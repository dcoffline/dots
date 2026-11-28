#!/bin/bash

# The Fortress Bootstrapper
set -e

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_REAL="$(readlink -f "$SCRIPT_DIR")"

# =========================================================
# PARSE CLI FLAGS
# =========================================================
INCLUDE_CONTAINERS=0
INCLUDE_OLLAMA=0
NO_APPS=0

for arg in "$@"; do
  case "$arg" in
  --containers | -c)
    INCLUDE_CONTAINERS=1
    ;;
  --ollama)
    INCLUDE_OLLAMA=1
    INCLUDE_CONTAINERS=1
    ;;
  --no-apps)
    NO_APPS=1
    ;;
  --help | -h)
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --containers   Include Podman Quadlet container symlinks (~/.config/containers)"
    echo "      --ollama       Include the ollama quadlet (GPU/iGPU hosts only; implies --containers)"
    echo "      --no-apps      Skip installing CLI tools, packages, and apps (only stow symlinks)"
    echo "  -h, --help         Show this help message"
    exit 0
    ;;
  *)
    echo "Unknown option: $arg"
    echo "Run '$(basename "$0") --help' for usage."
    exit 1
    ;;
  esac
done

# Export all environment variables sourced from configuration
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/share" "$HOME/.config/systemd/user"
set -a
[ -f "$SCRIPT_DIR/config/environment.d/envvars.conf" ] && source "$SCRIPT_DIR/config/environment.d/envvars.conf"
[ -f "$SCRIPT_DIR/config/bash/os.bash" ] && source "$SCRIPT_DIR/config/bash/os.bash"
set +a

# =========================================================
# ENVIRONMENT DETECTION
# =========================================================
if [ "$ENV_TYPE" == "container" ]; then
  echo "[ 🏗️  Container environment detected ]"
elif [ "${IS_MAC:-0}" -eq 1 ]; then
  echo "[ 🍏 macOS host detected ]"
elif [ "$ENV_TYPE" == "immutable" ]; then
  echo "[ 🛡️  Immutable host detected ]"
else
  echo "[ 💻 Standard mutable host detected ]"
fi

echo "🛡️  Bootstrapping the Fortress..."

