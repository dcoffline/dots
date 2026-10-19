#!/usr/bin/env python3
"""Pre-push secret scanner for the dots repo.

Blocks a push if any STAGED (or diff-provided) content contains credential-
bearing URLs — the class of leak that hit the aiostreams homepage.href
(Jellyfin picker blob, api_password, debrid keys).

Exit 0 = clean. Exit 1 = leak candidates found (prints them with line refs).
Designed for `git config core.hooksPath .githooks` (hook: pre-push) or
ad-hoc runs: `python3 .githooks/secret_scan.py --staged`.
"""
import re
import subprocess
import sys

# Credential-bearing URL patterns (path or query components)
PATTERNS = [
    # Jellyfin/AIOStreams picker URLs with embedded auth blob
    r"/jellyfin/[0-9a-f-]{36}/[A-Za-z0-9_\-=]{20,}",
    # Generic credential query params in any URL
    r"[?&](api_password|api_key|apikey|api_key|access_token|auth_token|token)=",
    # debrid / proxy URLs with embedded keys
    r"torrentio\.strem\.fun/resolve/realdebrid/[A-Za-z0-9]{20,}",
    r"debridmediamanager\.com/api/stremio/[A-Za-z0-9]{12,}",
    r"real-debrid\.com/(d|api)/[A-Za-z0-9]{8,}",
    r"alldebrid\.com/[a-z]/[A-Za-z0-9]{8,}",
    r"premiumize\.[a-z]+/.*[?&]apikey=",
    # Long JWT-ish blobs are matched by JWT_PATTERN below (NOT here).
]

# JWTs: case-sensitive by construction (header is base64 of '{"' -> always 'eyJ'),
# full 3-segment h.P.s shape. A loose case-insensitive eyJ scan false-positives on
# random base64 — 2026-10-17: a ~340KB dconf playback-history line (JPEG art as
# data:image/jpeg;base64) contained 8 case-insensitive 'EyJ/EYj' shapes and blocked
# every push. Real JWT = dot-separated header.payload.signature.
JWT_PATTERN = r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"

COMPILED = [re.compile(p, re.IGNORECASE) for p in PATTERNS] + [re.compile(JWT_PATTERN)]
ALLOWLIST = [
    r"example\.com", r"your-instance-url", r"<MASKED>", r"aiostreams\.hemati\.com/jellyfin/\$",
]

if len(sys.argv) > 1 and sys.argv[1] != "--stdin":
    SOURCE = sys.argv[1]
elif len(sys.argv) > 1 and sys.argv[1] == "--stdin":
    SOURCE = sys.stdin.buffer.read().decode("utf-8", errors="replace")
else:
    SOURCE = "--staged"

if SOURCE == "--staged":
    diff = subprocess.run(
        ["git", "diff", "--cached", "-U0"],
        capture_output=True, text=True,
    )
    body = diff.stdout
else:
    body = SOURCE

findings = []
current_file = ""
for lineno, line in enumerate(body.splitlines(), 1):
    if line.startswith("+++ "):
        current_file = line[4:].lstrip("b/").split("\t")[0]
        continue
    if line.startswith(("-", "+++", "---", "@@")):
        continue
    # secrets-class files are credential-bearing BY DESIGN — the git-crypt
    # gate (in pre-push) is what protects them, not this URL scan.
    if current_file.endswith(".secrets") or current_file.endswith(".secret") or current_file.endswith("rclone.conf"):
        continue
    if any(re.search(a, line) for a in ALLOWLIST):
        continue
    for c in COMPILED:
        m = c.search(line)
        if m:
            findings.append((lineno, c.pattern[:40], line.strip()[:140]))
            break

if findings:
    print("SECRET-SCAN: potential credential leaks found:")
    for lineno, pat, line in findings:
        print(f"  line {lineno} [{pat}...]: {line}")
    sys.exit(1)

print("secret-scan: clean")
