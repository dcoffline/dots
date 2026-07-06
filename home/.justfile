# =============================================================================
# MULTI-OS DOTFILES MANAGEMENT
# =============================================================================

# Running 'just' with no arguments will display this menu
default:
    @just --list

# =============================================================================
# SYSTEM MAINTENANCE
# =============================================================================

# Keep GDrive synced with Nextcloud Documents
sync-gdrive:
    #!/bin/bash
    
    # Define RCLONE for various systems
    RCLONE="rclone"
    if [ -x /home/linuxbrew/.linuxbrew/bin/rclone ]; then
        RCLONE="/home/linuxbrew/.linuxbrew/bin/rclone"
    elif [ -x /usr/bin/rclone ]; then
        RCLONE="/usr/bin/rclone"
    fi

    # Exit if a sync is already running to avoid overlaps
    if pidof -x $(basename $0) -o %PPID >/dev/null; then
        echo "Sync already running. Exiting."
        exit 1
    fi

    # Set the environment variable to completely hide Google Docs/Sheets
    export RCLONE_DRIVE_SKIP_GDOC=true

    # Common flags for speed and safety
    FLAGS="-u --delete-after --ignore-errors --no-update-dir-modtime --exclude ._* --exclude .DS_Store -v"

    echo "=== Step 1: Pushing up local changes to GDrive ==="
    $RCLONE sync ~/Documents GDrive: $FLAGS

    echo "=== Step 2: Pulling down changes from GDrive ==="
    $RCLONE sync GDrive: ~/Documents $FLAGS

    echo "=== Sync Complete ==="

