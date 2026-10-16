#!/usr/bin/env python3
"""zcc_detector.py v4 (rebuild 2026-10-15) — ZCC opportunity-cursor detector.

Single-pass, no_agent cron script (every 5m). WATCH-ONLY: polls GHL
/opportunities/search per pipeline (status=open), enqueues a `lead_new` event
for every opportunity created after the persisted per-pipeline cursor, then
advances the cursor. NEVER sends/moves/tags.

Rebuild context: the v3 script was deleted from ~/.hermes/scripts ~Oct 8-9
(unrecoverable — scripts lived in no git tree). Canonical copy now lives in
~/src/dots/scripts/zcc/ with a symlink from ~/.hermes/scripts/. Contracts
preserved from v3 (zcc-v2-shepherd skill):
  - queue:   /opt/data/logs/zcc_v2_queue.jsonl (append-only JSONL)
  - state:   /opt/data/logs/zcc_v2_state.json (cursor_per_pipeline, last_poll_ts)
  - log:     /opt/data/logs/zcc_v2_detector.log
  - event:   lead_new with pipeline/category in {Sales, Recruits, Groups};
             routing (orchestrator): Sales+Groups -> Stan, Recruits -> Mikayla
  - dedup:   per-pipeline cursor only; at-least-once append before cursor write
  - silence: healthy pass prints NOTHING to stdout (watchdog owns alerts);
             errors go to the log + exit 1 (watchdog alerts on stale heartbeat)

Exclusion: contacts tagged `no workflows` (tag-only rule; never domain-based).
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

SCRIPTS_DIR = "/opt/data/scripts"
LOG_FILE = "/opt/data/logs/zcc_v2_detector.log"
STATE_FILE = "/opt/data/logs/zcc_v2_state.json"
QUEUE_FILE = "/opt/data/logs/zcc_v2_queue.jsonl"

PIPELINES = {
    "FAGqET8PrBblQgxufjA7": "Sales",
    "nQGTohT8IcOSq60kcP2Q": "Recruits",
    "XP33pIgYevesfdMZkM9V": "Groups",
}
GHL_BASE = "https://services.leadconnectorhq.com"
MAX_PAGES = 5
EXCLUDE_TAG = "no workflows"


def log(msg, level="INFO"):
    line = f"[{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC] [{level}] {msg}"
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def load_env_file():
    """os.environ.setdefault from /opt/data/.env (established Hermes pattern)."""
    try:
        with open("/opt/data/.env") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    except OSError:
        pass


def ghl_get(path, params, api_key):
    url = f"{GHL_BASE}{path}?{urllib.parse.urlencode(params)}"
    # GHL sits behind Cloudflare, which 403s the default "Python-urllib/x" UA
    # (verified 2026-10-15: same key 403s without / 200s with a normal UA).
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {api_key}",
        "Version": "2021-07-28",
        "Accept": "application/json",
        "User-Agent": "zcc-detector/4.0",
    })
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.loads(resp.read().decode())


def to_ms(iso):
    """GHL createdAt (ISO 8601 UTC) -> epoch ms; 0 on parse failure."""
    if not iso:
        return 0
    try:
        return int(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def load_state():
    with open(STATE_FILE) as f:
        return json.load(f)


def save_state(state):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1)
    os.replace(tmp, STATE_FILE)


def fetch_open_opps(api_key, location_id, pipeline_id):
    """All open opps for a pipeline, following meta.nextPageUrl (capped)."""
    out, page = [], 0
    params = {
        "location_id": location_id,
        "pipeline_id": pipeline_id,
        "status": "open",
        "limit": 100,
    }
    while True:
        page += 1
        d = ghl_get("/opportunities/search", params, api_key)
        out.extend(d.get("opportunities", []))
        nxt = (d.get("meta") or {}).get("nextPageUrl")
        if not nxt or page >= MAX_PAGES:
            break
        q = urllib.parse.urlparse(nxt)
        params = {k: v[0] for k, v in urllib.parse.parse_qs(q.query).items()}
    return out


def build_event(opp, pipeline_name, now_iso):
    contact = opp.get("contact") or {}
    tags = contact.get("tags") or []
    evt = {
        "type": "lead_new",
        "conversation_id": None,
        "contact_id": opp.get("contactId"),
        "opportunity_id": opp.get("id"),
        "name": opp.get("name") or contact.get("name") or "Unknown",
        "email": contact.get("email") or "",
        "pipeline": pipeline_name,
        "category": pipeline_name,
        "pipeline_stage_id": opp.get("pipelineStageId") or "",
        "tags": tags,
        "createdAt": opp.get("createdAt"),
        "lastMessageBody": "",
        "lastMessageDirection": "none",
        "lastMessageDate": opp.get("createdAt"),
        "source": "ghl_poller_v4",
        "queued_at": now_iso,
    }
    return evt


def main():
    load_env_file()
    api_key = os.environ.get("GHL_API_KEY")
    location_id = os.environ.get("GHL_LOCATION_ID")
    if not api_key or not location_id:
        log("missing GHL_API_KEY/GHL_LOCATION_ID after env load", "ERROR")
        sys.exit(1)

    state = load_state()
    cursors = state.setdefault("cursor_per_pipeline", {p: 0 for p in PIPELINES})
    queued_total = 0
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    for pid, pname in PIPELINES.items():
        try:
            opps = fetch_open_opps(api_key, location_id, pid)
        except Exception as e:
            log(f"{pname}: poll failed: {e}", "ERROR")
            sys.exit(1)

        cursor = int(cursors.get(pid, 0))
        fresh = []
        max_ms = cursor
        for opp in opps:
            created = to_ms(opp.get("createdAt"))
            if created <= cursor:
                continue
            max_ms = max(max_ms, created)
            contact_tags = ((opp.get("contact") or {}).get("tags")) or []
            if EXCLUDE_TAG in contact_tags:
                continue
            fresh.append(build_event(opp, pname, now_iso))

        if fresh:
            with open(QUEUE_FILE, "a") as f:
                for evt in fresh:
                    f.write(json.dumps(evt) + "\n")
            cursors[pid] = max_ms
            queued_total += len(fresh)
        log(f"{pname}: scanned={len(opps)} fresh={len(fresh)} cursor={cursors[pid]}")

    state["last_poll_ts"] = int(time.time() * 1000)
    save_state(state)
    log(f"Single pass complete (v4): queued {queued_total} event(s)")
    # Healthy pass: silent stdout (watchdog owns alerting).


if __name__ == "__main__":
    main()
