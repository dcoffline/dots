#!/usr/bin/env bash
# Mounts all cloud storage remotes via rclone (Auto-detects macOS vs Linux)
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

LOGFILE="/tmp/rclone-mount.log"
PID_DIR="$HOME/.config/rclone/pid"
OS_TYPE="$(uname -s)"
RCLONE="$(resolve_rclone_bin)"

# 1. OS-Specific Setup (Caches & Pre-flight checks)
if [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "[ macOS Detected - Running Mac Rclone Routine ]"
  CACHE_DIR="$HOME/Library/Caches/rclone"

  # macOS Pre-flight Internet check
  for i in {1..12}; do
    ping -c1 8.8.8.8 >/dev/null 2>&1 && break
    if [[ $i -eq 12 ]]; then
      echo "No internet" >&2
      exit 1
    fi
    sleep 5
  done
else
  echo "[ Linux Detected - Running Linux Rclone Routine ]"
  if [ -f /run/ostree-booted ]; then
    CACHE_DIR="$HOME/.mnt/2T/rclone_cache"
  else
    CACHE_DIR="$HOME/.cache/rclone_cache"
  fi
fi

# 2. Define COMMON_FLAGS
COMMON_FLAGS=(
  --vfs-cache-mode full
  --cache-dir "$CACHE_DIR"
  --drive-import-formats docx,xlsx,pptx
  --vfs-read-chunk-size=64M
  --vfs-cache-max-size=10G
  --vfs-cache-max-age=720h
  --log-file "$LOGFILE"
  --log-level INFO
  --exclude '.DS_Store'
  --exclude '._*'
  --exclude '.Trash*'
  --exclude '.Trash-1000/**'
  --exclude '.smart-env/**'
  --exclude '.obsidian/copilot-index*'
  --dir-cache-time 30m
  --poll-interval 1m
  --attr-timeout 10m
)

if [[ "$OS_TYPE" != "Darwin" ]]; then
  # Append Linux-specific flags
  COMMON_FLAGS+=(
    --allow-other
    --umask 002
    --dir-perms 775
    --file-perms 664
    --vfs-read-chunk-size-limit off
    --vfs-cache-min-free-space=20G
    --buffer-size 64M
  )
fi

# 3. Preparation
mkdir -p "$PID_DIR" "$RCLONE_BASE_MOUNT" "$CACHE_DIR"
just --justfile "$HOME/.justfile" unmount || true
pkill rclone 2>/dev/null || true
sleep 2

# Clean stale mountpoint directories
for remote in "${RCLONE_REMOTES[@]}"; do
  mountpoint="$RCLONE_BASE_MOUNT/$remote"
  if [ -d "$mountpoint" ] && ! mount | grep -Fq "$mountpoint"; then
    rmdir "$mountpoint" 2>/dev/null && mkdir -p "$mountpoint" || true
  else
    mkdir -p "$mountpoint"
  fi
done

# 4. Mount Loop
for remote in "${RCLONE_REMOTES[@]}"; do
  mountpoint="$RCLONE_BASE_MOUNT/$remote"

  EXTRA_FLAGS=()
  if [[ "$remote" == "RealDebrid" ]]; then
    EXTRA_FLAGS=( --read-only --dir-cache-time 10s --attr-timeout 1s --multi-thread-streams=0 --cutoff-mode=cautious )
  elif [[ "$remote" == "AllDebrid" ]]; then
    # AllDebrid-recommended: minimal cache, no multi-thread, cautious cutoff
    EXTRA_FLAGS=( --read-only --dir-cache-time 10s --attr-timeout 1s --multi-thread-streams=0 --cutoff-mode=cautious --vfs-cache-mode minimal --buffer-size 0 )
  elif [[ "$remote" == "Nextcloud" ]]; then
    EXTRA_FLAGS=( --dir-cache-time 10s --attr-timeout 1s )
    # On bee (where Nextcloud container runs), bypass Cloudflare tunnel and use local WebDAV
    if [[ "$OS_TYPE" != "Darwin" && "$(hostname -s)" == "bee" ]]; then
      EXTRA_FLAGS+=( --webdav-url "http://127.0.0.1:8088/remote.php/dav/files/eric" )
    fi
  else
    EXTRA_FLAGS=( --dir-cache-time 72h )
  fi

  if [[ "$OS_TYPE" == "Darwin" ]]; then
    EXTRA_FLAGS+=( --volname "$remote" )
  fi

  echo "Mounting $remote → $mountpoint"
  nohup "$RCLONE" mount "${remote}:" "$mountpoint" "${COMMON_FLAGS[@]}" "${EXTRA_FLAGS[@]}" >/dev/null 2>&1 &
  echo $! >"$PID_DIR/${remote}.pid"
  sleep 1
done

sleep 3
echo -e "\nMount commands issued."

# 5. Post-mount verification (debrid WebDAVs: auth can go stale silently)
sleep 3
for remote in "RealDebrid" "AllDebrid"; do
  mountpoint="$RCLONE_BASE_MOUNT/$remote"
  if ! is_mounted "$mountpoint"; then
    continue
  fi
  if ! run_with_timeout 5 ls "$mountpoint" >/dev/null 2>&1; then
    echo "⚠️ $remote mount did not respond to listing (auth stale or endpoint down). Unmounting."
    unmount_path "$mountpoint"
  fi
done