# =========================================================
# 1. ENSURE STOW IS INSTALLED
# =========================================================
if ! command -v stow >/dev/null 2>&1; then
  echo "[ Stow not found. Installing... ]"
  if [ "$ENV_TYPE" == "immutable" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install stow
    else
      echo "Error: Homebrew is required on immutable systems."
      exit 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y stow
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y stow
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm stow
  else
    echo "Error: Could not install stow automatically."
    exit 1
  fi
fi

# =========================================================
# HELPER FUNCTIONS FOR BACKING UP EXISTING TARGETS
# =========================================================

# Helper: check if a target is a symlink pointing into the dotfiles repository
is_link_to_dots() {
  local target="$1"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(readlink -f "$target" 2>/dev/null || readlink "$target")"
    if [[ "$link_target" == "$SCRIPT_DIR"* || "$link_target" == "$SCRIPT_DIR_REAL"* ]]; then
      return 0
    fi
    # If link is relative, normalize and check
    if [[ "$link_target" != /* ]]; then
      local parent_dir
      parent_dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P || dirname "$target")"
      local combined="$parent_dir/$link_target"
      if [[ "$combined" == "$SCRIPT_DIR"* || "$combined" == "$SCRIPT_DIR_REAL"* || "$combined" == *"/src/dots/"* || "$combined" == *"/dots/"* ]]; then
        return 0
      fi
    fi
    # Same repo accessed via a different path prefix (e.g. /var/home vs /home)
    if [[ "$link_target" == *"/src/dots/"* || "$link_target" == *"/dots/"* ]]; then
      return 0
    fi
  fi
  return 1
}

# Helper: clean up dead/broken symlinks that point into this repository
prune_broken_dots_links() {
  local target_dir="$1"
  local max_depth="${2:-4}"
  [ -d "$target_dir" ] || return 0

  while IFS= read -r link; do
    [ -L "$link" ] || continue
    if [ ! -e "$link" ] && is_link_to_dots "$link"; then
      echo "[ 🧹 Pruning dead dotfiles symlink: $link ]"
      rm -f "$link"
    fi
  done < <(find "$target_dir" -maxdepth "$max_depth" -type l 2>/dev/null || true)
}

# Helper: check if a target is an external directory with dotfiles-managed symlinks (e.g. .env on 2T)
is_external_dir_with_dots_link() {
  local target="$1"
  if [ -L "$target" ] && [ -d "$target" ]; then
    if [ -e "$target/.env" ] && is_link_to_dots "$target/.env"; then
      return 0
    fi
  fi
  return 1
}

# Helper: recursively inspect and backup existing non-symlink files/directories
backup_item_recursive() {
  local src="$1"
  local dst="$2"

  [ -e "$src" ] || return 0

  # If dst exists and already links to our dots repo, skip
  if is_link_to_dots "$dst"; then
    return 0
  fi

  # If dst is an external directory with dots links (e.g., container data on 2T with stowed .env), skip
  if is_external_dir_with_dots_link "$dst"; then
    return 0
  fi

  # If both src and dst are directories (and dst is not a symlink), traverse down
  if [ -d "$src" ] && [ -d "$dst" ] && [ ! -L "$dst" ]; then
    for child in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$child" ] || continue
      local child_name="$(basename "$child")"
      [[ "$child_name" == ".DS_Store" || "$child_name" == "._*" || "$child_name" == "*" ]] && continue
      backup_item_recursive "$child" "$dst/$child_name"
    done
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    # dst is a real file or leaf directory that would conflict with stow
    echo "[ 📦 Backing up existing: $dst -> ${dst}.bak ]"
    rm -rf "${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
}

# Backup existing files and directories for a stow package
backup_package() {
  local pkg_name="$1"
  local target_base="$2"
  local pkg_dir="$SCRIPT_DIR/$pkg_name"

  [ -d "$pkg_dir" ] || return 0

  for item in "$pkg_dir"/* "$pkg_dir"/.[!.]* "$pkg_dir"/..?*; do
    [ -e "$item" ] || continue
    local name="$(basename "$item")"
    [[ "$name" == ".DS_Store" || "$name" == "._*" || "$name" == "*" ]] && continue
    backup_item_recursive "$item" "$target_base/$name"
  done
}

# =========================================================
# 2. PRUNE DEAD LINKS & BACKUP CONFLICTING TARGETS
# =========================================================
echo "[ Pruning dead dotfiles symlinks... ]"
prune_broken_dots_links "$HOME" 2
prune_broken_dots_links "$HOME/.local" 4
prune_broken_dots_links "$HOME/.config" 4
if [ "${IS_MAC:-0}" -eq 1 ]; then
  prune_broken_dots_links "$HOME/Library" 4
fi

echo "[ Checking for existing configurations to back up (*.bak)... ]"
backup_package "home" "$HOME"
backup_package "local" "$HOME/.local"
backup_package "config" "$HOME/.config"
if [ "$INCLUDE_CONTAINERS" -eq 1 ]; then
  backup_package "containers" "$HOME/.config/containers"
fi
if [ "${IS_MAC:-0}" -eq 1 ]; then
  backup_package "Library" "$HOME/Library"
fi

# =========================================================
# 3. APPLY DOTFILES WITH STOW
# =========================================================
echo "[ Applying dotfiles with Stow... ]"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/share" "$HOME/.config/rclone"
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME" home

# Collect any local/share directories that are symlinked to external storage (e.g. 2T SSD)
# so Stow does not attempt to clobber the external directory links with repository symlinks
local_stow_ignores=("--ignore=.DS_Store" "--ignore=^\._")
if [ -d "$SCRIPT_DIR/local/share" ]; then
  for d in "$SCRIPT_DIR/local/share"/*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    target="$HOME/.local/share/$name"
    if is_external_dir_with_dots_link "$target"; then
      local_stow_ignores+=("--ignore=^${name}$" "--ignore=${name}$")
    fi
  done
fi
stow -d "$SCRIPT_DIR" "${local_stow_ignores[@]}" -R -t "$HOME/.local" local

# SELinux: container-mounted .env files must be container_file_t (fresh checkouts
# get user_home_t, which blocks container reads even with :Z on the mount)
if command -v chcon >/dev/null 2>&1; then
  find "$SCRIPT_DIR/local/share" -name '.env' -exec chcon system_u:object_r:container_file_t:s0 {} \; 2>/dev/null
fi

# Apply config package
stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.config" config

# Podman Quadlet container symlinks (Host-only opt-in)
if [ "$INCLUDE_CONTAINERS" -eq 1 ]; then
  echo "[ 🐳 Including Podman container symlinks (--containers)... ]"
  mkdir -p "$HOME/.config/containers/systemd"
  # Sentinel keeps the target dir non-empty so stow tree-folds the package
  # (one big symlink) instead of laying per-file symlinks — tree-folding would
  # force later stow targets (ollama) to write inside the repo working tree.
  touch "$HOME/.config/containers/systemd/.keep"
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.config/containers" containers
  rm -f "$HOME/.config/containers/systemd/.keep"
  if [ "$INCLUDE_OLLAMA" -eq 1 ]; then
    echo "[ 🦙 Including ollama quadlet (--ollama)... ]"
    stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/.config/containers/systemd" ollama
  else
    echo "[ ⏭️  Skipping ollama quadlet (pass --ollama to include)... ]"
    stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.config/containers/systemd" ollama 2>/dev/null || true
  fi
else
  echo "[ ⏭️  Skipping Podman container symlinks (pass --containers to include)... ]"
  # Remove any previously stowed container symlinks pointing into this repo
  if [ -d "$HOME/.config/containers" ]; then
    stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.config/containers" containers 2>/dev/null || true
    rmdir "$HOME/.config/containers" 2>/dev/null || true
  fi
  if is_link_to_dots "$HOME/.config/containers"; then
    rm -rf "$HOME/.config/containers"
  fi
fi
if [ "${IS_MAC:-0}" -eq 1 ]; then
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -R -t "$HOME/Library" Library
fi

# =========================================================
# 4. RUN PACKAGE INSTALLER
# =========================================================
if [ "$NO_APPS" -eq 1 ]; then
  echo "[ ⏭️  Skipping package installer (--no-apps)... ]"
elif [ -f "$SCRIPT_DIR/install-pkg.sh" ]; then
  echo "[ Running package installer... ]"
  bash "$SCRIPT_DIR/install-pkg.sh"
fi

# =========================================================
# 5. GNOME SHELL EXTENSIONS (GNOME hosts only; no-op elsewhere)
# =========================================================
if [ "$NO_APPS" -eq 0 ] && [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] && command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -q "^org\.gnome\.shell$"; then
  echo "[ Configuring GNOME Shell extensions... ]"
  current_extensions=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
fi

echo "✅ Fortress bootstrap complete!"
