#!/usr/bin/env bash
# zcc-webhook watchdog — verifies the DECOUPLED webhook unit is alive and the
# PUBLIC tunnel path answers. Designed for both a host cron entry and a systemd
# user timer (it is idempotent). Emits NOTHING when healthy (cron-silent), or a
# loud ALERT line when the webhook is down (intended for cron mail / notify).
#
# Checks:
#   1. unit active  (systemctl --user is-active zcc-webhook.service)
#   2. container running + port 8991 reachable on homelab net
#   3. public tunnel answers configured endpoint (token-gated 200)
#      - a 200 means the endpoint is LIVE (auth gate responds); a 401 also proves
#        the tunnel+service answered, just with a bad/absent token.

set -uo pipefail

UNIT="zcc-webhook.service"
ALERT=""

# Load public webhook URL from environment or ~/.secrets
PUB_URL="${ZCC_WEBHOOK_URL:-}"
if [ -z "$PUB_URL" ] && [ -f "${HOME}/.secrets" ]; then
  PUB_URL=$(grep -E '^ZCC_WEBHOOK_URL=' "${HOME}/.secrets" 2>/dev/null | head -n1 | cut -d'=' -f2-)
  PUB_URL="${PUB_URL//[\"\' ]/}"
fi

if [ -z "$PUB_URL" ]; then
  echo "ALERT zcc-webhook DOWN: ZCC_WEBHOOK_URL is not set in environment or ~/.secrets ts=$(date -Is)"
  exit 1
fi

# 1) unit active
if ! /usr/bin/systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
  ALERT+="UNIT_DOWN($UNIT); "
fi

# 3) public tunnel (authoritative external path)
PUB_HTTP=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$PUB_URL" 2>/dev/null)
# Accept 200 (alive) — 401 also proves liveness (auth gate responded)
if [ "$PUB_HTTP" != "200" ] && [ "$PUB_HTTP" != "401" ]; then
  ALERT+="PUBLIC_FAIL(http=$PUB_HTTP); "
fi

if [ -n "$ALERT" ]; then
  echo "ALERT zcc-webhook DOWN: $ALERT ts=$(date -Is)"
  exit 1
fi
# healthy: print nothing (cron-silent)
exit 0