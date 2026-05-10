# ~/.zshrc — The One True Config (Bazzite 2025 edition)
export ZSH="$HOME/.config/omz"
ZSH_CUSTOM="$ZSH/custom"
ZSH_CACHE_DIR="$ZSH/cache"
ZSH_THEME=nanotechx
DEFAULT_USER=eric
plugins=(themes web-search command-not-found copybuffer colored-man-pages)

# ────── OH-MY-ZSH ──────
source $ZSH/oh-my-zsh.sh

# ────── POST-OMZ TWEAKS ──────
# --------------------------------------------------------------------
# This is the "best practice" for adding context to OMZ themes.
# We redefine the 'prompt_context' function that themes use.
# This inserts the container ID *inside* the theme's formatting.
# 1. First, check if the theme even defined this function
if (( ${+functions[prompt_context]} )); then
# 2. If it did, store a reference to the *original* function
  functions[original_prompt_context]=${functions[prompt_context]}
# 3. Now, create our new function
  prompt_context() {
    if [ -n "$CONTAINER_ID" ]; then
# If we're in a container, add our info (styled cyan)
      echo -n "%F{cyan}  $CONTAINER_ID%f "
    fi
# Call the theme's original function (which prints user@host)
    original_prompt_context
  }
fi

if [[ -e /.dockerenv ]] ; then
    psvar[1]="@${(%):-%m} «Docker»"     # show hostname inside docker containers
elif [[ -e /run/.containerenv ]] ; then
    psvar[1]="@${(%):-%m} «Podman»"     # show hostname inside podman containers
fi

# ────── ZSH OPTIONS ──────
# Lines configured by zsh-newuser-install
setopt autocd extendedglob notify prompt_subst
setopt appendhistory extended_history hist_ignore_all_dups hist_ignore_space
unsetopt beep
bindkey -v

# The following lines were added by compinstall
zstyle :compinstall filename "$ZDOTDIR/.zshrc"
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
autoload -Uz compinit
compinit

# ────── COMMON SHELL CONFIG ──────
set -a
[ -f "$HOME/.config/environment.d/envvars.conf" ] && source "$HOME/.config/environment.d/envvars.conf"
set +a

# Load path configuration
[ -f "$HOME/.config/bash/path.bash" ] && source "$HOME/.config/bash/path.bash"

# Load aliases and functions
[ -f "$HOME/.config/bash/alias.bash" ] && source "$HOME/.config/bash/alias.bash"
unalias rm
unalias git
[ -f "$HOME/.config/bash/function.bash" ] && source "$HOME/.config/bash/function.bash"

# Shell-specific inits
[ "$(command -v atuin)" ] && eval "$(atuin init zsh)"
[ "$(command -v zoxide)" ] && eval "$(zoxide init zsh)"
[ "$(command -v starship)" ] && eval "$(starship init zsh)"


