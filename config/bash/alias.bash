# .aliases - Universal Shell Aliases

# ────── CONTAINER ALIASES ──────

if [ -f /run/.containerenv ]; then

  # Distrobox
  alias dex='distrobox-export --app'
  alias deb='distrobox-export --export-path $HOME/.local/bin --bin'

  # Set Podman socket path for Container
  export DOCKER_HOST="unix:///run/host/run/user/$(id -u)/podman/podman.sock"
    
  # Rclone (Punching out to the host)
  alias dhe='distrobox-host-exec'
  alias rmount='dhe $HOME/.local/bin/rclone-mount'
  alias rlsmount='dhe mount | grep rclone || echo "No rclone mounts active"'
  alias rumount='dhe $HOME/.local/bin/rclone-unmount && rlsmount'
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

else

# ────── HOST ALIASES ──────
   
  # Distrobox
  alias dea='distrobox enter arch'
  alias dear='distrobox enter arch -e'
  alias def='distrobox enter fedora'
  alias defr='distrobox enter fedora -e'
  alias deu='distrobox enter ubuntu'
  alias deur='distrobox enter ubuntu -e'
  
  # Set Podman socket path for Container
  export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"
  
  # Rclone (Native)
  alias rmount='$HOME/.local/bin/rclone-mount'
  alias rlsmount='mount | grep rclone || echo "No rclone mounts active"'
  alias rumount='$HOME/.local/bin/rclone-unmount && rlsmount'
  alias rremount='rumount; sleep 3; rmount'
    
  # System Utils (Native)
  alias jc='journalctl'
  alias susc='sudo systemctl'
  alias scu='systemctl --user'
  alias suscdr='sudo systemctl daemon-reload'
  alias scudr='systemctl --user daemon-reload'
  alias deb='ssh eric@100.120.205.70'
  alias follow='journalctl --user -fu'
  alias git='distrobox enter fedora -e git'
  alias ptrans='dconf write /org/gnome/Ptyxis/Profiles/***/opacity'
  
fi

# ────── GLOBAL ALIASES ──────

# Editor
alias vi=$EDITOR
alias nano=$EDITOR
alias svi='sudo $EDITOR'
alias snano='sudo $EDITOR'
alias ted='flatpak run org.gnome.TextEditor'

# System Utilities
alias gd=gdctl
alias yey=paru
alias bb=busybox
alias j=jotta-cli
alias ff=fastfetch
alias openports='ss -tulanp'
alias cid="echo $CONTAINER_ID"
alias groqlog="cat $GROQDIR/groq_debug.log"
alias rlog="tail $HOME/.config/rclone/rclone-mount.log"

if [ ! -f "$HOME/.cargo/bin/linutil" ]; then
  alias linutil='curl -fsSL https://christitus.com/linux | sh'
fi

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
alias vich='command -v'
alias la='eza -la --icons=auto --group-directories-first'

# List recently installed packages
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl" 

# Podman Tools
alias d2q='podlet generate container podman run'
alias podip="podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'"
alias podclean='podman container prune -f ; podman image prune -f ; podman network prune -f ; podman volume prune -f'

# Fix for Ptyxis/VTE terminal color query leaks
[[ $TERM == "xterm-256color" ]] && export TERM="vte-256color"
