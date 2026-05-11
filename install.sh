#!/bin/bash
set -e

# The Fortress Bootstrapper
set -a
source ./config/environment.d/envvars.conf
set +a
mkdir -p $DOTS
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/homelab"
mkdir -p "$HOME/.config"

source ./config/bash/os.bash

echo "🛡️  Bootstrapping the Fortress..."

# 1. Ensure Stow is installed
if ! command -v stow >/dev/null 2>&1; then
  echo "[ Stow not found. Installing... ]"
  if [ -f /run/ostree-booted ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install stow
    else
      echo "Error: Homebrew is required on immutable hosts."
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
if [ -f "$DOTS/install-pkg.sh" ]; then
  echo "[ Running package installer... ]"
  bash "$DOTS/install-pkg.sh"
fi

# 3. Apply Stow
if [ -d "$DOTS" ]; then
  echo "[ Applying dotfiles with Stow... ]"
  mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share"
  cd "$DOTS"
  # Stow current directory (dots) into $HOME
  stow -v -t "$HOME" home
  stow -v -t "$HOME/.local" local
  stow -v -t "$HOME/.config" config
else
  echo "Error: Repository not found at $DOTS"
  exit 1
fi

echo "✅ Fortress bootstrap complete!"
