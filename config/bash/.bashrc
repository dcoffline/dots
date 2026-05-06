# .bashrc — The One True Config (BASH edition)

# Source UBlue globals ONLY on host
if [[ -z "$CONTAINER_ID" ]] && [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# Function to add to PATH only if it's not already there
add_to_path() {
  if [[ ":$PATH:" != *":$1:"* ]]; then
    PATH="$1:$PATH"
  fi
}

# Apply paths in REVERSE order of preference so the top priority ends up first
add_to_path "$HOME/.local/share/cargo/bin"
add_to_path "$HOME/.local/share/go/bin"
add_to_path "$HOME/.config/npm"
add_to_path "$HOME/.local/bin"
add_to_path "/home/linuxbrew/.linuxbrew/sbin"
add_to_path "/home/linuxbrew/.linuxbrew/bin"

export PATH

# ────── SHELL EXPORTS & ALIASES ──────
[ -f "$HOME/.config/bash/.shellenv" ] && source "$HOME/.config/bash/.shellenv"

# ────── CLI BLING & FUNCTIONS ──────
[ -f "$HOME/.config/bash/.functions" ] && source "$HOME/.config/bash/.functions"

[ "$(command -v starship)" ] && eval "$(starship init bash)"
[ "$(command -v zoxide)" ] && eval "$(zoxide init bash)"
[ "$(command -v fzf)" ] && source <(fzf --bash)

# Atuin Setup (Host and Container Safe)
if [ "$(command -v atuin)" ]; then
  # Configure Atuin hooks in container
  if [[ -n "$CONTAINER_ID" ]]; then
    unset ATUIN_SESSION
    unset ATUIN_HISTORY_ID
  fi

  # bash-preexec for Atuin (host OR container)
  if [[ -z "$__bp_imported" ]]; then
    # Clear PS0 to avoid leakage from previous corrupted state
    unset PS0
    if [ -f /usr/share/bash-preexec/bash-preexec.sh ]; then
      source /usr/share/bash-preexec/bash-preexec.sh
    elif [ -f "$HOME/.local/share/bash-preexec.sh" ]; then
      source "$HOME/.local/share/bash-preexec.sh"
    fi
    # Force DEBUG trap mode to avoid PS0 issues on Bash 5.3+
    __bp_hook_preexec_proc=__bp_hook_preexec_into_debug
  fi

  eval "$(atuin init bash)"
fi
