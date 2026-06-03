#!/bin/bash

# The Fortress Bootstrapper
set -e

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export all environment variables sourced from configuration
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

# 2. Run package installer
if [ -f "$SCRIPT_DIR/install-pkg.sh" ]; then
  echo "[ Running package installer... ]"
  bash "$SCRIPT_DIR/install-pkg.sh"
fi

# 3. Apply Stow
echo "[ Applying dotfiles with Stow... ]"
mkdir -p "$HOME/.config/systemd/user"
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' -R -v -t "$HOME" home
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' -R -v -t "$HOME/.local" local
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' -R -v -t "$HOME/.config" config

echo "✅ Fortress bootstrap complete!"
