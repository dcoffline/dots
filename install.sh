#!/bin/bash

# The Fortress Bootstrapper
set -e

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export all environment variables sourced from configuration
mkdir -p "$HOME/.local/bin" "$HOME/.local/scripts" "$HOME/.config/systemd/user"
set -a
[ -f "$SCRIPT_DIR/config/environment.d/envvars.conf" ] && source "$SCRIPT_DIR/config/environment.d/envvars.conf"
[ -f "$SCRIPT_DIR/config/bash/os.bash" ] && source "$SCRIPT_DIR/config/bash/os.bash"
set +a

# =========================================================
# ENVIRONMENT DETECTION
# =========================================================
if [ "$ENV_TYPE" == "container" ]; then
  echo "[ 🏗️  Container environment detected ]"
elif [ "$ENV_TYPE" == "immutable" ]; then
  echo "[ 🛡️  Immutable host detected ]"
else
  echo "[ 💻 Standard mutable host detected ]"
fi

echo "🛡️  Bootstrapping the Fortress..."

# =========================================================
# 1. ENSURE STOW IS INSTALLED
# =========================================================
if ! command -v stow >/dev/null 2>&1; then
  echo "[ Stow not found. Installing... ]"
  if [ "$ENV_TYPE" == "immutable" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install stow
    else
      echo "Error: Homebrew is required on immutable systems."
      exit 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y stow
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y stow
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm stow
  else
    echo "Error: Could not install stow automatically."
    exit 1
  fi
fi

# =========================================================
# HELPER FUNCTIONS FOR BACKING UP EXISTING TARGETS
# =========================================================

# Helper: check if a target is a symlink pointing into the dotfiles repository
is_link_to_dots() {
  local target="$1"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(readlink -f "$target" 2>/dev/null || readlink "$target")"
    if [[ "$link_target" == "$SCRIPT_DIR"* ]]; then
      return 0
    fi
  fi
  return 1
}

# Helper: recursively inspect and backup existing non-symlink files/directories
backup_item_recursive() {
  local src="$1"
  local dst="$2"

  [ -e "$src" ] || return 0

  # If dst exists and already links to our dots repo, skip
  if is_link_to_dots "$dst"; then
    return 0
  fi

  # If both src and dst are directories (and dst is not a symlink), traverse down
  if [ -d "$src" ] && [ -d "$dst" ] && [ ! -L "$dst" ]; then
    for child in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$child" ] || continue
      local child_name="$(basename "$child")"
      [[ "$child_name" == ".DS_Store" || "$child_name" == "._*" || "$child_name" == "*" ]] && continue
      backup_item_recursive "$child" "$dst/$child_name"
    done
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    # dst is a real file or leaf directory that would conflict with stow
    echo "[ 📦 Backing up existing: $dst -> ${dst}.bak ]"
    rm -rf "${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
}

# Backup existing files and directories for a stow package
backup_package() {
  local pkg_name="$1"
  local target_base="$2"
  local pkg_dir="$SCRIPT_DIR/$pkg_name"

  [ -d "$pkg_dir" ] || return 0

  for item in "$pkg_dir"/* "$pkg_dir"/.[!.]* "$pkg_dir"/..?*; do
    [ -e "$item" ] || continue
    local name="$(basename "$item")"
    [[ "$name" == ".DS_Store" || "$name" == "._*" || "$name" == "*" ]] && continue
    backup_item_recursive "$item" "$target_base/$name"
  done
}

# =========================================================
# 2. BACKUP EXISTING CONFLICTING TARGETS
# =========================================================
echo "[ Checking for existing configurations to back up (*.bak)... ]"
backup_package "home" "$HOME"
backup_package "local" "$HOME/.local"
backup_package "config" "$HOME/.config"
if [ "${IS_MAC:-0}" -eq 1 ]; then
  backup_package "Library" "$HOME/Library"
fi

# =========================================================
# 3. APPLY DOTFILES WITH STOW
# =========================================================
echo "[ Applying dotfiles with Stow... ]"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin" "$HOME/.local/scripts" "$HOME/.local/share/gnome-shell/extensions" "$HOME/.config/rclone"
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME" home
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.local" local
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.config" config
if [ "${IS_MAC:-0}" -eq 1 ]; then
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/Library" Library
fi

# =========================================================
# 4. RUN PACKAGE INSTALLER
# =========================================================
if [ -f "$SCRIPT_DIR/install-pkg.sh" ]; then
  echo "[ Running package installer... ]"
  bash "$SCRIPT_DIR/install-pkg.sh"
fi

# =========================================================
# 5. ENABLE GNOME SHELL EXTENSIONS IF APPLICABLE
# =========================================================
if command -v gsettings >/dev/null 2>&1; then
  echo "[ Configuring GNOME Shell extensions... ]"
  current_extensions=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
  if [[ "$current_extensions" != *"logomenu-fixed@dcoffline"* ]]; then
    if [[ "$current_extensions" == "@as []" || "$current_extensions" == "[]" ]]; then
      gsettings set org.gnome.shell enabled-extensions "['logomenu-fixed@dcoffline']"
    else
      new_extensions=$(echo "$current_extensions" | sed "s/]/, 'logomenu-fixed@dcoffline']/g")
      gsettings set org.gnome.shell enabled-extensions "$new_extensions"
    fi
  fi
fi

echo "✅ Fortress bootstrap complete!"
