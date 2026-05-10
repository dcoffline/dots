# .bashrc — The One True Config (BASH edition)

HISTSIZE=10000
HISTTIMEFORMAT="%F %T "
HISTCONTROL=ignoreboth:erasedups
HISTFILE="$HOME/.config/bash/.histfile"

# Source UBlue globals ONLY on host
if [[ -z "$CONTAINER_ID" ]] && [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# ────── SHELL EXPORTS & ALIASES ──────
[ -f "$HOME/.config/bash/.aliases" ] && source "$HOME/.config/bash/.aliases"

# ────── CLI BLING & FUNCTIONS ──────
[ -f "$HOME/.config/bash/.functions" ] && source "$HOME/.config/bash/.functions"

# Clean duplicates out of the PATH
cleanpath

[ "$(command -v fzf)" ] && source <(fzf --bash)
[ "$(command -v zoxide)" ] && eval "$(zoxide init bash)"
[ "$(command -v starship)" ] && eval "$(starship init bash)"

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
