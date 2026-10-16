#!/usr/bin/env python3
"""zcc_queue_watch.py — watchdog for /opt/data/logs/zcc_v2_queue.jsonl

Emit a STABLE, hash-eligible digest of UNPROCESSED ZCC events currently in the
queue. When the webhook (or detector fallback) appends a NEW event that the
shepherd hasn't processed yet, the output changes and the Hermes monitor
harness fires the shepherd agent immediately (wake-within-seconds instead of a
fixed poll interval).

Stable output rules:
  - Only lines whose queued_at+conversation_id is NOT in
    /opt/data/logs/zcc_v2_processed.txt are included (processed = already
    dispatched; re-firing on them would loop).
  - Sorted by queued_at so ordering never changes.
  - No timestamps; the event's own queued_at is part of the digest (it only
    changes when an event is appended).
  - Empty output when nothing unprocessed -> monitor suppresses the run.

Used as `monitor_script` for the ZCC Shepherd cron job.
"""
import json
import os
import sys

QUEUE_FILE = "/opt/data/logs/zcc_v2_queue.jsonl"
PROCESSED_FILE = "/opt/data/logs/zcc_v2_processed.txt"


def load_processed():
    try:
        with open(PROCESSED_FILE) as f:
            return set(line.strip() for line in f if line.strip())
    except OSError:
        return set()


def main():
    if not os.path.isfile(QUEUE_FILE):
        return
    processed = load_processed()
    pending = []
    try:
        with open(QUEUE_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    evt = json.loads(line)
                except json.JSONDecodeError:
                    continue
                old_key = evt.get("queued_at", "") + (evt.get("conversation_id") or "")
                new_key = "|".join([
                    evt.get("queued_at", ""),
                    str(evt.get("conversation_id") or ""),
                    str(evt.get("contact_id") or ""),
                    str(evt.get("opportunity_id") or ""),
                ])
                if old_key in processed or new_key in processed:
                    continue
                pending.append((evt.get("queued_at", ""), evt))
    except OSError:
        return
    pending.sort(key=lambda x: x[0])
    out = []
    for _, evt in pending:
        body = (evt.get("lastMessageBody") or "").replace("\n", " ")[:120]
        out.append(
            f"{evt.get('queued_at','')}|{evt.get('type','')}|"
            f"{evt.get('contact_id','')}|{evt.get('conversation_id','')}|{body}"
        )
    sys.stdout.write("\n".join(out) + ("\n" if out else ""))


if __name__ == "__main__":
    main()