# Initiates the Fortress Maintenance Protocol (Updates, Syncs, Backups)
update:
    #!/usr/bin/env bash
    sudo -v
    set -e
    SHELLINI="config/dconf-backups/gnome-shell.ini"
    
    # Sudo keep-alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    if [ -f /run/.containerenv ]; then
      ENV_TYPE="container"
      echo "[ 🏗️  Container environment detected ]"
    elif [ -f /run/ostree-booted ] || [[ "$(uname -s)" == "Darwin" ]]; then
      ENV_TYPE="immutable"
      echo "[ 🛡️  Immutable host detected ]"
    else
      ENV_TYPE="mutable"
      echo "[ 💻 Standard mutable host detected ]"
    fi

    cd "$DOTS" || exit 1
    source ./config/environment.d/envvars.conf
    [ -f ./config/bash/os.bash ] && source ./config/bash/os.bash

    echo "[ Syncing with GitHub... ]"
    git pull --rebase origin main || echo "⚠️ Warning: Git pull failed. Continuing..."

    echo "[ Initiating Fortress Maintenance Protocol... ]"

    if [ "$ENV_TYPE" = "container" ]; then
      echo "[ Updating Container binaries... ]"
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf upgrade -y --skip-unavailable
      elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get upgrade -y
      elif command -v pacman >/dev/null 2>&1; then
        if command -v yay >/dev/null 2>&1; then yay -Syu; else sudo pacman -Syu; fi
      fi

      echo "[ Updating Cargo packages... ]"
      cargo install television atuin || echo "⚠️ Warning: Cargo updates failed."

      echo "[ Syncing Host State... ]"
      distrobox-host-exec sh -c "cd '$DOTS' && /home/linuxbrew/.linuxbrew/bin/brew bundle dump --force"
      if distrobox-host-exec printenv XDG_CURRENT_DESKTOP 2>/dev/null | grep -qi gnome; then
        distrobox-host-exec dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
        sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
      fi

      echo "[ Applying Dotfile Updates... ]"
      mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin" "$HOME/.local/share/gnome-shell/extensions"
      stow -R --ignore=".DS_Store" -t "$HOME" home
      stow -R --ignore=".DS_Store" -t "$HOME/.config" config
      stow -R --ignore=".DS_Store" -t "$HOME/.local" local

      echo "[ Backing up to GitHub... ]"
      git add Brewfile "$SHELLINI"
      git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
      git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."
      
      echo "[ Starting Immutable Host Update... ]"
      distrobox-host-exec ujust update

    elif [ "$ENV_TYPE" = "immutable" ]; then
      echo "[ Syncing Host State... ]"
      brew bundle dump --force || echo "⚠️ Warning: Homebrew dump failed."
      if command -v dconf >/dev/null 2>&1 && [[ "$XDG_CURRENT_DESKTOP" =~ "GNOME" ]]; then
        dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
        sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
      fi

      echo "[ Applying Dotfile Updates... ]"
      stow -R --ignore=".DS_Store" -t "$HOME" home
      stow -R --ignore=".DS_Store" -t "$HOME/.config" config
      stow -R --ignore=".DS_Store" -t "$HOME/.local" local

      echo "[ Backing up to GitHub via Container... ]"
      if [ "$OS_TYPE" = "mac" ]; then
        git add Brewfile
        git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
        git push origin main || echo "⚠️ Warning: Git push failed."
      elif [ "$OS_TYPE" = "linux" ]; then
        CONTAINER_NAME=$(distrobox list --no-color | awk -F '|' 'NR>1 {gsub(/[ \t]+/, "", $2); print $2}' | head -n 1)
        if [ -n "$CONTAINER_NAME" ]; then
          distrobox enter "$CONTAINER_NAME" -- sh -c "cd '$DOTS' && git add Brewfile '$SHELLINI' && git commit -m 'System snapshot: \$(date +\"%Y-%m-%d\")' || true && git push origin main"
        fi
        echo "[ Starting Immutable Host Update... ]"
        ujust update
      fi

    else
      echo "[ Updating System binaries... ]"
      if command -v brew >/dev/null 2>&1; then brew update && brew upgrade; fi
      if command -v dnf >/dev/null 2>&1; then sudo dnf upgrade -y --skip-unavailable; fi
      if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get upgrade -y; fi
      if command -v pacman >/dev/null 2>&1; then command -v yay >/dev/null 2>&1 && yay -Syu || sudo pacman -Syu; fi
      if command -v npm >/dev/null 2>&1; then sudo npm update -g; fi
      if command -v cargo >/dev/null 2>&1; then cargo install television atuin || echo "⚠️ Warning: Cargo failed."; fi

      echo "[ Syncing Host State & Dotfiles... ]"
      if command -v dconf >/dev/null 2>&1 && [[ "$XDG_CURRENT_DESKTOP" =~ "GNOME" ]]; then
        dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
        sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
      fi
      if command -v brew >/dev/null 2>&1; then brew bundle dump --force; fi

      stow -R --ignore=".DS_Store" -t "$HOME" home
      stow -R --ignore=".DS_Store" -t "$HOME/.config" config
      stow -R --ignore=".DS_Store" -t "$HOME/.local" local

      git add "$SHELLINI" Brewfile
      git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
      git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."
    fi
    echo "[ Fortress Maintenance Complete ]"

