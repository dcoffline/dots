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

    # Ensure host user eric owns all local files so rclone can set timestamps (chtimes).
    # Nextcloud container (UID 524320) retains access via default ACLs.
    podman unshare chown -R 0:0 /var/home/eric/.mnt/10T/Documents 2>/dev/null || true

    # Set the environment variable to completely hide Google Docs/Sheets
    export RCLONE_DRIVE_SKIP_GDOC=true

    # Use bisync for bidirectional sync to prevent data loss / overwrite conflicts
    echo "=== Running Bisync between /var/home/eric/.mnt/10T/Documents and GDrive: ==="
    if ! $RCLONE bisync /var/home/eric/.mnt/10T/Documents GDrive: --slow-hash-sync-only --recover --resilient --exclude '**/.trash/**' --exclude '**/.Trash*/**' --exclude '**/.Trash-1000/**' --exclude '**/.DS_Store' --exclude '**/._*' --drive-skip-shortcuts --drive-skip-dangling-shortcuts -v; then
        echo "⚠️ Bisync failed. If this is your first time running bisync, you must run:"
        echo "  just resync-gdrive"
        exit 1
    fi

    echo "=== Sync Complete ==="

# Resync GDrive with Nextcloud Documents (recovery / initial setup)
resync-gdrive:
    #!/bin/bash
    
    RCLONE="rclone"
    if [ -x /home/linuxbrew/.linuxbrew/bin/rclone ]; then
        RCLONE="/home/linuxbrew/.linuxbrew/bin/rclone"
    elif [ -x /usr/bin/rclone ]; then
        RCLONE="/usr/bin/rclone"
    fi

    # Ensure host user eric owns all local files so rclone can set timestamps (chtimes).
    # Nextcloud container (UID 524320) retains access via default ACLs.
    podman unshare chown -R 0:0 /var/home/eric/.mnt/10T/Documents 2>/dev/null || true

    export RCLONE_DRIVE_SKIP_GDOC=true

    echo "=== Running Bisync --resync between /var/home/eric/.mnt/10T/Documents and GDrive: ==="
    $RCLONE bisync /var/home/eric/.mnt/10T/Documents GDrive: --resync --slow-hash-sync-only --exclude '**/.trash/**' --exclude '**/.Trash*/**' --exclude '**/.Trash-1000/**' --exclude '**/.DS_Store' --exclude '**/._*' --drive-skip-shortcuts --drive-skip-dangling-shortcuts -v
    echo "=== Resync Complete ==="

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
      if command -v rustup >/dev/null 2>&1; then
        echo "[ Updating Rust toolchain... ]"
        rustup update stable
      fi
      cargo install television atuin || echo "⚠️ Warning: Cargo updates failed."

      echo "[ Syncing Host State... ]"
      distrobox-host-exec sh -c "cd '$DOTS' && /home/linuxbrew/.linuxbrew/bin/brew bundle dump --force && sed -i '/^flatpak/d' Brewfile"
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
      brew bundle dump --force && sed -i '/^flatpak/d' Brewfile || echo "⚠️ Warning: Homebrew dump failed."
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
          distrobox enter "$CONTAINER_NAME" -- sh -c "cd '$DOTS' && git add Brewfile '$SHELLINI' && git commit -m \"System snapshot: $(date +'%Y-%m-%d')\" || true && git push origin main"
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
      if command -v cargo >/dev/null 2>&1; then
        if command -v rustup >/dev/null 2>&1; then
          echo "[ Updating Rust toolchain... ]"
          rustup update stable
        fi
        cargo install television atuin || echo "⚠️ Warning: Cargo failed."
      fi

      echo "[ Syncing Host State & Dotfiles... ]"
      if command -v dconf >/dev/null 2>&1 && [[ "$XDG_CURRENT_DESKTOP" =~ "GNOME" ]]; then
        dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
        sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
      fi
      if command -v brew >/dev/null 2>&1; then brew bundle dump --force && sed -i '/^flatpak/d' Brewfile; fi

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
    declare -A REMOTES=( ["Archive"]="Archive" ["Backup"]="Backup" ["GDrive"]="GDrive" ["Hematicom"]="Hematicom" ["Nextcloud"]="Nextcloud" ["OneDrive"]="OneDrive" ["Timeline"]="Timeline" ["Zurg"]="Zurg" )

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
    mkdir -p "$PID_DIR" "$BASE_MOUNT" "$CACHE_DIR"
    just unmount || true
    pkill rclone 2>/dev/null || true
    sleep 2

    # Clean stale mountpoint directories
    for remote in "${!REMOTES[@]}"; do
      target="${REMOTES[$remote]}"
      mountpoint="$BASE_MOUNT/$target"
      if [ -d "$mountpoint" ] && ! mount | grep -Fq "$mountpoint"; then
        rmdir "$mountpoint" 2>/dev/null && mkdir -p "$mountpoint" || true
      else
        mkdir -p "$mountpoint"
      fi
    done

    # 4. Mount Loop
    for remote in "${!REMOTES[@]}"; do
      target="${REMOTES[$remote]}"
      mountpoint="$BASE_MOUNT/$target"

      if [[ "$remote" == "Zurg" ]]; then
        zurg_up=false
        for attempt in {1..10}; do
          if curl -s --connect-timeout 2 http://127.0.0.1:9999/ >/dev/null 2>&1 || curl -s --connect-timeout 2 https://zurg.hemati.com/ >/dev/null 2>&1; then
            zurg_up=true
            break
          fi
          echo "Waiting for Zurg WebDAV server to be ready (attempt $attempt/10)..."
          sleep 2
        done
        if [ "$zurg_up" = false ]; then
          echo "⚠️ Zurg WebDAV server is not responding after 20s. Skipping mount."
          continue
        fi
      fi

      EXTRA_FLAGS=()
      if [[ "$OS_TYPE" == "Darwin" ]]; then
        EXTRA_FLAGS+=( --volname "$remote" )
        if [[ "$remote" == "realdebrid" || "$remote" == "RealDebrid" || "$remote" == "Zurg" ]]; then
          EXTRA_FLAGS+=( --read-only )
        fi
      else
        # Linux
        if [[ "$remote" == "Zurg" ]]; then
          EXTRA_FLAGS=( --read-only --dir-cache-time 10s --attr-timeout 1s )
        elif [[ "$remote" == "Nextcloud" ]]; then
          EXTRA_FLAGS=( --dir-cache-time 10s --attr-timeout 1s )
        else
          EXTRA_FLAGS=( --dir-cache-time 72h )
        fi
      fi

      echo "Mounting $remote → $mountpoint"
      nohup "$RCLONE" mount "${remote}:" "$mountpoint" "${COMMON_FLAGS[@]}" "${EXTRA_FLAGS[@]}" >/dev/null 2>&1 &
      echo $! >"$PID_DIR/${remote}.pid"
      sleep 1
    done

    sleep 3
    echo -e "\nMount commands issued."

