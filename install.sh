#!/bin/bash

# The Fortress Bootstrapper
set -e

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export all environment variables sourced from configuration
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
set -a
source "$SCRIPT_DIR/config/environment.d/envvars.conf"
source "$SCRIPT_DIR/config/bash/os.bash"
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

# 1. Ensure Stow is installed
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

# 2. Apply dotfiles with stow
echo "[ Applying dotfiles with Stow... ]"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin" "$HOME/.local/share/gnome-shell/extensions"
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME" home
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.local" local
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.config" config

# 3. Run package installer
if [ -f "$SCRIPT_DIR/install-pkg.sh" ]; then
  echo "[ Running package installer... ]"
  bash "$SCRIPT_DIR/install-pkg.sh"
fi

# 4. Enable GNOME Shell extensions if applicable
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
