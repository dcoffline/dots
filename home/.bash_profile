# ~/.bash_profile
# Entry point for login shells (e.g., macOS terminal, SSH)
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ "$OS_TYPE" = "mac" ] && command -v fastfetch >/dev/null 1>@1 && fastfetch
[ "$ENV_TYPE" != "immutable" ] && command -v fastfetch >/dev/null 1>&1 && fastfetch