# ~/.bash_profile
# Entry point for login shells (e.g., macOS terminal, SSH)
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"

# Added by Ghostex so tools installed in $HOME/.local/share/ghostex/tools/bin run in new terminals.
export PATH="$PATH:$HOME/.local/share/ghostex/tools/bin"


# Added by Antigravity CLI installer
export PATH="/home/eric/.local/bin:$PATH"
