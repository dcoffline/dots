# Homebrew shellenv (ARM64 macOS)
eval "$(/opt/homebrew/bin/brew shellenv)"

# MacPorts PATH (from your saved file)
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

# Additional PATH for local bins and Cargo (for Rust tools like starship/yazi)
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
