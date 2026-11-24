# =============================================================================
# DEVELOPMENT & SYSTEM TOOL INSTALLERS
# =============================================================================

# Installs CLI tools from $DOTS/Brewfile and $DOTS/install-pkg.sh on Omarchy via `omarchy pkg add` (--dry-run, --aur)
omarchy-cli *args:
    #!/usr/bin/env bash
    exec bash "$HOME/.config/just/lib/install-omarchy-cli.sh" {{args}}

# Installs the Antigravity CLI
agy:
    curl -fsSL https://antigravity.google/cli/install.sh | bash

# Installs and configures Voxtype push-to-talk voice-to-text on Linux and macOS
voxtype:
    #!/usr/bin/env bash
    exec bash "$HOME/.config/just/lib/install-voxtype.sh"

# Installs the open-wispr GNOME extension
openwispr:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f "$HOME/.config/environment.d/envvars.conf" ] && source "$HOME/.config/environment.d/envvars.conf"
    DOTS="${DOTS:-$HOME/src/dots}"

    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64)        BIN="openwispr-linux-amd64" ;;
      aarch64|arm64) BIN="openwispr-linux-arm64" ;;
      *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac

    REPO="https://github.com/tnfssc/openwispr-gnome-extension/releases/latest/download"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    mkdir -p "$DOTS/config/systemd/user" "$DOTS/local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps"

    curl -fsSL "$REPO/${BIN}.tar.gz" -o "$TMP/${BIN}.tar.gz"
    tar -xzf "$TMP/${BIN}.tar.gz" -C "$TMP"
    install -Dm755 "$TMP/$BIN" "$HOME/.local/bin/openwispr"

    curl -fsSL "$REPO/openwispr-engine.service" -o "$DOTS/config/systemd/user/openwispr-engine.service"
    curl -fsSL "$REPO/openwispr-hotkeyd.service" -o "$DOTS/config/systemd/user/openwispr-hotkeyd.service"
    curl -fsSL "$REPO/io.github.tnfssc.openwispr.desktop" -o "$HOME/.local/share/applications/io.github.tnfssc.openwispr.desktop"
    curl -fsSL "$REPO/openwispr.png" -o "$HOME/.local/share/icons/hicolor/256x256/apps/io.github.tnfssc.openwispr.png"

    cd "$DOTS"
    stow -v -t "$HOME/.local" local
    stow -v -t "$HOME/.config" config
