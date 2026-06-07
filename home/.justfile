# =============================================================================
# MULTI-OS DOTFILES MANAGEMENT
# =============================================================================

# Running 'just' with no arguments will display this menu
default:
    @just --list

# =============================================================================
# SYSTEM MAINTENANCE
# =============================================================================

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
      distrobox-host-exec dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
      sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"

      echo "[ Applying Dotfile Updates... ]"
      stow -R -v --ignore=".DS_Store" -t "$HOME" home
      stow -R -v --ignore=".DS_Store" -t "$HOME/.config" config
      stow -R -v --ignore=".DS_Store" -t "$HOME/.local" local

      echo "[ Backing up to GitHub... ]"
      git add Brewfile "$SHELLINI"
      git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
      git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."
      
      echo "[ Starting Immutable Host Update... ]"
      distrobox-host-exec ujust update

    elif [ "$ENV_TYPE" = "immutable" ]; then
      echo "[ Syncing Host State... ]"
      brew bundle dump --force || echo "⚠️ Warning: Homebrew dump failed."
      if command -v dconf >/dev/null 2>&1; then
        dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
        sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
      fi

      echo "[ Applying Dotfile Updates... ]"
      stow -R -v --ignore=".DS_Store" -t "$HOME" home
      stow -R -v --ignore=".DS_Store" -t "$HOME/.config" config
      stow -R -v --ignore=".DS_Store" -t "$HOME/.local" local

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
      if command -v dconf >/dev/null 2>&1; then
        dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
        sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
      fi
      if command -v brew >/dev/null 2>&1; then brew bundle dump --force; fi

      stow -R -v --ignore=".DS_Store" -t "$HOME" home
      stow -R -v --ignore=".DS_Store" -t "$HOME/.config" config
      stow -R -v --ignore=".DS_Store" -t "$HOME/.local" local

      git add "$SHELLINI" Brewfile
      git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
      git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."
    fi
    echo "[ Fortress Maintenance Complete ]"

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
    declare -A REMOTES=( ["alldebrid"]="AllDebrid" ["jotta"]="Archive" ["10T"]="Backup" ["bee"]="Bee" ["gdrive"]="GDrive" ["onedrive"]="OneDrive" ["realdebrid"]="RealDebrid" ["timeline"]="Timeline" ["zurg"]="Zurg" )

    if [[ "$(uname -s)" == "Darwin" ]]; then
      # ===============================
      # macOS Mount Logic
      # ===============================
      echo "[ macOS Detected - Running Mac Rclone Routine ]"
      RCLONE="/usr/local/bin/rclone"
      CACHE_DIR="$HOME/Library/Caches/rclone"
      for i in {1..12}; do ping -c1 8.8.8.8 >/dev/null 2>&1 && break; if [[ $i -eq 12 ]]; then echo "No internet" >&2; exit 1; fi; sleep 5; done

      mkdir -p "$PID_DIR" "$BASE_MOUNT" "$CACHE_DIR"
      pkill rclone 2>/dev/null || true
      sleep 2

      COMMON_FLAGS=( --vfs-cache-mode writes --cache-dir "$CACHE_DIR" --vfs-read-chunk-size=64M --vfs-cache-max-size=10G --vfs-cache-max-age=720h --log-file "$LOGFILE" --log-level INFO )
      for remote in "${!REMOTES[@]}"; do
        target="${REMOTES[$remote]}"
        mountpoint="$BASE_MOUNT/$target"
        mkdir -p "$mountpoint"
        
        EXTRA_FLAGS=()
        if [[ "$remote" == "alldebrid" || "$remote" == "realdebrid" ]]; then
          EXTRA_FLAGS=( --read-only --exclude '.DS_Store' --exclude '._*' )
        fi
        
        echo "Mounting ${remote}: → $mountpoint"
        "$RCLONE" mount "${remote}:" "$mountpoint" "${COMMON_FLAGS[@]}" "${EXTRA_FLAGS[@]}" &
        echo $! >"$PID_DIR/${remote}.pid"
      done

    else
      # ===============================
      # Linux Mount Logic
      # ===============================
      echo "[ Linux Detected - Running Linux Rclone Routine ]"
      RCLONE="rclone"
      if [ -x /home/linuxbrew/.linuxbrew/bin/rclone ]; then
        RCLONE="/home/linuxbrew/.linuxbrew/bin/rclone"
      elif [ -x /usr/bin/rclone ]; then
        RCLONE="/usr/bin/rclone"
      fi

      if [ -f /run/ostree-booted ]; then
        CACHE_DIR=/var/mnt/2T/rclone_cache
      else
        CACHE_DIR="$HOME/.cache/rclone_cache"
      fi

      COMMON_FLAGS=( --allow-other --umask 002 --dir-perms 775 --file-perms 664 --vfs-cache-mode writes --cache-dir "$CACHE_DIR" --vfs-read-chunk-size=64M --vfs-read-chunk-size-limit off --attr-timeout 10m --dir-cache-time 72h --vfs-cache-max-size=10G --vfs-cache-max-age=720h --vfs-cache-min-free-space=20G --poll-interval=1m --buffer-size 64M --log-file "$LOGFILE" --log-level INFO )

      mkdir -p "$PID_DIR" "$BASE_MOUNT" "$CACHE_DIR"
      pkill rclone 2>/dev/null || true
      sleep 2

      for remote in "${!REMOTES[@]}"; do
        target="${REMOTES[$remote]}"
        mountpoint="$BASE_MOUNT/$target"
        mkdir -p "$mountpoint"
        
        EXTRA_FLAGS=()
        if [[ "$remote" == "alldebrid" || "$remote" == "realdebrid" ]]; then
          EXTRA_FLAGS=( --read-only --exclude '.DS_Store' --exclude '._*' )
        fi

        echo "Mounting $remote → $mountpoint"
        "$RCLONE" mount "${remote}:" "$mountpoint" "${COMMON_FLAGS[@]}" "${EXTRA_FLAGS[@]}" &
        echo $! >"$PID_DIR/${remote}.pid"
      done
    fi
    
    sleep 5
    echo -e "\nMount commands issued."

# Unmounts all rclone directories
unmount:
    #!/usr/bin/env bash
    BASE_MOUNT="$HOME/.mnt/rclone"
    declare -A REMOTES=( ["alldebrid"]="AllDebrid" ["jotta"]="Archive" ["10T"]="Backup" ["gdrive"]="GDrive" ["onedrive"]="OneDrive" ["realdebrid"]="RealDebrid" ["timeline"]="Timeline" ["zurg"]="Zurg" )

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

      if mountpoint -q "$mountpoint" 2>/dev/null || df | grep -q "$mountpoint"; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
          umount "$mountpoint" 2>/dev/null || diskutil unmount force "$mountpoint"
        else
          fusermount -uz "$mountpoint" || fusermount -u "$mountpoint" || echo "Mount $mountpoint is stubborn."
        fi
      fi
    done

# =============================================================================
# DEVELOPMENT TOOLS
# =============================================================================

# Installs the Antigravity CLI
install-agy:
    curl -fsSL https://antigravity.google/cli/install.sh | bash

