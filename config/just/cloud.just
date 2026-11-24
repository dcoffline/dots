# =============================================================================
# CLOUD STORAGE (RCLONE & NEXTCLOUD)
# =============================================================================

# Mounts cloud storage remotes (Auto-detects macOS vs Linux)
mount:
    #!/usr/bin/env bash
    exec bash "$HOME/.config/just/lib/rclone-mount.sh"

# Unmounts all rclone directories
unmount:
    #!/usr/bin/env bash
    source "$HOME/.config/just/lib/common.sh"

    for remote in "${RCLONE_REMOTES[@]}"; do
      mountpoint="$RCLONE_BASE_MOUNT/$remote"
      pid_file="$HOME/.config/rclone/pid/${remote}.pid"

      if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          echo "Stopping rclone for $mountpoint (PID: $pid)"
          kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
      fi

      unmount_path "$mountpoint"

      if [ -d "$mountpoint" ] && ! mount | grep -Fq "$mountpoint"; then
        rmdir "$mountpoint" 2>/dev/null && mkdir -p "$mountpoint" || true
      fi
    done

# Checks all rclone mount points and restarts the service if any are dead/hung
check-mounts:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"

    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "Watchdog not supported on macOS in this configuration."
      exit 0
    fi

    # Check if the main rclone service is active. If not, do not force-start it.
    if ! systemctl --user is-active --quiet rclone.service; then
      echo "rclone.service is not active. Skipping watchdog check."
      exit 0
    fi

    trigger_restart=false
    failed_remote=""

    for remote in "${RCLONE_REMOTES[@]}"; do
      mountpoint="$RCLONE_BASE_MOUNT/$remote"

      echo "Checking mountpoint: $mountpoint"

      # 1. Check if it's mounted
      if ! mountpoint -q "$mountpoint" 2>/dev/null; then
        echo "❌ $remote is not mounted!"
        trigger_restart=true
        failed_remote="$remote (not mounted)"
        break
      fi

      # 2. Check if the mount is responsive (non-blocking test)
      if ! run_with_timeout 3 stat "$mountpoint" >/dev/null 2>&1; then
        echo "❌ $remote mount is hung or unresponsive!"
        trigger_restart=true
        failed_remote="$remote (unresponsive)"
        break
      fi
    done

    if [ "$trigger_restart" = true ]; then
      echo "Reconnecting mounts... Failure detected on: $failed_remote"
      if command -v notify-send &>/dev/null; then
        notify-send -u critical "Rclone Watchdog" "Mount failed on $failed_remote. Reconnecting..." || true
      fi
      systemctl --user restart rclone.service
    else
      echo "✅ All rclone mounts are healthy."
    fi

# Commits and pushes rclone.conf changes while preserving skip-worktree and stow symlink integrity
update-rclone msg="Update rclone remotes":
    #!/usr/bin/env bash
    set -euo pipefail
    DOTS="${DOTS:-$HOME/src/dots}"
    LIVE_CONF="$HOME/.config/rclone/rclone.conf"
    REPO_CONF="$DOTS/config/rclone/rclone.conf"

    # Always restore skip-worktree on exit so background token refreshes stay ignored
    trap 'git -C "$DOTS" update-index --skip-worktree config/rclone/rclone.conf 2>/dev/null || true' EXIT

    # If rclone config atomically replaced the stow symlink with a regular file, sync it back and re-link
    if [ -f "$LIVE_CONF" ] && [ ! -L "$LIVE_CONF" ]; then
      echo "🔄 Live rclone.conf was replaced by a regular file; syncing to repo and restoring relative symlink..."
      cp -p "$LIVE_CONF" "$REPO_CONF"
      (cd "$HOME/.config/rclone" && ln -sfn ../../src/dots/config/rclone/rclone.conf rclone.conf)
    fi

    git -C "$DOTS" update-index --no-skip-worktree config/rclone/rclone.conf

    if git -C "$DOTS" diff --quiet -- config/rclone/rclone.conf; then
      echo "✅ No changes to commit in config/rclone/rclone.conf."
      exit 0
    fi

    git -C "$DOTS" add config/rclone/rclone.conf
    git -C "$DOTS" commit -m "{{msg}}" -- config/rclone/rclone.conf
    git -C "$DOTS" push origin main
    echo "✅ rclone.conf committed, pushed (git-crypt), and skip-worktree re-applied."

