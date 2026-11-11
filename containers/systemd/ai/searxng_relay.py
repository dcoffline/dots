#!/usr/bin/env python3
"""SearXNG -> Tavily-shape relay bridge for freellmapi custom search (#1174).

freellmapi's custom search relays speak Tavily's wire shape at
POST {base_url}/search with `Authorization: Bearer <key>` and a body of
{query, max_results, topic?}, expecting {results: [{title, url, content,
score?}]}. This bridge accepts that shape, forwards the query to SearXNG's
JSON API, and re-shapes the response.

Runs inside the `homelab.network` podman network (container DNS searxng-relay),
no host port published. Auth is a shared bearer token mounted read-only.

Stdlib only (python:3.12-alpine, no pip install step).
"""
import hmac
import json
import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SEARXNG_UPSTREAM = os.environ.get('SEARXNG_UPSTREAM', 'http://searxng:8080')
AUTH_TOKEN_FILE = os.environ.get('AUTH_TOKEN_FILE', '/run/relay-token')
LISTEN_PORT = int(os.environ.get('LISTEN_PORT', '8080'))
MAX_CONTENT_CHARS = 1200  # match freellmapi's EXTRACT_CHARS
REQUEST_TIMEOUT = 10.0


def load_token():
    try:
        with open(AUTH_TOKEN_FILE, 'r', encoding='utf-8') as fh:
            return fh.read().strip()
    except OSError as exc:
        print(f'[relay] FATAL: cannot read token file {AUTH_TOKEN_FILE}: {exc}')
        raise SystemExit(1)


TOKEN = load_token()


def do_search(query, max_results, topic):
    params = {'q': query, 'format': 'json'}
    if topic == 'news':
        params['categories'] = 'news'
    url = SEARXNG_UPSTREAM + '/search?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
        payload = json.loads(resp.read().decode('utf-8'))

    seen, hits = set(), []
    for row in payload.get('results', []):
        url_out = row.get('url') or ''
        if not url_out or url_out in seen:
            continue
        seen.add(url_out)
        content = row.get('content') or ''
        hits.append({
            'title': row.get('title') or url_out,
            'url': url_out,
            'content': content[:MAX_CONTENT_CHARS],
            'score': row.get('score') if isinstance(row.get('score'), (int, float)) else float(len(hits)),
        })
        if len(hits) >= max_results:
            break
    return hits


class RelayHandler(BaseHTTPRequestHandler):
    server_version = 'searxng-relay/1.0'

    def log_message(self, fmt, *args):  # quiet-ish: one line per request
        print(f'[relay] {self.address_string()} {fmt % args}')

    def _json(self, status, obj):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/health':
            self._json(200, {'ok': True})
            return
        self._json(404, {'error': 'not found'})

    def do_POST(self):
        if self.path != '/search':
            self._json(404, {'error': 'not found'})
            return

        auth = self.headers.get('Authorization', '')
        expected = 'Bearer ' + TOKEN
        if not hmac.compare_digest(auth, expected):
            self._json(401, {'error': {'message': 'unauthorized', 'type': 'authentication_error'}})
            return

        try:
            length = int(self.headers.get('Content-Length', '0'))
            body = json.loads(self.rfile.read(length).decode('utf-8')) if length else {}
        except (ValueError, UnicodeDecodeError):
            self._json(400, {'error': {'message': 'invalid JSON body', 'type': 'invalid_request_error'}})
            return

        query = (body.get('query') or '').strip()
        if not query:
            self._json(400, {'error': {'message': '`query` is required', 'type': 'invalid_request_error'}})
            return
        max_results = body.get('max_results') or 5
        try:
            max_results = max(1, min(int(max_results), 20))
        except (TypeError, ValueError):
            max_results = 5
        topic = body.get('topic')

        try:
            hits = do_search(query, max_results, topic)
        except Exception as exc:  # noqa: BLE001 - upstream or parse failure
            print(f'[relay] search failed: {exc}')
            self._json(502, {'error': {'message': f'searxng upstream error: {exc}', 'type': 'server_error'}})
            return

        self._json(200, {'results': hits})


if __name__ == '__main__':
    print(f'[relay] listening on :{LISTEN_PORT}, upstream={SEARXNG_UPSTREAM}')
    ThreadingHTTPServer(('0.0.0.0', LISTEN_PORT), RelayHandler).serve_forever()
