#!/bin/bash

# Package installation script for the Fortress

# Sourcing environment if run directly/independently
if [ -z "$ENV_TYPE" ] || [ -z "$DOTS" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  set -a
  [ -f "$SCRIPT_DIR/config/environment.d/envvars.conf" ] && source "$SCRIPT_DIR/config/environment.d/envvars.conf"
  [ -f "$SCRIPT_DIR/config/bash/os.bash" ] && source "$SCRIPT_DIR/config/bash/os.bash"
  set +a
fi

FONTDIR="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
GNOME_INI="config/dconf-backups/gnome-shell.ini"

# =========================================================
# HOST-SPECIFIC (Homebrew)
# =========================================================
if [ "$ENV_TYPE" = "immutable" ]; then
  echo "[ Host-specific environment detected. Using Brewfile... ]"
  if command -v brew >/dev/null 2>&1; then
    # Trust Brewfile taps to prevent trust prompts / warnings
    brew trust achannarasappa/tap browsh-org/browsh jotta/cli lizardbyte/homebrew macos-fuse-t/cask nikitabobko/tap samtay/tui ublue-os/tap valkyrie00/bbrew 2>/dev/null || true
    brew bundle --file="$DOTS/Brewfile"
  else
    echo "[ Homebrew not found; skipping Brewfile ]"
  fi
fi

# =========================================================
# CONTAINER / MUTABLE
# =========================================================
if [ "$ENV_TYPE" != "immutable" ]; then

  # Fedora-based systems
  if command -v dnf >/dev/null 2>&1; then
    echo "[ Fedora-based system detected. Using DNF... ]"
    if [ ! -f /etc/yum.repos.d/jotta-cli.repo ] && [ ! -f /etc/yum.repos.d/JottaCLI.repo ]; then
      echo "[ Configuring Jottacloud CLI repository... ]"
      sudo mkdir -p /etc/pki/rpm-gpg
      sudo sh -c 'curl -s https://repo.jotta.cloud/jotta.gpg | gpg --no-default-keyring --keyring /tmp/jotta_temp.gpg --import && gpg --no-default-keyring --keyring /tmp/jotta_temp.gpg --export --armor > /etc/pki/rpm-gpg/RPM-GPG-KEY-jotta && rm -f /tmp/jotta_temp.gpg' 2>/dev/null || true
      sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-jotta 2>/dev/null || true
      sudo tee /etc/yum.repos.d/jotta-cli.repo >/dev/null <<'EOF'
[jotta-cli]
name=Jottacloud CLI
baseurl=https://repo.jotta.cloud/redhat
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-jotta https://repo.jotta.cloud/public.gpg
EOF
    fi
    DNF_PACKAGES=(
      busybox cava chafa direnv fastfetch gh git-crypt glab gcc jotta-cli make
      neovim nodejs npm pipx ShellCheck sops stress-ng trash-cli weston which yq
    )
    sudo dnf install -y --skip-unavailable "${DNF_PACKAGES[@]}"
    EXPORT_BINS=(
      busybox cava gh git git-crypt glab jotta-cli shellcheck sops stress-ng weston
    )

    # Ubuntu-based systems
  elif command -v apt-get >/dev/null 2>&1; then
    echo "[ Debian/Ubuntu-based system detected. Using APT... ]"
    if [ ! -f /etc/apt/sources.list.d/jotta-cli.list ]; then
      echo "[ Configuring Jottacloud CLI repository... ]"
      sudo mkdir -p /usr/share/keyrings
      sudo curl -fsSL https://repo.jotta.cloud/jotta.gpg -o /usr/share/keyrings/jotta.gpg
      echo "deb [signed-by=/usr/share/keyrings/jotta.gpg] https://repo.jotta.cloud/debian debian main" | sudo tee /etc/apt/sources.list.d/jotta-cli.list >/dev/null
    fi
    sudo apt-get update
    APT_PACKAGES=(
      busybox cava chafa direnv fastfetch gh git-crypt glab gcc jotta-cli make
      neovim nodejs npm pipx shellcheck sops stress-ng trash-cli weston which yq
    )
    sudo apt-get install -y "${APT_PACKAGES[@]}"

    # Arch-based systems
  elif command -v pacman >/dev/null 2>&1; then
    echo "[ ARCH-based system detected. Using PACMAN/yay... ]"
    ARCH_PACKAGES=(
      busybox chafa direnv fastfetch github-cli glab gcc jotta-cli make npm
      neovim nodejs python-pipx shellcheck sops stress-ng trash-cli which yq
    )
    if command -v yay >/dev/null 2>&1 && yay --version >/dev/null 2>&1; then
      yay -S --noconfirm "${ARCH_PACKAGES[@]}"
    else
      echo "[ yay is not available or broken. Falling back to pacman package-by-package... ]"
      for pkg in "${ARCH_PACKAGES[@]}"; do
        sudo pacman -S --noconfirm --needed "$pkg" || echo "[ Warning: Failed to install $pkg via pacman ]"
      done
    fi
  fi

  # DISTROBOX EXPORTS
  if [ -f /run/.containerenv ] && [ -n "${EXPORT_BINS[*]}" ]; then
    echo "[ Exporting select binaries to Host... ]"
    for bin in "${EXPORT_BINS[@]}"; do
      BIN_PATH=$(which -a "$bin" 2>/dev/null | grep -v "$HOME" | head -n 1)
      if [ -n "$BIN_PATH" ]; then
        distrobox-export --bin "$BIN_PATH" --export-path "$HOME/.local/bin"
      fi
    done
  fi
fi

# =========================================================
# UNIVERSAL (Host-aware)
# =========================================================

# RUST & CARGO TOOLCHAINS
echo "[ Checking for Rust toolchain... ]"
CARGO_BIN_DIR="${CARGO_HOME:-$HOME/.cargo}/bin"
export PATH="$CARGO_BIN_DIR:$PATH"

if ! cargo --version >/dev/null 2>&1; then
  if command -v rustup >/dev/null 2>&1; then
    echo "[ Initializing Rustup toolchain... ]"
    rustup default stable
  else
    echo "[ Cargo not found. Installing Rustup... ]"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  fi

  if [ -f "${CARGO_HOME:-$HOME/.cargo}/env" ]; then
    source "${CARGO_HOME:-$HOME/.cargo}/env"
  elif [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
  fi
fi

# RUST BINARIES
echo "[ Installing Rust binaries... ]"
if cargo --version >/dev/null 2>&1; then
  # Install cargo-binstall for lightning-fast, pre-compiled deployments
  if ! command -v cargo-binstall >/dev/null 2>&1; then
    echo "[ Installing cargo-binstall... ]"
    cargo install cargo-binstall
  fi
  CARGO_PACKAGES=(
    atuin bat dysk eza fd-find ripgrep starship
    tealdeer television yazi-fm yazi-cli zoxide
  )
  echo "[ Fetching pre-compiled binaries... ]"
  cargo binstall -y "${CARGO_PACKAGES[@]}"
else
  echo "[ ERROR: Cargo is still not available. Skipping Rust binaries. ]"
fi

# NERD FONTS
FONT_NAME="CascadiaCode"
mkdir -p "$HOME/.local/share/fonts"
if ! ls ~/.local/share/fonts/*${FONT_NAME}* >/dev/null 2>&1; then
  echo "[ Installing ${FONT_NAME} Nerd Font... ]"
  TMP_ZIP=$(mktemp)
  if wget --hsts-file="$HOME/.cache/wget-hsts" -qO "$TMP_ZIP" "$FONTDIR/${FONT_NAME}.zip"; then
    unzip -qo "$TMP_ZIP" -d "$HOME/.local/share/fonts/"
    rm -f "$TMP_ZIP"
  fi
fi

# FLATPAKS
FLATPAK_APPS=(
  com.bitwarden.desktop
  com.mattjakeman.ExtensionManager
  com.github.tchx84.Flatseal
  it.mijorus.gearlever
  io.github.flattool.Ignition
  io.github.fabrialberio.pinapp
  page.tesk.Refine
  dev.fredol.open-tv
)
echo "[ Checking GUI apps... ]"

for app in "${FLATPAK_APPS[@]}"; do
  if [ "$ENV_TYPE" = "container" ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    if ! distrobox-host-exec flatpak list --app --columns=application | grep -q "^$app$"; then
      distrobox-host-exec flatpak install --system -y flathub "$app"
    fi
  elif command -v flatpak >/dev/null 2>&1; then
    if ! flatpak list --app --columns=application | grep -q "^$app$"; then
      sudo flatpak install --system -y flathub "$app"
    fi
  fi
done

# PODMAN API SOCKET & FLATPAK OVERRIDES
if [ "$ENV_TYPE" != "container" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    echo "[ Ensuring Podman API socket is active and initialized... ]"
    systemctl --user enable --now podman.socket 2>/dev/null || true
    if [ ! -S "/run/user/$(id -u)/podman/podman.sock" ]; then
      echo "[ Podman socket file is missing; restarting podman.socket... ]"
      systemctl --user restart podman.socket 2>/dev/null || true
    fi
  fi

  if command -v flatpak >/dev/null 2>&1; then
    echo "[ Configuring Flatpak overrides for Pods... ]"
    flatpak override --user --filesystem=xdg-run/podman:ro com.github.marhkb.Pods 2>/dev/null || true
  fi
else
  if command -v distrobox-host-exec >/dev/null 2>&1; then
    echo "[ Requesting Host to ensure Podman socket and Flatpak overrides are configured... ]"
    distrobox-host-exec systemctl --user enable --now podman.socket 2>/dev/null || true
    if ! distrobox-host-exec test -S "/run/user/\$(id -u)/podman/podman.sock"; then
      distrobox-host-exec systemctl --user restart podman.socket 2>/dev/null || true
    fi
    distrobox-host-exec flatpak override --user --filesystem=xdg-run/podman:ro com.github.marhkb.Pods 2>/dev/null || true
  fi
fi

# GNOME EXTENSIONS
if [ "${IS_LINUX:-0}" -eq 1 ]; then
  IS_GNOME=0
  if [ "$ENV_TYPE" = "container" ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    HOST_DESKTOP=$(distrobox-host-exec printenv XDG_CURRENT_DESKTOP 2>/dev/null || echo "")
    if [[ "$HOST_DESKTOP" =~ "GNOME" ]]; then
      IS_GNOME=1
    fi
  elif [[ "$XDG_CURRENT_DESKTOP" =~ "GNOME" ]]; then
    IS_GNOME=1
  fi

  if [ "$IS_GNOME" -eq 1 ]; then
    GNOME_EXTENSIONS=(
      "allowlockedremotedesktop@kamens.us"
      "all-windows-srwp@jkavery.github.io"
      "AlphabeticalAppGrid@stuarthayhurst"
      "blur-my-shell@aunetx"
      "clipboard-indicator@tudmotu.com"
      "dynamic-music-pill@andbal"
      "logomenu-fixed@dcoffline"
      "openwispr-gnome-extension"
      "panel-workspace-scroll@polymeilex.github.io"
      "randomwallpaper@iflow.space"
      "screentospace@dilzhan.dev"
      "smart-pause-resume@erenseymen.github.io"
      "status-area-horizontal-spacing@mathematical.coffee.gmail.com"
      "tailscale-gnome@diskmth.fr"
      "tilingshell@ferrarodomenico.com"
      "transparent-window-moving@noobsai.github.com"
      "tweaks-system-menu@extensions.gnome-shell.fifi.org"
      "window-list@gnome-shell-extensions.gcampax.github.com"
      "workspace-bar@jguece"
    )

    if ! command -v gext >/dev/null 2>&1; then
      echo "[ gext not found. Attempting to install gnome-extensions-cli... ]"
      if command -v pipx >/dev/null 2>&1; then
        pipx install gnome-extensions-cli --system-site-packages || true
      elif command -v pip >/dev/null 2>&1; then
        pip install --user gnome-extensions-cli || true
      fi
    fi

    if command -v gext >/dev/null 2>&1; then
      echo "[ Installing GNOME Extensions locally... ]"
      for ext in "${GNOME_EXTENSIONS[@]}"; do
        gext install "$ext" 2>/dev/null || true
      done
    elif [ "$ENV_TYPE" = "container" ] && command -v distrobox-host-exec >/dev/null 2>&1; then
      echo "[ Installing GNOME Extensions via Host... ]"
      for ext in "${GNOME_EXTENSIONS[@]}"; do
        distrobox-host-exec gext install "$ext" 2>/dev/null || true
      done
    fi

    # Load DCONF
    if command -v dconf >/dev/null 2>&1; then
      echo "[ Loading GNOME Shell DCONF settings... ]"
      dconf load /org/gnome/shell/ <"$DOTS/$GNOME_INI"
    elif [ "$ENV_TYPE" = "container" ] && command -v distrobox-host-exec >/dev/null 2>&1; then
      echo "[ Loading GNOME Shell DCONF settings via Host... ]"
      distrobox-host-exec dconf load /org/gnome/shell/ <"$DOTS/$GNOME_INI"
    fi
  fi
fi

echo "[ Fortress package installation complete ]"
