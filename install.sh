#!/bin/bash

# The Fortress Bootstrapper
set -e
set -a
source ./config/environment.d/envvars.conf
set +a
source ./config/bash/os.bash

echo "🛡️  Bootstrapping the Fortress..."

# 1. Ensure Stow is installed
if ! command -v stow >/dev/null 2>&1; then
  echo "[ Stow not found. Installing... ]"
  if [ -f /run/ostree-booted ]; then
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
  elif [ "$IS_MAC" -eq 1 ]; then
    brew install stow
  else
    echo "Error: Could not install stow automatically."
    exit 1
  fi
fi

# 2. Run package installer
if [ -f "./install-pkg.sh" ]; then
  echo "[ Running package installer... ]"
  bash "./install-pkg.sh"
fi

# 3. Apply Stow
echo "[ Applying dotfiles with Stow... ]"
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/homelab"
stow -v -t "$HOME" home
stow -v -t "$HOME/.local" local
stow -v -t "$HOME/.config" config

echo "✅ Fortress bootstrap complete!"
