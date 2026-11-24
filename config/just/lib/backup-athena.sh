#!/usr/bin/env bash
# Backs up all dev projects, Hermes state, Quadlets, Systemd units, Gemini & Secrets (keeps 7)
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TARGET_DIR="${1:-$HOME/.mnt/10T/Backups/Athena}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$TARGET_DIR/athena_$TIMESTAMP"
LATEST_LINK="$TARGET_DIR/latest"
RETENTION_COUNT=7
START_TIME=$(date +%s)

echo "================================================================"
echo " Starting Athena & Project Base Backup Protocol"
echo " Destination: $BACKUP_DIR"
echo " Timestamp:   $TIMESTAMP"
echo "================================================================"

if [ ! -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR" 2>/dev/null || {
    echo "❌ Error: Target directory '$TARGET_DIR' is not accessible." >&2
    exit 1
  }
fi

if [ ! -w "$TARGET_DIR" ]; then
  echo "❌ Error: Target directory '$TARGET_DIR' is not writable." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

# 1. Back up All Development Projects (~/src/projects/)
echo "[ 1/7 ] Backing up development projects (~/src/projects/)..."
mkdir -p "$BACKUP_DIR/projects"
if [ -d "$HOME/src/projects" ]; then
  safe_rsync -a \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.venv' \
    --exclude='venv' \
    --exclude='.pytest_cache' \
    --exclude='.ruff_cache' \
    --exclude='target/' \
    "$HOME/src/projects/" "$BACKUP_DIR/projects/"
  echo "  ✓ Projects backed up: $(ls -1 "$HOME/src/projects" | tr '\n' ' ')"
else
  echo "  ⚠️ Warning: $HOME/src/projects not found, skipping."
fi

# 2. Back up Hermes / Athena Agent Runtime State (~/.local/share/hermes/)
echo "[ 2/7 ] Backing up Hermes / Athena agent state (~/.local/share/hermes/)..."
mkdir -p "$BACKUP_DIR/hermes"
if [ -d "$HOME/.local/share/hermes" ]; then
  safe_rsync -a \
    --exclude='.cache' \
    --exclude='.npm' \
    --exclude='.google-venv' \
    --exclude='lazy-packages' \
    --exclude='usr' \
    --exclude='bin' \
    --exclude='home' \
    --exclude='audio_cache' \
    --exclude='image_cache' \
    --exclude='tmp' \
    --exclude='logs' \
    --exclude='transcripts' \
    --exclude='*.sock' \
    --exclude='*.pid' \
    --exclude='*.lock' \
    --exclude='*.db-shm' \
    "$HOME/.local/share/hermes/" "$BACKUP_DIR/hermes/"
  echo "  ✓ Hermes runtime state backed up."
else
  echo "  ⚠️ Warning: $HOME/.local/share/hermes not found, skipping."
fi

# 3. Back up Homelab Quadlet Definitions (~/.config/containers/systemd/)
echo "[ 3/7 ] Backing up Homelab Quadlets (~/.config/containers/systemd/)..."
mkdir -p "$BACKUP_DIR/quadlets"
if [ -d "$HOME/.config/containers/systemd" ]; then
  safe_rsync -a "$HOME/.config/containers/systemd/" "$BACKUP_DIR/quadlets/"
  echo "  ✓ Quadlets backed up ($(find "$BACKUP_DIR/quadlets" -type f | wc -l) files)."
else
  echo "  ⚠️ Warning: Quadlets directory not found, skipping."
fi

# 4. Back up Systemd User Units & Timers (~/.config/systemd/user/)
echo "[ 4/7 ] Backing up Systemd User Units (~/.config/systemd/user/)..."
mkdir -p "$BACKUP_DIR/systemd_user"
if [ -d "$HOME/.config/systemd/user" ]; then
  safe_rsync -a "$HOME/.config/systemd/user/" "$BACKUP_DIR/systemd_user/"
  echo "  ✓ Systemd user units backed up ($(find "$BACKUP_DIR/systemd_user" -type f | wc -l) files)."
else
  echo "  ⚠️ Warning: Systemd user directory not found, skipping."
fi

# 5. Back up Gemini & Antigravity Config (~/.gemini/)
echo "[ 5/7 ] Backing up Gemini / Antigravity config (~/.gemini/)..."
mkdir -p "$BACKUP_DIR/gemini"
if [ -d "$HOME/.gemini" ]; then
  safe_rsync -a \
    --exclude='brain' \
    --exclude='bin' \
    --exclude='tmp' \
    --exclude='*.log' \
    --exclude='cache' \
    --exclude='crashes' \
    --exclude='conversations' \
    "$HOME/.gemini/" "$BACKUP_DIR/gemini/"
  echo "  ✓ Gemini / Antigravity configs backed up."
