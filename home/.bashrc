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

[ "$(command -v starship)" ] && eval "$(starship init bash)"
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
fi

### bling.sh source start
# Check if bling has already been sourced so that we dont break atuin. https://github.com/atuinsh/atuin/issues/380#issuecomment-1594014644
[ "${BLING_SOURCED:-0}" -eq 1 ] && return
BLING_SOURCED=1

# ls aliases
if [ "$(command -v eza)" ]; then
  alias ll='eza -l --icons=auto --group-directories-first'
  alias l.='eza -d .*'
  alias ls='eza'
  alias l1='eza -1'
fi

# ugrep for grep
if [ "$(command -v ug)" ]; then
  alias grep='ug'
  alias egrep='ug -E'
  alias fgrep='ug -F'
  alias xzgrep='ug -z'
  alias xzegrep='ug -zE'
  alias xzfgrep='ug -zF'
fi

if [ "$(basename "$SHELL")" = "bash" ]; then
  #shellcheck disable=SC1091
  . /usr/share/bash-prexec
  [ "$(command -v atuin)" ] && eval "$(atuin init bash)"
  [ "$(command -v zoxide)" ] && eval "$(zoxide init bash)"
elif [ "$(basename "$SHELL")" = "zsh" ]; then
  [ "$(command -v atuin)" ] && eval "$(atuin init zsh)"
  [ "$(command -v zoxide)" ] && eval "$(zoxide init zsh)"
fi
