#!/usr/bin/env bash
# freellmapi zero-keys watchdog — silent when healthy; ONE alert line when the api_keys table is empty.
set -uo pipefail
DB="$HOME/.local/share/freellmapi/data/freeapi.db"
STATE="$HOME/.local/share/hermes/state/freellm_zero_keys.state"
mkdir -p "$(dirname "$STATE")"

COUNT=$(distrobox-host-exec podman exec freellmapi node -e '
const db=require("better-sqlite3")("/app/server/data/freeapi.db");
let n=0; try{ n=db.prepare("select count(*) c from api_keys").get().c; }catch(e){ n=-1; }
console.log(n);' 2>/dev/null || echo ERR)

if [ "$COUNT" -gt 0 ] 2>/dev/null; then
  rm -f "$STATE"   # healthy: clear suppression
  exit 0
fi

# Unhealthy (0 keys, unreadable db, or container/db unreachable)
if [ -f "$STATE" ]; then
  FIRST=$(cat "$STATE")
  NOW=$(date +%s)
  AGE=$(( NOW - FIRST ))
  if [ "$AGE" -lt 1800 ]; then
    exit 0   # grace window: quiet for first 30m
  fi
  # already alerted once at grace expiry; re-alert at most every 12h
  LASTALERT=$(cat "$STATE.alert" 2>/dev/null || echo 0)
  if [ $(( NOW - LASTALERT )) -lt 43200 ]; then
    exit 0
  fi
else
  date +%s > "$STATE"
  exit 0
fi

date +%s > "$STATE.alert"
REASON="api_keys count=$COUNT"
case "$COUNT" in
  0) REASON="api_keys table is EMPTY (all provider keys lost / DB reset)" ;;
  -1) REASON="api_keys table unreadable (DB schema changed or corrupted)" ;;
  ERR) REASON="freellmapi container or DB unreachable" ;;
esac
echo "🚨 freellmapi: $REASON — completions will 401 upstream. Re-add provider keys at freellm.hemati.com, then sync the unified API key to vane + ~/.secrets (FREELLMAPI_API_KEY). Persists since $(date -d @$FIRST '+%b %d %H:%M' 2>/dev/null || echo 'grace start')."
exit 0
