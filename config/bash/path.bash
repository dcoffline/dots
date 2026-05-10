# Path management for Bash

# Add to path only if it exists and isn't already there
add_to_path() {
  local dir="$1"
  if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
    PATH="$dir:$PATH"
  fi
}

# ────── COMMON PATHS ──────
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.cargo/bin"

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
  # Linux Specifics
  add_to_path "$HOME/.config/npm"
  add_to_path "$HOME/.local/share/go/bin"
  
  # Linuxbrew if available
  if [ -d /home/linuxbrew/.linuxbrew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
fi

# ────── CLEANUP ──────
# Use cleanpath function from .functions if available
if command -v cleanpath >/dev/null; then
  cleanpath
fi

export PATH
