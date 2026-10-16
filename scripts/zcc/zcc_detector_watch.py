#!/usr/bin/env python3
"""zcc_detector_watch.py v2 (rebuild 2026-10-15) — slim ZCC detector watchdog.

no_agent cron (every 2m). Silent (empty stdout, exit 0) when healthy. On any
fault: prints a LOUD alert line (stdout is delivered verbatim to the Discord
alerts channel), attempts `hermes cron resume 990979372bf7` (self-heal for the
paused-detector failure mode from the 2026-08-25 Bart Samson incident), exits 1
so the failure registers in cron state.

Faults detected:
  1. Detector script missing from ~/.hermes/scripts (the Oct 2026 prune loss)
  2. Detector state file missing (pipeline never ran / state wiped)
  3. last_poll_ts stale > STALE_MS (detector failing or its cron paused)

Dropped from v1: the badkey/FFL-16 heartbeat bridge (badkey was also pruned;
Discord stdout delivery is the alert channel now).
"""
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

STATE_FILE = "/opt/data/logs/zcc_v2_state.json"
DETECTOR_SCRIPT = os.path.expanduser("~/.hermes/scripts/zcc_detector.py")
DETECTOR_JOB = "990979372bf7"
STALE_MS = 15 * 60 * 1000  # detector runs every 5m; alert at 3 missed runs


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def try_resume():
    try:
        subprocess.run(
            ["/var/home/eric/.local/bin/hermes", "cron", "resume", DETECTOR_JOB],
            capture_output=True, timeout=30,
        )
    except Exception:
        pass


def main():
    if not os.path.exists(DETECTOR_SCRIPT):
        print(f"🚨 ZCC DETECTOR DOWN ({now_utc()}): {DETECTOR_SCRIPT} MISSING from disk. "
              f"Rebuild from ~/src/dots/scripts/zcc/ and resume cron {DETECTOR_JOB}.")
        sys.exit(1)

    if not os.path.exists(STATE_FILE):
        print(f"🚨 ZCC DETECTOR DOWN ({now_utc()}): {STATE_FILE} missing — detector never ran or state wiped.")
        sys.exit(1)

    import json
    with open(STATE_FILE) as f:
        state = json.load(f)
    last_poll = state.get("last_poll_ts", 0)
    age = int(time.time() * 1000) - int(last_poll)
    if age > STALE_MS:
        mins = age // 60000
        try_resume()
        print(f"🚨 ZCC DETECTOR STALE ({now_utc()}): last poll {mins} min ago "
              f"(threshold {STALE_MS // 60000} min). Attempted hermes cron resume {DETECTOR_JOB}. "
              f"If this repeats, the detector is failing — check zcc_v2_detector.log.")
        sys.exit(1)

    # Healthy: silent, exit 0.
    sys.exit(0)


if __name__ == "__main__":
    main()
