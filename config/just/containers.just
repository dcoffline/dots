# =============================================================================
# CONTAINERS (PODMAN QUADLETS & LOCAL IMAGES)
# =============================================================================

# Builds or rebuilds local container images (pka-web, searxng-relay, zcc-webhook-base)
build-images:
    #!/usr/bin/env bash
    set -euo pipefail
    DOTS="${DOTS:-$HOME/src/dots}"
    echo "==> Building localhost/zcc-webhook-base:latest..."
    podman build -t localhost/zcc-webhook-base:latest -f "$DOTS/containers/systemd/hermes/Containerfile.zcc-webhook" "$DOTS/containers/systemd/hermes/"

    if [ -f "$HOME/src/projects/pka-web/Containerfile" ]; then
        echo "==> Building localhost/pka-web:latest..."
        podman build -t localhost/pka-web:latest -f "$HOME/src/projects/pka-web/Containerfile" "$HOME/src/projects/pka-web"
    fi

    echo "==> Building localhost/searxng-relay:latest..."
    podman build -t localhost/searxng-relay:latest -f "$DOTS/containers/systemd/ai/Containerfile.searxng-relay" "$DOTS/containers/systemd/ai/"
    echo "==> All local container images built successfully."

# Stows Homelab Podman Quadlet container definitions to ~/.config/containers (Host only)
stow:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"
    DOTS="$(resolve_dots_dir)"
    echo "[ 🐳 Stowing Podman Quadlet containers... ]"
    mkdir -p "$HOME/.config/containers"
    stow -d "$DOTS" -R --ignore=".DS_Store" --ignore='^\._' -t "$HOME/.config/containers" containers
    systemctl --user daemon-reload
    echo "✅ Containers stowed and systemd daemon reloaded!"

# Unstows Homelab Podman Quadlet container definitions and reloads systemd
unstow:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"
    DOTS="$(resolve_dots_dir)"
    echo "[ 🧹 Unstowing Podman Quadlet containers... ]"
    if [ -d "$HOME/.config/containers" ]; then
      stow -d "$DOTS" -D --ignore=".DS_Store" --ignore='^\._' -t "$HOME/.config/containers" containers 2>/dev/null || true
      rm -rf "$HOME/.config/containers"
    fi
    systemctl --user daemon-reload
    echo "✅ Containers unstowed and systemd daemon reloaded!"
