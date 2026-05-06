#!/bin/bash

# Package installation script for the Fortress

DOTS="$HOME/src/gh/dcoffline/dots"
FONTDIR="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
GNOME_INI="config/dconf-backups/gnome-shell.ini"

# =========================================================
# IMMUTABLE (Host)
# =========================================================
if [ -f /run/ostree-booted ]; then
  echo "[ Immutable host detected. Using Brewfile... ]"

  if command -v brew >/dev/null 2>&1; then
    brew bundle --file="$DOTS/Brewfile"
  else
    echo "[ Homebrew not found; skipping Brewfile ]"
  fi

# =========================================================
# CONTAINER / MUTABLE
# =========================================================
else
  if command -v dnf >/dev/null 2>&1; then
    echo "[ Fedora-based system detected. Using DNF... ]"
    sudo dnf -y copr enable lihaohong/yazi
    sudo dnf -y copr enable atim/starship
    sudo dnf -y copr enable fernando-debian/dysk
    DNF_PACKAGES=(
      bat chafa direnv dysk eza fastfetch fd-find flatpak gh
      glab gcc golang npm nodejs pipx ripgrep ShellCheck 
      starship stress-ng tealdeer trash-cli yazi yq zoxide
    )
    sudo dnf install -y --skip-unavailable "${DNF_PACKAGES[@]}"
    EXPORT_BINS=(dysk gh glab shellcheck stress-ng)

  elif command -v apt-get >/dev/null 2>&1; then
    echo "[ Debian/Ubuntu-based system detected. Using APT... ]"
    sudo apt-get update
    APT_PACKAGES=(
      bat chafa direnv eza fastfetch fd-find flatpak gh 
      glab gcc golang nodejs npm pipx ripgrep shellcheck 
      starship stress-ng tealdeer trash-cli yazi yq zoxide
    )
    sudo apt-get install -y "${APT_PACKAGES[@]}"

  elif command -v pacman >/dev/null 2>&1; then
    echo "[ ARCH-based system detected. Using PACMAN/PARU... ]"
    ARCH_PACKAGES=(
      bat chafa direnv eza fastfetch fd flatpak github-cli 
      glab gcc go nodejs npm python-pipx ripgrep shellcheck 
      starship stress-ng tealdeer trash-cli yazi yq zoxide
    )
    if command -v paru >/dev/null 2>&1; then
      paru -S --noconfirm "${ARCH_PACKAGES[@]}"
    else
      sudo pacman -S --noconfirm "${ARCH_PACKAGES[@]}"
    fi
  fi

  # RUST & CARGO BINARIES
  echo "[ Checking for Rust toolchain... ]"
  if ! command -v cargo >/dev/null 2>&1; then
    echo "[ Cargo not found. Installing Rustup... ]"
    # Install Rust silently accepting all defaults
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # Inject Cargo into the current script's PATH so the next step works.
    # (Checking your custom XDG path first, then falling back to default)
    if [ -f "$HOME/.local/share/cargo/env" ]; then
      source "$HOME/.local/share/cargo/env"
    elif [ -f "$HOME/.cargo/env" ]; then
      source "$HOME/.cargo/env"
    fi
  fi

  echo "[ Installing Rust binaries via Cargo... ]"
  if command -v cargo >/dev/null 2>&1; then
    cargo install television atuin
  else
    echo "[ ERROR: Cargo is still not available. Skipping Rust binaries. ]"
  fi

  # NPM BINARIES
  echo "[ Installing Node binaries via NPM... ]"
  if command -v npm >/dev/null 2>&1; then
    npm install -g "@google/gemini-cli"
  else
    echo "[ ERROR: NPM is not available. Skipping Node binaries. ]"
  fi

  # DISTROBOX EXPORTS
  if [ -f /run/.containerenv ] && [ -n "${EXPORT_BINS[*]}" ]; then
    echo "[ Exporting select binaries to Host... ]"
    for bin in "${EXPORT_BINS[@]}"; do
      BIN_PATH=$(which -a "$bin" 2>/dev/null | grep -v "$HOME" | head -n 1)
      if [ -n "$BIN_PATH" ]; then
        distrobox-export --bin "$BIN_PATH"
      fi
    done
  fi
fi

# =========================================================
# UNIVERSAL (Host-aware)
# =========================================================

# FLATPAKS
FLATPAK_APPS=(
  app.zen_browser.zen
  com.bitwarden.desktop
  com.brave.Browser
  com.stremio.Service
  org.freefilesync.FreeFileSync
)

echo "[ Checking GUI apps... ]"
for app in "${FLATPAK_APPS[@]}"; do
  if [ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    if ! distrobox-host-exec flatpak list --app --columns=application | grep -q "^$app$"; then
      distrobox-host-exec flatpak install --system -y flathub "$app"
    fi
  elif command -v flatpak >/dev/null 2>&1; then
    if ! flatpak list --app --columns=application | grep -q "^$app$"; then
      sudo flatpak install --system -y flathub "$app"
    fi
  fi
done

# NERD FONTS
FONT_NAME="CascadiaCode"
mkdir -p ~/.local/share/fonts
if ! ls ~/.local/share/fonts/*${FONT_NAME}* >/dev/null 2>&1; then
  echo "[ Installing ${FONT_NAME} Nerd Font... ]"
  TMP_ZIP=$(mktemp)
  if wget --hsts-file="$HOME/.cache/wget-hsts" -qO "$TMP_ZIP" "$FONTDIR/${FONT_NAME}.zip"; then
    unzip -qo "$TMP_ZIP" -d ~/.local/share/fonts/
    rm -f "$TMP_ZIP"
  fi
fi

# GNOME EXTENSIONS
GNOME_EXTENSIONS=(
  "AlphabeticalAppGrid@stuarthayhurst"
  "app-hider@lynith.dev"
  "clipboard-indicator@tudmotu.com"
  "screentospace@dilzhan.dev"
  "status-area-horizontal-spacing@mathematical.coffee.gmail.com"
  "tailscale-status@maxgallup.github.com"
  "tilingshell@ferrarodomenico.com"
  "transparent-window-moving@noobsai.github.com"
  "tweaks-system-menu@extensions.gnome-shell.fifi.org"
  "azwallpaper@azwallpaper.gitlab.com"
  "window-list@gnome-shell-extensions.gcampax.github.com"
)

if ! command -v gext >/dev/null 2>&1 && [ ! -f /run/.containerenv ]; then
  pipx install gnome-extensions-cli --system-site-packages || true
fi

if command -v gext >/dev/null 2>&1 || ([ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null 2>&1); then
  echo "[ Installing GNOME Extensions... ]"
  for ext in "${GNOME_EXTENSIONS[@]}"; do
    if [ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null 2>&1; then
      distrobox-host-exec gext install "$ext" 2>/dev/null || true
    else
      gext install "$ext" 2>/dev/null || true
    fi
  done

  # Load DCONF
  if [ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    distrobox-host-exec dconf load /org/gnome/shell/ <"$DOTS/$GNOME_INI"
  else
    dconf load /org/gnome/shell/ <"$DOTS/$GNOME_INI"
  fi
fi

echo "[ Fortress package installation complete ]"
