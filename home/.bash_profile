# ~/.bash_profile
# Entry point for login shells (e.g., macOS terminal, SSH)
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"

# Hermes Agent command
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