# Unmounts all rclone directories
unmount:
    #!/usr/bin/env bash
    BASE_MOUNT="$HOME/.mnt/rclone"
    declare -A REMOTES=( ["Archive"]="Archive" ["Backup"]="Backup" ["GDrive"]="GDrive" ["Hematicom"]="Hematicom" ["Nextcloud"]="Nextcloud" ["OneDrive"]="OneDrive" ["Timeline"]="Timeline" ["Zurg"]="Zurg" )

    # Zurg is now mounted on macOS as well

    for remote in "${!REMOTES[@]}"; do
      target="${REMOTES[$remote]}"
      mountpoint="$BASE_MOUNT/$target"
      pid_file="$HOME/.config/rclone/pid/${remote}.pid"

      if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          echo "Stopping rclone for $mountpoint (PID: $pid)"
          kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
      fi

      if [[ "$(uname -s)" == "Darwin" ]]; then
        umount "$mountpoint" 2>/dev/null || umount -f "$mountpoint" 2>/dev/null || diskutil unmount force "$mountpoint" 2>/dev/null || true
      else
        fusermount -uz "$mountpoint" 2>/dev/null || fusermount -u "$mountpoint" 2>/dev/null || true
      fi

      if [ -d "$mountpoint" ] && ! mount | grep -Fq "$mountpoint"; then
        rmdir "$mountpoint" 2>/dev/null && mkdir -p "$mountpoint" || true
      fi
    done

# Checks all rclone mount points and restarts the service if any are dead/hung
check-mounts:
    #!/usr/bin/env bash
    set -euo pipefail
    BASE_MOUNT="$HOME/.mnt/rclone"
    declare -A REMOTES=( ["Archive"]="Archive" ["Backup"]="Backup" ["GDrive"]="GDrive" ["Hematicom"]="Hematicom" ["Nextcloud"]="Nextcloud" ["OneDrive"]="OneDrive" ["Timeline"]="Timeline" ["Zurg"]="Zurg" )

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

      # Skip checking Zurg if it is offline
      if [[ "$remote" == "Zurg" ]]; then
        if ! curl -s --connect-timeout 3 http://127.0.0.1:9999/ >/dev/null 2>&1 && ! curl -s --connect-timeout 3 https://zurg.hemati.com/ >/dev/null 2>&1; then
          echo "⚠️ Zurg WebDAV is offline. Skipping watchdog check."
          continue
        fi
      fi

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