else
  echo "  ⚠️ Warning: $HOME/.gemini not found, skipping."
fi

# 6. Back up Secrets and Environment Configurations
echo "[ 6/7 ] Backing up Secrets & Environment configs..."
mkdir -p "$BACKUP_DIR/secrets"
if [ -f "$HOME/.secrets" ]; then
  cp -p "$HOME/.secrets" "$BACKUP_DIR/secrets/.secrets"
fi
if [ -d "$HOME/.config/environment.d" ]; then
  mkdir -p "$BACKUP_DIR/secrets/environment.d"
  cp -rp "$HOME/.config/environment.d/"* "$BACKUP_DIR/secrets/environment.d/" 2>/dev/null || true
fi
if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
  cp -p "$HOME/.config/rclone/rclone.conf" "$BACKUP_DIR/secrets/rclone.conf"
fi
find "$BACKUP_DIR/secrets" -type d -exec chmod 700 {} + 2>/dev/null || true
find "$BACKUP_DIR/secrets" -type f -exec chmod 600 {} + 2>/dev/null || true
echo "  ✓ Secrets & environment configs backed up (chmod 600)."

# 6b. Back up freellmapi app state (DB with api keys/settings — lost once already, 2026-11-11)
echo "[ 6b ] Backing up freellmapi state (~/.local/share/freellmapi/)..."
mkdir -p "$BACKUP_DIR/freellmapi"
if [ -d "$HOME/.local/share/freellmapi" ]; then
  # data/ is owned by the rootless-podman subuid (525287), mode 700. podman unshare
  # enters eric's user namespace, where that subuid is readable, so no sudo needed.
  # /home is a symlink the namespace can't trust, so pass resolved real paths.
  podman unshare rsync -a --no-owner --no-group --exclude='*.sock' \
    "$(readlink -f "$HOME/.local/share/freellmapi")/" \
    "$(readlink -f "$BACKUP_DIR/freellmapi")/"
  echo "  ✓ freellmapi state backed up."
else
  echo "  ℹ️ freellmapi dir not found, skipping."
fi

# 7. Back up Athena Gem Obsidian Project Notes
echo "[ 7/7 ] Backing up Athena Gem Notes..."
mkdir -p "$BACKUP_DIR/notes_athena"
NOTES_SRC="$HOME/Documents/Notes/Hemati/projects/Athena_Gem"
if [ -d "$NOTES_SRC" ]; then
  safe_rsync -a "$NOTES_SRC/" "$BACKUP_DIR/notes_athena/"
  echo "  ✓ Athena Gem notes backed up."
else
  echo "  ℹ️ Notes directory $NOTES_SRC not found, skipping."
fi

# Manifest
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')

cat <<EOF > "$BACKUP_DIR/manifest.json"
{
  "timestamp": "$TIMESTAMP",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$(hostname)",
  "user": "$(whoami)",
  "total_size": "$TOTAL_SIZE",
  "duration_seconds": $DURATION,
  "components": {
    "projects": $(if [ -d "$BACKUP_DIR/projects" ]; then echo "true"; else echo "false"; fi),
    "hermes": $(if [ -d "$BACKUP_DIR/hermes" ]; then echo "true"; else echo "false"; fi),
    "quadlets": $(if [ -d "$BACKUP_DIR/quadlets" ]; then echo "true"; else echo "false"; fi),
    "systemd_user": $(if [ -d "$BACKUP_DIR/systemd_user" ]; then echo "true"; else echo "false"; fi),
    "gemini": $(if [ -d "$BACKUP_DIR/gemini" ]; then echo "true"; else echo "false"; fi),
    "secrets": $(if [ -d "$BACKUP_DIR/secrets" ]; then echo "true"; else echo "false"; fi),
    "notes_athena": $(if [ -d "$BACKUP_DIR/notes_athena" ]; then echo "true"; else echo "false"; fi)
  }
}
EOF

# Symlink to latest
ln -sfn "athena_$TIMESTAMP" "$LATEST_LINK"

# Retention
echo "================================================================"
echo " Managing backup retention (keeping $RETENTION_COUNT most recent)..."
PRUNED_COUNT="$(prune_old_backups "$TARGET_DIR" "athena_" "$RETENTION_COUNT")"
if [ "$PRUNED_COUNT" -gt 0 ]; then
  echo "  ✓ Pruned $PRUNED_COUNT old backup(s)."
else
  echo "  ✓ No old backups required pruning."
fi

echo "================================================================"
echo " ✅ Athena & Project Base Backup COMPLETED successfully!"
echo " Snapshot:  $BACKUP_DIR"
echo " Latest:    $LATEST_LINK"
echo " Size:      $TOTAL_SIZE"
echo " Elapsed:   ${DURATION}s"
echo "================================================================"
