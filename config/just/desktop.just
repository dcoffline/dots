# =============================================================================
# DESKTOP, DISPLAY & STREAMING MAINTENANCE
# =============================================================================

# Upgrades Sunshine, reapplies KMS/uhid capabilities, fixes Qt plugin links, and restarts the service
update-sunshine:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> Upgrading Sunshine Game Stream Host..."
    brew unpin sunshine 2>/dev/null || true
    trap 'brew pin sunshine 2>/dev/null || true' EXIT

    brew upgrade sunshine

    POSTINST="$(brew --prefix sunshine)/bin/postinst"
    if [ -x "$POSTINST" ]; then
        echo "==> Running post-install setup (requires sudo for capabilities and udev rules)..."
        sudo "$POSTINST"
    elif [ -x /usr/libexec/sunshine-postinst ]; then
        echo "==> Running Bazzite sunshine-postinst..."
        sudo /usr/libexec/sunshine-postinst
    else
        echo "==> Applying KMS capture capabilities..."
        sudo setcap cap_sys_admin,cap_sys_nice+p "$(readlink -f "$(which sunshine)")"
    fi

    # Refresh KWin Screencast Wayland permission desktop file with current Cellar path
    mkdir -p "$HOME/.local/share/applications"
    cat <<EOF > "$HOME/.local/share/applications/dev.lizardbyte.app.Sunshine.kwin.desktop"
    [Desktop Entry]
    Exec=$(readlink -f "$(which sunshine)")
    X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1
    Type=Application
    Name=dev.lizardbyte.app.Sunshine-kwin-wayland-permission
    Comment=Sunshine KWin screencast permission
    NoDisplay=true
    EOF
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 2>/dev/null || true

    # Fix potential Homebrew Qt plugin collisions on ostree/Silverblue
    if brew list qtbase >/dev/null 2>&1; then
        brew link --overwrite qtbase >/dev/null 2>&1 || true
    fi
    if brew list qtsvg >/dev/null 2>&1; then
        brew link --overwrite qtsvg >/dev/null 2>&1 || true
    fi

    echo "==> Restarting Sunshine user service..."
    systemctl --user restart sunshine.service

    echo "==> Sunshine update completed successfully!"
    systemctl --user status sunshine.service --no-pager

# Recovers Moonlight/Sunshine streaming by restarting plasmashell (if hung on D-Bus) and Sunshine
fix-sunshine:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "⚠️ fix-sunshine is only applicable on Linux (KDE/Sunshine)."
        exit 0
    fi

    echo "==> Restarting plasma-plasmashell.service (clears hung org.freedesktop.Notifications)..."
    host_exec systemctl --user restart plasma-plasmashell.service

    echo "==> Waiting for org.freedesktop.Notifications on D-Bus..."
    for _ in {1..15}; do
        if host_exec busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.DBus.Peer Ping >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    echo "==> Restarting Sunshine user service..."
    host_exec systemctl --user restart app-dev.lizardbyte.app.Sunshine.service

    echo "==> Status:"
    host_exec systemctl --user status plasma-plasmashell.service app-dev.lizardbyte.app.Sunshine.service --no-pager | grep -E "●|Active:|Main PID:" || true
    echo "✅ Sunshine recovery complete!"

# Applies GPU flicker-prevention flags to Electron & Chromium apps (optional [app] filter)
fix-flicker target="":
    #!/usr/bin/env bash
    exec python3 "$HOME/.config/just/lib/fix-flicker.py" "{{target}}"
