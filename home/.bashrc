# .bashrc — The One True Config (BASH edition)

# ────── MODULAR CORE ──────
[ -f "$HOME/.config/bash/os.bash" ] && source "$HOME/.config/bash/os.bash"

# Load environment variables
set -a
[ -f "$HOME/.config/environment.d/envvars.conf" ] &&
  source "$HOME/.config/environment.d/envvars.conf"
set +a

# Load functions (provides cleanpath)
[ -f "$HOME/.config/bash/function.bash" ] && source "$HOME/.config/bash/function.bash"

# Load path configuration (OS-aware)
[ -f "$HOME/.config/bash/path.bash" ] && source "$HOME/.config/bash/path.bash"

# Load aliases
[ -f "$HOME/.config/bash/alias.bash" ] && source "$HOME/.config/bash/alias.bash"

# ────── BASH SETTINGS ──────
HISTSIZE=10000
HISTTIMEFORMAT="%F %T "
HISTCONTROL=ignoreboth:erasedups
HISTFILE="$HOME/.config/bash/.histfile"

# Source system-wide bashrc on Linux host
[[ "$IS_LINUX" -eq 1 && -z "$CONTAINER_ID" && -f /etc/bashrc ]] && . /etc/bashrc

# ────── CLI TOOLS ──────
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


# Added by Antigravity CLI installer
export PATH="/var/home/eric/.local/bin:$PATH"
