#!/usr/bin/env python3
"""
ZCC GHL Webhook Watcher — one-shot watchdog.

Watches /opt/data/logs/zcc_v2_queue.jsonl for a NEW webhook-delivered event
(source == 'ghl_webhook', type == reply/lead_new) whose contact_id is not a
test artifact. Prints the event (JSON) so the cron delivery surfaces it; stays
SILENT (empty output) when nothing new and real has arrived — so it only
produces noise when Eric should look.

Usage: python3 zcc_webhook_watch.py
"""
import json
import os

QUEUE = "/opt/data/logs/zcc_v2_queue.jsonl"
SEEN = "/opt/data/logs/zcc_v2_webhook_seen.txt"
TEST_MARKS = ("E2E", "E2E2", "TEST", "GHLTEST", "test-lead")

def main():
    seen = set()
    if os.path.exists(SEEN):
        with open(SEEN) as f:
            seen = set(f.read().splitlines())

    fresh = []
    if os.path.exists(QUEUE):
        with open(QUEUE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    evt = json.loads(line)
                except Exception:
                    continue
                if evt.get("source") != "ghl_webhook":
                    continue
                cid = str(evt.get("contact_id") or "")
                key = f"{evt.get('queued_at')}|{cid}"
                if key in seen or not cid:
                    continue
                if any(t in cid for t in TEST_MARKS):
                    continue
                fresh.append(evt)

    if fresh:
        with open(SEEN, "a") as f:
            for e in fresh:
                f.write(f"{e.get('queued_at')}|{e.get('contact_id')}\n")
        # emit (delivered by cron) only the NEW real events
        for e in fresh:
            print(json.dumps(e))

if __name__ == "__main__":
    main()