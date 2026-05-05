# .bashrc for $HOME directory

# Source the actual config in .config/bash
if [ -f "$HOME/.config/bash/.bashrc" ]; then
    source "$HOME/.config/bash/.bashrc"
fi
### bling.sh source start
test -f /usr/share/bazzite-cli/bling.sh && source /usr/share/bazzite-cli/bling.sh
### bling.sh source end
