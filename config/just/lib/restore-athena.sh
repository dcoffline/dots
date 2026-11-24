#!/usr/bin/env bash
# Restores all dev projects, Hermes state, Quadlets, Systemd units, Gemini & Secrets
set -euo pipefail

BACKUP_BASE="$HOME/.mnt/10T/Backups/Athena"
SOURCE_DIR="${1:-}"

if [ -z "$SOURCE_DIR" ]; then
  if [ -L "$BACKUP_BASE/latest" ] && [ -d "$BACKUP_BASE/latest" ]; then
    SOURCE_DIR="$(cd "$BACKUP_BASE/latest" && pwd -P)"
  else
    NEWEST_DIR="$(ls -1dt "$BACKUP_BASE"/athena_* 2>/dev/null | head -n 1 || true)"
    if [ -n "$NEWEST_DIR" ] && [ -d "$NEWEST_DIR" ]; then
      SOURCE_DIR="$(cd "$NEWEST_DIR" && pwd)"
    else
      echo "❌ Error: No backups found in '$BACKUP_BASE'." >&2
      exit 1
    fi
  fi
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "❌ Error: Backup source directory '$SOURCE_DIR' does not exist." >&2
  exit 1
fi

echo "================================================================"
echo " Starting Athena & Project Base Restoration Protocol"
echo " Source Snapshot: $SOURCE_DIR"
echo " Target Host:     $HOME ($(whoami)@$(hostname))"
echo "================================================================"

if [ -f "$SOURCE_DIR/manifest.json" ]; then
  echo "Snapshot Manifest:"
  grep -E '"(timestamp|created_at|total_size)"' "$SOURCE_DIR/manifest.json" || true
fi

read -p "⚠️  Are you sure you want to restore from this snapshot? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Restoration cancelled by user."
  exit 0
fi

START_TIME=$(date +%s)

# 1. Restore Development Projects
if [ -d "$SOURCE_DIR/projects" ]; then
  echo "[ 1/7 ] Restoring development projects (~/src/projects/)..."
  mkdir -p "$HOME/src/projects"
  rsync -a "$SOURCE_DIR/projects/" "$HOME/src/projects/"
  if [ -d "$HOME/src/projects/pka-web" ] && [ ! -e "$HOME/src/projects/Athena" ]; then
    ln -s pka-web "$HOME/src/projects/Athena"
  fi
  echo "  ✓ Projects restored."
fi

# 2. Restore Hermes Agent Runtime State
if [ -d "$SOURCE_DIR/hermes" ]; then
  echo "[ 2/7 ] Restoring Hermes / Athena runtime state (~/.local/share/hermes/)..."
  mkdir -p "$HOME/.local/share/hermes"
  rsync -a "$SOURCE_DIR/hermes/" "$HOME/.local/share/hermes/"
  echo "  ✓ Hermes runtime state restored."
fi

# 3. Restore Homelab Quadlets
if [ -d "$SOURCE_DIR/quadlets" ]; then
  echo "[ 3/7 ] Restoring Homelab Quadlets (~/.config/containers/systemd/)..."
  mkdir -p "$HOME/.config/containers/systemd"
  rsync -a "$SOURCE_DIR/quadlets/" "$HOME/.config/containers/systemd/"
  echo "  ✓ Quadlet definitions restored."
fi

# 4. Restore Systemd User Units
if [ -d "$SOURCE_DIR/systemd_user" ]; then
  echo "[ 4/7 ] Restoring Systemd User Units (~/.config/systemd/user/)..."
  mkdir -p "$HOME/.config/systemd/user"
  rsync -a "$SOURCE_DIR/systemd_user/" "$HOME/.config/systemd/user/"
  echo "  ✓ Systemd user units restored."
fi

# 5. Restore Gemini & Antigravity Config
if [ -d "$SOURCE_DIR/gemini" ]; then
  echo "[ 5/7 ] Restoring Gemini & Antigravity config (~/.gemini/)..."
  mkdir -p "$HOME/.gemini"
  rsync -a "$SOURCE_DIR/gemini/" "$HOME/.gemini/"
  echo "  ✓ Gemini / Antigravity config restored."
fi

# 6. Restore Secrets & Environment
if [ -d "$SOURCE_DIR/secrets" ]; then
  echo "[ 6/7 ] Restoring Secrets & Environment configs..."
  if [ -f "$SOURCE_DIR/secrets/.secrets" ]; then
    cp -p "$SOURCE_DIR/secrets/.secrets" "$HOME/.secrets"
    chmod 600 "$HOME/.secrets"
  fi
  if [ -d "$SOURCE_DIR/secrets/environment.d" ]; then
    mkdir -p "$HOME/.config/environment.d"
    cp -rp "$SOURCE_DIR/secrets/environment.d/"* "$HOME/.config/environment.d/" 2>/dev/null || true
  fi
  if [ -f "$SOURCE_DIR/secrets/rclone.conf" ]; then
    mkdir -p "$HOME/.config/rclone"
    cp -p "$SOURCE_DIR/secrets/rclone.conf" "$HOME/.config/rclone/rclone.conf"
    chmod 600 "$HOME/.config/rclone/rclone.conf"
  fi
  echo "  ✓ Secrets & environment configs restored (chmod 600)."
fi

# 7. Restore Athena Gem Obsidian Notes
if [ -d "$SOURCE_DIR/notes_athena" ]; then
  echo "[ 7/7 ] Restoring Athena Gem Notes..."
  mkdir -p "$HOME/Documents/Notes/Hemati/projects/Athena_Gem"
  rsync -a "$SOURCE_DIR/notes_athena/" "$HOME/Documents/Notes/Hemati/projects/Athena_Gem/"
  echo "  ✓ Athena Gem notes restored."
fi

# Post-restore
echo "================================================================"
echo " Reloading systemd user daemon..."
systemctl --user daemon-reload 2>/dev/null || true

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "================================================================"
echo " ✅ Athena & Project Base Restoration COMPLETED successfully!"
echo " Source:    $SOURCE_DIR"
echo " Elapsed:   ${DURATION}s"
echo "================================================================"
