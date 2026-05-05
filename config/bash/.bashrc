# .bashrc — The One True Config (BASH edition)

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# User specific environment
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

# ────── SHELL ENVIRONMENT ──────
[ -f "$HOME/.config/bash/.shellenv" ] && source "$HOME/.config/bash/.shellenv"

# ────── CLI BLING & FUNCTIONS ──────
[ -f "$HOME/.config/bash/.functions" ] && source "$HOME/.config/bash/.functions"

# Provide Bash-like hooks for Atuin if available on the host OS
[ -f /usr/share/bash-prexec ] && source /usr/share/bash-prexec

[ "$(command -v starship)" ] && eval "$(starship init bash)"
[ "$(command -v zoxide)" ] && eval "$(zoxide init bash)"
[ "$(command -v atuin)" ] && eval "$(atuin init bash)"
[ "$(command -v fzf)" ] && source <(fzf --bash)