# Installs the open-wispr GNOME extension 
install-openwispr:
    source $HOME/.config/environment.d/envvars.conf

    ARCH="$(uname -m)"
    case "$ARCH" in x86_64) BIN="openwispr-linux-amd64" ;; aarch64|arm64) BIN="openwispr-linux-arm64" ;; *) echo "Unsupported architecture: $ARCH"; exit 1 ;; esac
    REPO="https://github.com/tnfssc/openwispr-gnome-extension/releases/latest/download"
    TMP="$(mktemp -d)"

    mkdir -p $DOTS/config/systemd/user $DOTS/local/bin $HOME/.local/share/applications $HOME/.local/share/icons/hicolor/256x256/apps

    curl -fsSL "$REPO/${BIN}.tar.gz" -o "$TMP/${BIN}.tar.gz"
    tar -xzf "$TMP/${BIN}.tar.gz" -C "$TMP"
    install -Dm755 "$TMP/$BIN" $HOME/.local/bin/openwispr

    curl -fsSL "$REPO/openwispr-engine.service" -o $DOTS/config/systemd/user/openwispr-engine.service
    curl -fsSL "$REPO/openwispr-hotkeyd.service" -o $DOTS/config/systemd/user/openwispr-hotkeyd.service
    curl -fsSL "$REPO/io.github.tnfssc.openwispr.desktop" -o $HOME/.local/share/applications/io.github.tnfssc.openwispr.desktop
    curl -fsSL "$REPO/openwispr.png" -o $HOME/.local/share/icons/hicolor/256x256/apps/io.github.tnfssc.openwispr.png

    cd $DOTS
    stow -v -t $HOME/.local local
    stow -v -t $HOME/.config config
    cd -

# Script to clean up macOS AppleDouble sidecar files (._*) and .DS_Store files
clean-apple:
    #!/usr/bin/env bash

    set -euo pipefail

    TARGET_DIR="${1:-/var/home/eric/.mnt/10T/Documents/Notes}"

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Error: Directory '$TARGET_DIR' does not exist."
        exit 1
    fi

    echo "Target directory: $TARGET_DIR"
    echo "Searching for macOS hidden sidecar files (._*)..."

    # Count files to be removed
    FILE_COUNT=$(find "$TARGET_DIR" -name "._*" | wc -l)
    echo "Found $FILE_COUNT '._*' files/directories."

    if [ "$FILE_COUNT" -eq 0 ]; then
        echo "No '._*' files found. Nothing to clean!"
        exit 0
    fi

    read -p "Do you want to delete these $FILE_COUNT files/directories? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting..."
        # Use -print0 and xargs -0 for handling spaces and special characters safely
        find "$TARGET_DIR" -name "._*" -print0 | xargs -0 rm -rf
        echo "Done! Cleaned up $FILE_COUNT '._*' files."
    else
        echo "Cancelled. No files were deleted."
    fi
    
# =============================================================================
# BACKUP NEXTCLOUD DATABASE, CONFIG AND QUADLETS (KEEPS LAST 4 BACKUPS)
# =============================================================================

backup-nextcloud:
    #!/usr/bin/env bash
    set -euo pipefail

    # Source secrets if available to get MYSQL_ROOT_PASSWORD
    if [ -f "$HOME/.secrets" ]; then
      source "$HOME/.secrets"
    fi

    TARGET_DIR="$HOME/.mnt/10T/Backups/nextcloud"
    BACKUP_DIR="$TARGET_DIR/nextcloud_$(date +%Y%m%d_%H%M%S)"
    
    echo "Starting Nextcloud backup to $TARGET_DIR..."
    mkdir -p "$BACKUP_DIR"

    # 1. Dump the database (MariaDB)
    echo "Dumping MariaDB database..."
    if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
      podman exec -i nextcloud-db mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" nextcloud > "$BACKUP_DIR/db_dump.sql"
    elif [ -n "${MYSQL_PASSWORD:-}" ]; then
      podman exec -i nextcloud-db mariadb-dump -u eric -p"$MYSQL_PASSWORD" nextcloud > "$BACKUP_DIR/db_dump.sql"
    else
      echo "Error: No database password found in environment or ~/.secrets" >&2
      exit 1
    fi

    # 2. Backup Nextcloud config directory (moved from SSD appdata to ~/.local/share/nextcloud/config)
    echo "Copying config folder..."
    if [ -d "$HOME/.local/share/nextcloud/config" ]; then
      podman unshare tar -cf - -C "$HOME/.local/share/nextcloud" config | tar -xf - -C "$BACKUP_DIR"
      chmod -R u+rw "$BACKUP_DIR/config"
    else
      echo "Warning: Nextcloud config directory not found at ~/.local/share/nextcloud/config" >&2
    fi

    # 3. Backup your Quadlet definition files (including subdirectories like nextcloud)
    echo "Copying Quadlet files..."
    mkdir -p "$BACKUP_DIR/quadlets"
    cp -r "$HOME/.config/containers/systemd/"* "$BACKUP_DIR/quadlets/" 2>/dev/null || true

    # 4. Retention: Delete backups older than 4 days
    echo "Cleaning up old backups (keeping last 4 days)..."
    find "$TARGET_DIR" -maxdepth 1 -type d -name "nextcloud_*" -mtime +3 -exec rm -rf {} \;
    
    echo "Backup complete!"
