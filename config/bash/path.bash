# Path management for Bash

# Add to path only if it exists and isn't already there
add_to_path() {
  local dir="$1"
  if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
    PATH="$dir:$PATH"
  fi
}

# ────── OS SPECIFIC PATHS ──────
if [ "$IS_MAC" -eq 1 ]; then
  # Homebrew (ARM64 macOS)
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  # MacPorts
  add_to_path "/opt/local/sbin"
  add_to_path "/opt/local/bin"

elif [ "$IS_LINUX" -eq 1 ]; then
  # In containers (Distrobox / Toolbox), link host Linuxbrew if not already present
  if [ ! -e /home/linuxbrew ] && [ -d /run/host/home/linuxbrew ]; then
    sudo -n ln -s /run/host/home/linuxbrew /home/linuxbrew 2>/dev/null || true
  fi

  # Linuxbrew if available
  if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
fi

# ────── COMMON PATHS (take precedence over Homebrew) ──────
add_to_path "$HOME/.local/share/go/bin"
add_to_path "$HOME/.config/npm/bin"
add_to_path "$HOME/.local/share/cargo/bin"
add_to_path "$HOME/.local/bin"

# Keep mise command-wrappers first when present so mise account switches work
_mise_wrappers="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/command-wrappers/bin"
if [ -d "$_mise_wrappers" ] || [[ ":$PATH:" == *":$_mise_wrappers:"* ]]; then
  PATH="$_mise_wrappers:$PATH"
fi
unset _mise_wrappers

# ────── CLEANUP ──────
# Use cleanpath function from function.bash if available
cleanpath

export PATH
