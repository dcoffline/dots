# .bashrc for $HOME directory

# Source the actual config in .config/bash
if [ -f "$HOME/.config/bash/.bashrc" ]; then
  source "$HOME/.config/bash/.bashrc"
fi
. "/var/home/eric/.local/share/cargo/env"
