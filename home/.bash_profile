# ~/.bash_profile

# Read systemd environment variables and export them
# (Useful for TTY or SSH sessions that bypass the graphical login)
if [ -f "$HOME/.config/environment.d/envvars.conf" ]; then
  set -a
  source "$HOME/.config/environment.d/envvars.conf"
  set +a
fi

# Function to add to PATH only if it's not already there
add_to_path() {
  if [[ ":$PATH:" != *":$1:"* ]]; then
    PATH="$1:$PATH"
  fi
}

# Apply paths in REVERSE order of preference so the top priority ends up first
add_to_path "$HOME/.local/share/go/bin"
add_to_path "$HOME/.config/npm"
add_to_path "$HOME/.cargo/bin"
add_to_path "$HOME/.local/bin"
# add_to_path "/home/linuxbrew/.linuxbrew/sbin"
# add_to_path "/home/linuxbrew/.linuxbrew/bin"

export PATH

# Load interactive Bash configurations
if [ -f "$HOME/.bashrc" ]; then
  source "$HOME/.bashrc"
fi