# Rebuild the gnome-rounded-blur library (run after Mutter/GNOME updates)
rounded-blur:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "⚙️  Configuring environment variables..."
    mkdir -p ~/.config/environment.d
    echo "GI_TYPELIB_PATH=/usr/local/lib64/girepository-1.0:/usr/local/lib/girepository-1.0" > ~/.config/environment.d/60-gnome-rounded-blur.conf
    
    if [ ! -f /etc/ld.so.conf.d/usr-local-x86_64.conf ]; then
        echo "⚙️  Configuring dynamic linker search path..."
        echo -e "/usr/local/lib64\n/usr/local/lib" | sudo tee /etc/ld.so.conf.d/usr-local-x86_64.conf > /dev/null
    fi

    echo "🔄 Updating build dependencies in Fedora distrobox..."
    distrobox-enter -n fedora -- sudo dnf upgrade -y --refresh glib2-devel mutter-devel gobject-introspection-devel gobject-introspection meson gcc gcc-c++ make git
    
    echo "🏗️  Rebuilding gnome-rounded-blur inside Fedora distrobox..."
    distrobox-enter -n fedora -- bash -c "curl -sL https://raw.githubusercontent.com/aunetx/blur-my-shell/refs/heads/master/scripts/rounded_blur_build.sh | bash -s -- -i"
    
    echo "📦 Copying files to host /usr/local/..."
    sudo cp -r /tmp/gnome-rounded-blur/build/binary/usr/local/* /usr/local/
    
    echo "🔄 Reloading dynamic linker cache..."
    sudo ldconfig
    
    echo "✅ Success! Please log out and back in to apply the changes."

# =============================================================================
# CLOUD STORAGE
# =============================================================================

# Mounts cloud storage remotes (Auto-detects macOS vs Linux)
mount:
    #!/usr/bin/env bash
    set -euo pipefail
    BASE_MOUNT="$HOME/.mnt/rclone"
    LOGFILE="$HOME/.config/rclone/rclone-mount.log"
    PID_DIR="$HOME/.config/rclone/pid"
    declare -A REMOTES=( ["Archive"]="Archive" ["Backup"]="Backup" ["GDrive"]="GDrive" ["Nextcloud"]="Nextcloud" ["OneDrive"]="OneDrive" ["RealDebrid"]="RealDebrid" ["Timeline"]="Timeline" ["Zurg"]="Zurg" )

    OS_TYPE="$(uname -s)"

    # 1. OS-Specific Setup (Binaries, Caches, & Pre-flight checks)
    if [[ "$OS_TYPE" == "Darwin" ]]; then
      echo "[ macOS Detected - Running Mac Rclone Routine ]"
      RCLONE="/usr/local/bin/rclone"
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
      RCLONE="rclone"
      if [ -x /home/linuxbrew/.linuxbrew/bin/rclone ]; then
        RCLONE="/home/linuxbrew/.linuxbrew/bin/rclone"
      elif [ -x /usr/bin/rclone ]; then
        RCLONE="/usr/bin/rclone"
      fi

      if [ -f /run/ostree-booted ]; then
        CACHE_DIR="$HOME/.mnt/2T/rclone_cache"
      else
        CACHE_DIR="$HOME/.cache/rclone_cache"
      fi
    fi

    # 2. Define COMMON_FLAGS
    COMMON_FLAGS=(
      --vfs-cache-mode writes
      --cache-dir "$CACHE_DIR"
      --drive-import-formats docx,xlsx,pptx
      --vfs-read-chunk-size=64M
      --vfs-cache-max-size=10G
      --vfs-cache-max-age=720h
      --log-file "$LOGFILE"
      --log-level ERROR
    )

    if [[ "$OS_TYPE" != "Darwin" ]]; then
      # Append Linux-specific flags
      COMMON_FLAGS+=(
        --allow-other
        --exclude '.DS_Store'
        --exclude '._*'
        --umask 002
        --dir-perms 775
        --file-perms 664
        --vfs-read-chunk-size-limit off
        --attr-timeout 10m
        --vfs-cache-min-free-space=20G
        --poll-interval=1m
        --buffer-size 64M
      )
    fi

    # 3. Preparation
    mkdir -p "$PID_DIR" "$BASE_MOUNT" "$CACHE_DIR"
    just unmount || true
    pkill rclone 2>/dev/null || true
    sleep 2

    # 4. Mount Loop
    for remote in "${!REMOTES[@]}"; do
      target="${REMOTES[$remote]}"
      mountpoint="$BASE_MOUNT/$target"
      mkdir -p "$mountpoint"

      EXTRA_FLAGS=()
      if [[ "$OS_TYPE" == "Darwin" ]]; then
        if [[ "$remote" == "realdebrid" || "$remote" == "RealDebrid" ]]; then
          EXTRA_FLAGS=( --read-only --exclude '.DS_Store' --exclude '._*' )
        fi
      else
        # Linux
        if [[ "$remote" == "realdebrid" || "$remote" == "RealDebrid" ]]; then
          EXTRA_FLAGS=( --read-only --dir-cache-time 72h )
        elif [[ "$remote" == "Zurg" ]]; then
          EXTRA_FLAGS=( --dir-cache-time 10s )
        else
          EXTRA_FLAGS=( --dir-cache-time 72h )
        fi
      fi

      echo "Mounting $remote → $mountpoint"
      nohup "$RCLONE" mount "${remote}:" "$mountpoint" "${COMMON_FLAGS[@]}" "${EXTRA_FLAGS[@]}" >/dev/null 2>&1 &
      echo $! >"$PID_DIR/${remote}.pid"
    done

    sleep 5
    echo -e "\nMount commands issued."

# Unmounts all rclone directories
unmount:
    #!/usr/bin/env bash
    BASE_MOUNT="$HOME/.mnt/rclone"
    declare -A REMOTES=( ["Archive"]="Archive" ["Backup"]="Backup" ["GDrive"]="GDrive" ["Nextcloud"]="Nextcloud" ["OneDrive"]="OneDrive" ["RealDebrid"]="RealDebrid" ["Timeline"]="Timeline" ["Zurg"]="Zurg" )

    for remote in "${!REMOTES[@]}"; do
      target="${REMOTES[$remote]}"
      mountpoint="$BASE_MOUNT/$target"
      pid_file="$HOME/.config/rclone/pid/${remote}.pid"

      if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          echo "Stopping rclone for $mountpoint (PID: $pid)"
          kill "$pid"
        fi
        rm -f "$pid_file"
      fi

      if mountpoint -q "$mountpoint" 2>/dev/null || grep -Fq "$mountpoint" /proc/mounts 2>/dev/null || mount | grep -Fq "$mountpoint"; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
          umount "$mountpoint" 2>/dev/null || diskutil unmount force "$mountpoint"
        else
          fusermount -uz "$mountpoint" || fusermount -u "$mountpoint" || echo "Mount $mountpoint is stubborn."
        fi
      fi
    done

# Checks all rclone mount points and restarts the service if any are dead/hung
check-mounts:
    #!/usr/bin/env bash
    set -euo pipefail
    BASE_MOUNT="$HOME/.mnt/rclone"
    declare -A REMOTES=( ["Archive"]="Archive" ["Backup"]="Backup" ["GDrive"]="GDrive" ["Nextcloud"]="Nextcloud" ["OneDrive"]="OneDrive" ["RealDebrid"]="RealDebrid" ["Timeline"]="Timeline" ["Zurg"]="Zurg" )

    OS_TYPE="$(uname -s)"
    if [[ "$OS_TYPE" == "Darwin" ]]; then
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

    for remote in "${!REMOTES[@]}"; do
      target="${REMOTES[$remote]}"
      mountpoint="$BASE_MOUNT/$target"

      echo "Checking mountpoint: $mountpoint"

      # 1. Check if it's mounted
      if ! mountpoint -q "$mountpoint" 2>/dev/null; then
        echo "❌ $remote is not mounted!"
        trigger_restart=true
        failed_remote="$remote (not mounted)"
        break
      fi

      # 2. Check if the mount is responsive (non-blocking test)
      if ! timeout 3 stat "$mountpoint" >/dev/null 2>&1; then
        echo "❌ $remote mount is hung or unresponsive!"
        trigger_restart=true
        failed_remote="$remote (unresponsive)"
        break
      fi
    done

    if [ "$trigger_restart" = true ]; then
      echo "Reconnecting mounts... Failure detected on: $failed_remote"
      if command -v notify-send &>/dev/null; then
        notify-send -u critical "Rclone Watchdog" "Mount failed on $failed_remote. Reconnecting..."
      fi
      systemctl --user restart rclone.service
    else
      echo "✅ All rclone mounts are healthy."
    fi

# =============================================================================
# DEVELOPMENT TOOLS
# =============================================================================

# Installs the Antigravity CLI
install-agy:
    curl -fsSL https://antigravity.google/cli/install.sh | bash

# =============================================================================
# LOGSEQ SYNC PROTOCOL (Cross-Platform)
# =============================================================================

# Launches Logseq with git pull/rebase and push sync (Mac & Linux)
logseq:
    #!/usr/bin/env bash
    set -euo pipefail

    OS_TYPE=""
    if [[ "$(uname -s)" == "Darwin" ]]; then
      OS_TYPE="mac"
    else
      OS_TYPE="linux"
    fi
    
    REPO_DIR="$HOME/src/logseq"
    cd "$REPO_DIR" || exit 1

    # Notification Helper Function
    notify() {
      local title="Logseq Sync"
      local message="$1"
      if [[ "$OS_TYPE" == "mac" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\""
      elif command -v notify-send &>/dev/null; then
        notify-send "$title" "$message"
      fi
    }

    echo "🔄 Checking for mobile changes on GitHub..."
    if curl -sI --connect-timeout 3 https://github.com &>/dev/null && git fetch origin main &>/dev/null; then
      LOCAL_HASH=$(git rev-parse @)
      REMOTE_HASH=$(git rev-parse @{u})
      BASE_HASH=$(git merge-base @ @{u})

      if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        echo "✅ Repository is already up-to-date."
      elif [ "$LOCAL_HASH" = "$BASE_HASH" ]; then
        echo "📥 Remote changes detected. Pulling..."
        if git pull --rebase origin main; then
          notify "📥 Pulled latest changes from GitHub."
        fi
      elif [ "$REMOTE_HASH" = "$BASE_HASH" ]; then
        echo "🚀 Local changes ahead of remote. Proceeding..."
      else
        echo "⚠️ Diverged! Attempting pull --rebase..."
        if git pull --rebase origin main; then
          notify "📥 Pulled and rebased latest changes."
        fi
      fi
    else
      echo "⚠️ Warning: Could not contact remote repository. Starting Logseq offline."
      notify "⚠️ Offline: Starting Logseq in offline mode."
    fi

    echo "🚀 Launching Logseq..."
    if [ "$OS_TYPE" = "mac" ]; then
      if [ -d "$HOME/.logseq-app/Logseq.app" ]; then
        open -W "$HOME/.logseq-app/Logseq.app"
      else
        open -W -a Logseq
      fi
    else
      env DESKTOPINTEGRATION=1 "$HOME/Applications/logseq.appimage"
      #env DESKTOPINTEGRATION=1 "$XDG_DATA_HOME/logseq/Logseq"
      #env DESKTOPINTEGRATION=1 /usr/bin/flatpak run --branch=stable --arch=x86_64 --command=run.sh --file-forwarding com.logseq.Logseq
    fi

    echo "📦 Logseq closed. Shipping latest changes to GitHub..."
    CHANGES_COMMITTED=false
    if [ -n "$(git status --porcelain)" ]; then
      echo "Changes detected. Staging and committing..."
      git add -A
      git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S') from $OS_TYPE" || true
      CHANGES_COMMITTED=true
    fi

    if curl -sI --connect-timeout 3 https://github.com &>/dev/null; then
      if [ "$CHANGES_COMMITTED" = true ]; then
        if git push origin main; then
          echo "✅ Sync complete!"
          notify "📤 Uploaded your latest edits to GitHub."
        else
          echo "⚠️ Error: Failed to push changes."
          notify "⚠️ Error: Failed to push edits to GitHub."
        fi
      else
        # Try pushing anyway just in case the auto-commit plugin committed things
        if git push origin main &>/dev/null || git diff-index --quiet HEAD --; then
          echo "✅ Sync complete! (No new local changes to push)"
          notify "✅ Sync complete. Repository is up-to-date."
        else
          notify "⚠️ Error: Failed to push changes."
        fi
      fi
    else
      if [ "$CHANGES_COMMITTED" = true ]; then
        echo "⚠️ Offline: Changes saved locally but could not push."
        notify "⚠️ Offline: Edits saved locally (will push next sync)."
      else
        echo "⚠️ Offline: Started and closed offline."
      fi
    fi



