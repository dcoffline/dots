#!/bin/bash
set -e

# The Fortress Bootstrapper
DOTS="$HOME/src/gh/dcoffline/dots"

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
  else
    echo "Error: Could not install stow automatically."
    exit 1
  fi
fi

# 2. Run package installer
if [ -f "$DOTS/install-packages.sh" ]; then
  echo "[ Running package installer... ]"
  bash "$DOTS/install-packages.sh"
fi

# 3. Apply Stow
if [ -d "$DOTS" ]; then
  echo "[ Applying dotfiles with Stow... ]"
  cd "$DOTS"
  # Stow current directory (dots) into $HOME
  stow -R -v -t "$HOME" home
  stow -R -v -t "$HOME/.config" config
  stow -R -v -t "$HOME/.local" local
else
  echo "Error: Repository not found at $DOTS"
  exit 1
fi

echo "✅ Fortress bootstrap complete!"
