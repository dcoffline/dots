#!/bin/sh
# scrob entrypoint - patched copy of upstream bellamy/scrob /entrypoint.sh
# (2026-11-15): upstream chmods /dev/stdout and /dev/stderr o+w, which fails
# under rootless podman (bind-mounted fds are not writable) and set -e aborts
# the container. This copy drops those two chmod lines. Lives in the dots repo
# (source of truth) instead of the old 2T path that was lost in cleanup.
set -e

PUID=${PUID:-1000}
PGID=${PGID:-1000}
BACKEND_PORT=${BACKEND_PORT:-7331}
export BACKEND_PORT

# Timezone
if [ -n "$TZ" ]; then
    ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime 2>/dev/null || echo "Could not set /etc/localtime, keeping the existing one"
    echo "$TZ" > /etc/timezone 2>/dev/null || true
fi

# Fix ownership so the scrob user can write to the data directory
chown -R "$PUID:$PGID" /app/backend/data

echo "Running database migrations..."
cd /app/backend
su-exec "$PUID:$PGID" .venv/bin/python -m alembic upgrade head

echo "Starting Scrob (frontend :7330, backend 127.0.0.1:${BACKEND_PORT})..."
exec su-exec "$PUID:$PGID" /usr/local/bin/supervisord -n -c /etc/supervisor/supervisord.conf
