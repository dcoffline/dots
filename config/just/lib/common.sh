#!/usr/bin/env bash
# Shared helpers and constants for ~/.justfile modules.
# Kept Bash 3.2-compatible so macOS stock /bin/bash works without issues.

RCLONE_BASE_MOUNT="$HOME/.mnt/rclone"
RCLONE_REMOTES=(
  Archive
  Backup
  GDrive
  Hematicom
  Nextcloud
  OneDrive
  Timeline
  RealDebrid
  AllDebrid
)

# Resolve canonical path to the dotfiles repository
resolve_dots_dir() {
  local raw="${DOTS:-$HOME/src/dots}"
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$raw" 2>/dev/null || echo "$raw"
  else
    echo "$raw"
  fi
}

# Resolve the rclone binary for macOS or Linux
resolve_rclone_bin() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if [ -x /usr/local/bin/rclone ]; then
      echo "/usr/local/bin/rclone"
    elif [ -x /opt/homebrew/bin/rclone ]; then
      echo "/opt/homebrew/bin/rclone"
    else
      echo "rclone"
    fi
  else
    if [ -x /home/linuxbrew/.linuxbrew/bin/rclone ]; then
      echo "/home/linuxbrew/.linuxbrew/bin/rclone"
    elif [ -x /usr/bin/rclone ]; then
      echo "/usr/bin/rclone"
    else
      echo "rclone"
    fi
  fi
}

# Check whether a path is currently mounted (Linux + macOS)
is_mounted() {
  local path="$1"
  mountpoint -q "$path" 2>/dev/null || mount | grep -Fq " on $path "
}

# Run a command with a timeout (uses GNU timeout if available, else Perl alarm for macOS)
run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
  fi
}

# Best-effort unmount of a FUSE/rclone mountpoint (Linux + macOS)
unmount_path() {
  local mountpoint="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    umount "$mountpoint" 2>/dev/null \
      || umount -f "$mountpoint" 2>/dev/null \
      || diskutil unmount force "$mountpoint" 2>/dev/null \
      || true
  else
    fusermount3 -uz "$mountpoint" 2>/dev/null \
      || fusermount -uz "$mountpoint" 2>/dev/null \
      || fusermount -u "$mountpoint" 2>/dev/null \
      || true
  fi
}

# Auto-clear a stale rclone bisync lockfile if the owning PID is no longer alive
clear_stale_bisync_lock() {
  local lockfile="$1"
  if [ -f "$lockfile" ]; then
    local lock_pid
    lock_pid=$(jq -r '.PID // empty' "$lockfile" 2>/dev/null \
      || grep -o '"PID": *"[0-9]*"' "$lockfile" | grep -o '[0-9]*' \
      || true)
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      echo "⚠️ Stale bisync lockfile from dead PID $lock_pid detected (prior crash/reboot). Auto-clearing."
      rm -f "$lockfile"
    fi
  fi
}

# Run a command on the host when inside a Distrobox container
host_exec() {
  if [ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    distrobox-host-exec "$@"
  else
    "$@"
  fi
}

# Portable in-place sed (BSD/macOS vs GNU/Linux)
sedi() {
  if [[ "${OSTYPE:-}" == darwin* ]] || [ "${IS_MAC:-0}" -eq 1 ] || [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Rsync wrapper that treats exit code 24 (vanished source files) as non-fatal
safe_rsync() {
  rsync "$@" || {
    local ec=$?
    if [ "$ec" -eq 24 ]; then
      return 0
    fi
    return "$ec"
  }
}

# Keep the N newest directories matching "<prefix>*" inside <target_dir>
prune_old_backups() {
  local target_dir="$1"
  local prefix="$2"
  local keep="$3"
  local pruned=0
  local old_dir
  while IFS= read -r old_dir; do
    [ -n "$old_dir" ] || continue
    rm -rf "$old_dir"
    pruned=$((pruned + 1))
  done < <(ls -1dt "$target_dir"/"${prefix}"* 2>/dev/null | tail -n +$((keep + 1)))
  echo "$pruned"
}