# Restows Nextcloud user folders into ~ as local directories of symlinks ([-n] [-v])
restow *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"

    SRC="$RCLONE_BASE_MOUNT/Nextcloud"
    DIRS=(Documents Music Pictures Videos)
    STOW_IGNORES=(
      "--ignore=^\.DS_Store$"
      "--ignore=^\._.*"
      "--ignore=^\.localized$"
      "--ignore=^\.~lock\..*"
      "--ignore=^Thumbs\.db$"
    )

    if ! command -v stow >/dev/null 2>&1; then
      echo "❌ GNU Stow is not installed (install with: pacman -S stow / brew install stow)" >&2
      exit 1
    fi

    # 1. Verify Nextcloud root exists and is responsive (works on native FUSE and VM 9p shares)
    if [[ ! -d "$SRC" ]]; then
      echo "❌ Nextcloud directory not found at $SRC. Aborting to protect existing links." >&2
      exit 1
    fi

    if ! run_with_timeout 5 ls "$SRC" >/dev/null 2>&1; then
      echo "❌ Nextcloud mount at $SRC is unresponsive. Aborting." >&2
      exit 1
    fi

    # 2. Verify at least one expected folder is populated (guards against empty unmounted stubs)
    any_populated=0
    for dir in "${DIRS[@]}"; do
      if [[ -d "$SRC/$dir" ]] && [[ -n "$(run_with_timeout 5 ls -A "$SRC/$dir" 2>/dev/null || true)" ]]; then
        any_populated=1
        break
      fi
    done
    if [[ "$any_populated" -eq 0 ]]; then
      echo "❌ Nextcloud at $SRC appears empty or unmounted. Aborting to protect existing links." >&2
      exit 1
    fi

    EXTRA_ARGS=()
    DRY_RUN=0
    for arg in {{args}}; do
      EXTRA_ARGS+=("$arg")
      case "$arg" in
        -n|--no|--simulate) DRY_RUN=1 ;;
      esac
    done

    FAILED=0
    for dir in "${DIRS[@]}"; do
      src_dir="$SRC/$dir"
      target_dir="$HOME/$dir"

      if [[ ! -d "$src_dir" ]] || [[ -z "$(run_with_timeout 5 ls -A "$src_dir" 2>/dev/null || true)" ]]; then
        echo "⚠️  Skipping $dir: $src_dir is missing or empty"
        continue
      fi

      # Safely migrate if ~/$dir is still a direct symlink to the Nextcloud mount
      if [[ -L "$target_dir" ]]; then
        link_dest="$(readlink "$target_dir")"
        if [[ "${link_dest%/}" == *".mnt/rclone/Nextcloud/$dir" ]]; then
          if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "🔍 [dry-run] Would replace symlink $target_dir -> $link_dest with a local directory"
            continue
          fi
          echo "🔄 Replacing direct symlink $target_dir -> $link_dest with a local directory..."
          rm "$target_dir"
        else
          echo "⚠️  Skipping $dir: $target_dir is a symlink to $link_dest (not Nextcloud)" >&2
          FAILED=1
          continue
        fi
      fi

      if [[ ! -d "$target_dir" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          echo "🔍 [dry-run] Would create $target_dir and restow $dir"
          continue
        fi
        mkdir -p "$target_dir"
      fi

      echo "🔗 Restowing $dir → $target_dir"
      if ! stow -R -d "$SRC" -t "$target_dir" "${STOW_IGNORES[@]}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "$dir"; then
        echo "❌ Failed to restow $dir (resolve conflicts above and re-run)" >&2
        FAILED=1
      fi
    done

    if [[ "$FAILED" -ne 0 ]]; then
      echo "⚠️  Completed with errors." >&2
      exit 1
    fi
    echo "✅ Nextcloud folders restowed."

# Keep GDrive synced with Nextcloud Documents
sync-gdrive:
    #!/usr/bin/env bash
    source "$HOME/.config/just/lib/common.sh"

    RCLONE="$(resolve_rclone_bin)"

    # Exit if a sync is already running to avoid overlaps
    if pidof -x "$(basename "$0")" -o %PPID >/dev/null; then
        echo "Sync already running. Exiting."
        exit 1
    fi

    # Ensure host user eric owns all local files so rclone can set timestamps (chtimes).
    # Nextcloud container (UID 524320) retains access via default ACLs.
    podman unshare chown -R 0:0 /var/home/eric/.mnt/10T/Documents 2>/dev/null || true

    clear_stale_bisync_lock "$HOME/.cache/rclone/bisync/var_home_eric_.mnt_10T_Documents..GDrive_.lck"

    # Completely hide Google Docs/Sheets
    export RCLONE_DRIVE_SKIP_GDOC=true

    echo "=== Running Bisync between /var/home/eric/.mnt/10T/Documents and GDrive: ==="
    if ! "$RCLONE" bisync /var/home/eric/.mnt/10T/Documents GDrive: --slow-hash-sync-only --recover --resilient --tpslimit 10 --exclude '**/.trash/**' --exclude '**/.Trash*/**' --exclude '**/.Trash-1000/**' --exclude '**/.DS_Store' --exclude '**/._*' --drive-skip-shortcuts --drive-skip-dangling-shortcuts -v; then
        echo "⚠️ Bisync failed. If this is your first time running bisync, you must run:"
        echo "  just cloud resync-gdrive"
        exit 1
    fi

    echo "=== Sync Complete ==="

# Resync GDrive with Nextcloud Documents (recovery / initial setup)
resync-gdrive:
    #!/usr/bin/env bash
    source "$HOME/.config/just/lib/common.sh"

    RCLONE="$(resolve_rclone_bin)"

    # Ensure host user eric owns all local files so rclone can set timestamps (chtimes).
    # Nextcloud container (UID 524320) retains access via default ACLs.
    podman unshare chown -R 0:0 /var/home/eric/.mnt/10T/Documents 2>/dev/null || true

    clear_stale_bisync_lock "$HOME/.cache/rclone/bisync/var_home_eric_.mnt_10T_Documents..GDrive_.lck"

    export RCLONE_DRIVE_SKIP_GDOC=true

    echo "=== Running Bisync --resync between /var/home/eric/.mnt/10T/Documents and GDrive: ==="
    "$RCLONE" bisync /var/home/eric/.mnt/10T/Documents GDrive: --resync --slow-hash-sync-only --tpslimit 10 --exclude '**/.trash/**' --exclude '**/.Trash*/**' --exclude '**/.Trash-1000/**' --exclude '**/.DS_Store' --exclude '**/._*' --drive-skip-shortcuts --drive-skip-dangling-shortcuts -v
    echo "=== Resync Complete ==="
