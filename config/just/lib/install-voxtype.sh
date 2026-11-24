#!/usr/bin/env bash
# Installs and configures Voxtype push-to-talk voice-to-text on Linux and macOS
set -euo pipefail

OS="$(uname -s)"
DOTS="${DOTS:-$HOME/src/dots}"

echo "=== Installing and Configuring Voxtype ($OS) ==="

if [ "$OS" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew is required on macOS. Install it from https://brew.sh"
    exit 1
  fi
  echo "[ 🍺 Installing Voxtype via Homebrew... ]"
  brew tap peteonrails/voxtype 2>/dev/null || true
  brew install --cask peteonrails/voxtype/voxtype

  mkdir -p "$HOME/.config/voxtype" "$HOME/Library/Application Support/voxtype"
  if [ -f "$DOTS/config/voxtype/config.toml" ]; then
    echo "[ ⚙️ Deploying Voxtype config from dotfiles... ]"
    ln -sfn "$DOTS/config/voxtype/config.toml" "$HOME/Library/Application Support/voxtype/config.toml"
    ln -sfn "$DOTS/config/voxtype/config.toml" "$HOME/.config/voxtype/config.toml"
  fi

  echo "[ 📥 Setting up model (large-v3-turbo)... ]"
  voxtype setup --model large-v3-turbo --download || true

  echo "[ 🚀 Setting up Voxtype.app bundle and Login Item... ]"
  voxtype setup app-bundle

  echo "✅ Voxtype installed and configured on macOS!"
  echo "👉 Ensure Microphone, Accessibility, and Input Monitoring permissions are granted to Voxtype.app in System Settings."

elif [ "$OS" = "Linux" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  echo "[ 📥 Fetching latest Voxtype release from GitHub... ]"
  LATEST_URL=$(curl -sSL https://api.github.com/repos/peteonrails/voxtype/releases/latest 2>/dev/null | grep "browser_download_url.*\.rpm" | head -n 1 | cut -d '"' -f 4 || true)
  if [ -z "$LATEST_URL" ]; then
    LATEST_URL="https://github.com/peteonrails/voxtype/releases/latest/download/voxtype-0.7.1-1.x86_64.rpm"
  fi

  curl -fsSL "$LATEST_URL" -o "$TMP/voxtype.rpm"
  cd "$TMP"
  rpm2cpio voxtype.rpm | cpio -idmv >/dev/null 2>&1

  mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/voxtype" "$HOME/.local/share/voxtype/models"

  # Install backend binary (prefer Vulkan GPU acceleration if available, fallback to avx2)
  if [ -f "usr/lib/voxtype/voxtype-vulkan" ]; then
    echo "[ ⚡ Installing Vulkan GPU-accelerated backend... ]"
    install -Dm755 usr/lib/voxtype/voxtype-vulkan "$HOME/.local/bin/voxtype"
  elif [ -f "usr/lib/voxtype/voxtype-avx2" ]; then
    echo "[ 💻 Installing AVX2 CPU backend... ]"
    install -Dm755 usr/lib/voxtype/voxtype-avx2 "$HOME/.local/bin/voxtype"
  else
    install -Dm755 usr/bin/voxtype "$HOME/.local/bin/voxtype"
  fi

  # Ensure ydotoold user service
  if [ -f "$DOTS/config/systemd/user/ydotoold.service" ]; then
    cp "$DOTS/config/systemd/user/ydotoold.service" "$HOME/.config/systemd/user/ydotoold.service"
  fi

  # Deploy voxtype config
  if [ -f "$DOTS/config/voxtype/config.toml" ]; then
    echo "[ ⚙️ Deploying Voxtype config from dotfiles... ]"
    ln -sfn "$DOTS/config/voxtype/config.toml" "$HOME/.config/voxtype/config.toml"
  fi

  # Download model if not present
  if [ ! -f "$HOME/.local/share/voxtype/models/ggml-large-v3-turbo.bin" ]; then
    echo "[ 📥 Downloading large-v3-turbo model... ]"
    "$HOME/.local/bin/voxtype" setup --model large-v3-turbo --download || true
  fi

  # Generate voxtype systemd user service
  "$HOME/.local/bin/voxtype" setup systemd --no-post-install 2>/dev/null || true

  echo "[ 🔄 Reloading and enabling systemd user services... ]"
  systemctl --user daemon-reload
  systemctl --user enable --now ydotoold || true
  systemctl --user enable --now voxtype || true

  echo "✅ Voxtype installed and running on Linux!"
else
  echo "❌ Unsupported operating system: $OS"
  exit 1
fi
