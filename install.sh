#!/bin/bash
set -e

# The Fortress Bootstrapper (Chezmoi Edition)
DOTS_DIR="$HOME/src/gh/dcoffline/dots"

echo "🛡️  Bootstrapping the Fortress..."

# 1. Ensure Chezmoi is installed
if ! command -v chezmoi >/dev/null 2>&1; then
    echo "[ Chezmoi not found. Installing... ]"
    if [ -f /run/ostree-booted ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install chezmoi
        else
            echo "Error: Homebrew is required on immutable hosts."
            exit 1
        fi
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y chezmoi
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y chezmoi
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm chezmoi
    else
        # Fallback to binary install
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi

# 2. Initialize Chezmoi
if [ -d "$DOTS_DIR" ]; then
    echo "[ Initializing Chezmoi from $DOTS_DIR... ]"
    chezmoi init --apply --source="$DOTS_DIR"
else
    echo "Error: Repository not found at $DOTS_DIR"
    exit 1
fi

echo "✅ Fortress bootstrap complete!"
