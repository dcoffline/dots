# .alias - Universal Shell Aliases

# ────── CONTAINER ALIASES ──────

if [ "$ENV_TYPE" = "container" ]; then

  # Set Podman socket path for Container
  export DOCKER_HOST="unix:///run/host/run/user/$(id -u)/podman/podman.sock"

  # Distrobox
  alias dex='distrobox-export --app'
  alias deb='distrobox-export --export-path $HOME/.local/bin --bin'

  # Rclone (Punching out to the host)
  alias dhe='distrobox-host-exec'
  alias rmount="dhe just mount"
  alias rlsmount='dhe mount | grep rclone || echo "No rclone mounts active"'
  alias rumount="dhe just unmount"
  alias rcheck='dhe just check-mounts'
  alias rremount='dhe rumount; sleep 3; rmount'

  # System Utils (Punching out to the host)
  alias btop='dhe btop'
  alias htop='dhe htop'
  alias susc='dhe sudo systemctl'
  alias scu='dhe systemctl --user'
  alias scudr='dhe systemctl --user daemon-reload'
  alias jc='dhe journalctl'
  alias follow='dhe journalctl --user -fu'
  alias ptrans='dhe dconf write /org/gnome/Ptyxis/Profiles/***/opacity'
  alias brew='dhe /var/home/linuxbrew/.linuxbrew/bin/brew'

# ──────  HOST ALIASES ──────

else

  # Set Podman socket path
  export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"

  # Distrobox
  alias def='distrobox enter fedora'
  alias defr='distrobox enter fedora -e'
  alias dea='distrobox enter arch'
  alias dear='distrobox enter arch -e'
  alias deu='distrobox enter ubuntu'
  alias deur='distrobox enter ubuntu -e'

  # Rclone (Native)
  alias rlsmount='mount | grep rclone || echo "No rclone mounts active"'
  alias rumount='just unmount'
  alias rcheck='just check-mounts'
  alias rremount='rumount; sleep 3; rmount'
fi

# ────── GLOBAL ALIASES ──────

# Fix for Ptyxis/VTE terminal color query leaks
[[ $TERM == "xterm-256color" ]] && export TERM="vte-256color"

# List recently installed packages
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"

# Podman Tools
alias d2q='podlet generate container podman run'
alias podip="podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'"
alias podclean='podman container prune -f ; podman image prune -f ; podman network prune -f ; podman volume prune -f'

# Editor
alias vi=$EDITOR
alias nano=$EDITOR
alias svi='sudo $EDITOR'
alias ted='flatpak run org.gnome.TextEditor'

# System Utils (Native)
alias gd=gdctl
alias yey=paru
alias bb=busybox
alias j=jotta-cli
alias ff=fastfetch
alias sc='systemctl'
alias susc='sudo systemctl'
alias scu='systemctl --user'
alias suscdr='sudo systemctl daemon-reload'
alias scudr='systemctl --user daemon-reload'
alias jc='journalctl'
alias jcu="journalctl --user -xeu"
alias follow='journalctl --user -fu'
alias gsettings='/usr/bin/gsettings'
alias update='just update'
alias openports='ss -tulanp'
alias lzd='lazydocker'
alias cid="echo $CONTAINER_ID"
alias rlog="tail $HOME/.config/rclone/rclone-mount.log"
alias ptrans='dconf write /org/gnome/Ptyxis/Profiles/***/opacity'
alias nats='env -u GSETTINGS_BACKEND /usr/bin/gsettings set org.gnome.desktop.peripherals.mouse natural-scroll'

# File Management
alias cat=bat
alias cp='cp -i'
alias mv='mv -i'
alias rm='trash -v'
alias mkdir='mkdir -p'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias da='date "+%Y-%m-%d %A %T %Z"'
alias h='history | grep'
alias p='ps aux | grep'
alias mx='chmod a+x'
alias dots='cd $DOTS'
alias logs='cd $LOGS'
alias vich='command -v'
alias la='eza -la --icons=auto --group-directories-first'

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

# Chris Titus Linux Utilities
if [ ! -f "$HOME/.local/share/cargo/bin/linutil" ]; then
  alias linutil='curl -fsSL https://christitus.com/linux | sh'
fi
