#!/bin/bash

# The Fortress Uninstaller
# Reverses install.sh: removes stow links into this repo, restores *.bak originals,
# and removes empty directories the installer creates.
# NOT reverted (installed system-wide, not tracked by stow): packages, Flatpak
# apps, Jottacloud CLI and its repo/GPG entries, Nerd Fonts, GNOME extensions and dconf.
set -e

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_REAL="$(readlink -f "$SCRIPT_DIR")"

# Source OS and environment detection if available
[ -f "$SCRIPT_DIR/config/environment.d/envvars.conf" ] && set -a && source "$SCRIPT_DIR/config/environment.d/envvars.conf" && set +a
[ -f "$SCRIPT_DIR/config/bash/os.bash" ] && source "$SCRIPT_DIR/config/bash/os.bash"

echo "🛡️  Unwinding the Fortress (Uninstalling dotfiles)..."

# =========================================================
# HELPER FUNCTIONS FOR RESTORING BACKUPS
# =========================================================

# Helper: check if a target is a symlink pointing into the dotfiles repository
# (works for dangling links; matches the same path aliases install.sh accepts)
is_link_to_dots() {
  local target="$1"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(readlink -f "$target" 2>/dev/null)" || return 1
    if [[ "$link_target" == "$SCRIPT_DIR"/* || "$link_target" == "$SCRIPT_DIR_REAL"/* ]]; then
      return 0
    fi
    if [[ "$link_target" == *"/src/dots/"* ]]; then
      return 0
    fi
  fi
  return 1
}

# Helper: restore <target>.bak -> <target>. Never deletes real user files:
# only a stow link into this repo (or nothing) may be replaced.
restore_target() {
  local target="$1"
  local backup="${target}.bak"
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    if [ -L "$target" ] && ! is_link_to_dots "$target"; then
      echo "[ ⚠️  Leaving $backup in place: $target is an unrelated symlink ]"
      return 0
    fi
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "[ ⚠️  Leaving $backup in place: $target exists and is not a link ]"
      return 0
    fi
    echo "[ 🔄 Restoring backup: $backup -> $target ]"
    rm -f "$target"
    mv "$backup" "$target"
  fi
}

# Helper: recursively find and restore .bak files/directories for a package
restore_item_recursive() {
  local src="$1"
  local dst="$2"

  [ -e "$src" ] || return 0

  # If a backup for this item exists, restore it
  if [ -e "${dst}.bak" ] || [ -L "${dst}.bak" ]; then
    restore_target "$dst"
  elif [ -d "$src" ] && [ -d "$dst" ] && [ ! -L "$dst" ]; then
    # If src is a directory, inspect its children for sub-backups
    for child in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$child" ] || continue
      local child_name="$(basename "$child")"
      [[ "$child_name" == ".DS_Store" || "$child_name" == "._*" || "$child_name" == "*" ]] && continue
      restore_item_recursive "$child" "$dst/$child_name"
    done
  fi
}

# Restore backed-up files and directories for a stow package
restore_package() {
  local pkg_name="$1"
  local target_base="$2"
  local pkg_dir="$SCRIPT_DIR/$pkg_name"

  [ -d "$pkg_dir" ] || return 0

  for item in "$pkg_dir"/* "$pkg_dir"/.[!.]* "$pkg_dir"/..?*; do
    [ -e "$item" ] || continue
    local name="$(basename "$item")"
    [[ "$name" == ".DS_Store" || "$name" == "._*" || "$name" == "*" ]] && continue
    restore_item_recursive "$item" "$target_base/$name"
  done
}

# Helper: remove lingering symlinks that point to dotfiles repo
cleanup_lingering_symlinks() {
  local pkg_name="$1"
  local target_base="$2"
  local pkg_dir="$SCRIPT_DIR/$pkg_name"

  [ -d "$pkg_dir" ] || return 0

  for item in "$pkg_dir"/* "$pkg_dir"/.[!.]* "$pkg_dir"/..?*; do
    [ -e "$item" ] || continue
    local name="$(basename "$item")"
    [[ "$name" == ".DS_Store" || "$name" == "._*" || "$name" == "*" ]] && continue
    local target_item="$target_base/$name"

    if is_link_to_dots "$target_item"; then
      echo "[ 🗑️  Removing lingering symlink: $target_item ]"
      rm -f "$target_item"
    fi
  done
}

# Helper: rmdir directories install.sh created, deepest first; only succeeds if empty
remove_empty_dirs() {
  local d
  for d in "$@"; do
    if [ -d "$d" ] && [ ! -L "$d" ]; then
      rmdir "$d" 2>/dev/null && echo "[ 🗑️  Removed empty directory: $d ]" || true
    fi
  done
}

# =========================================================
# 1. REMOVE STOW SYMLINKS
# =========================================================
echo "[ 🧹 Removing symlinks with Stow... ]"
if command -v stow >/dev/null 2>&1; then
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME" home 2>/dev/null || true
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.local" local 2>/dev/null || true
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.config" config 2>/dev/null || true
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.config/containers" containers 2>/dev/null || true
  if [ "${IS_MAC:-0}" -eq 1 ]; then
    stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/Library" Library 2>/dev/null || true
  fi
fi

# Cleanup any lingering symlinks
cleanup_lingering_symlinks "home" "$HOME"
cleanup_lingering_symlinks "local" "$HOME/.local"
cleanup_lingering_symlinks "config" "$HOME/.config"
cleanup_lingering_symlinks "containers" "$HOME/.config/containers"
if [ -d "$HOME/.config/containers" ]; then
  rmdir "$HOME/.config/containers" 2>/dev/null || true
fi
if [ "${IS_MAC:-0}" -eq 1 ]; then
  cleanup_lingering_symlinks "Library" "$HOME/Library"

  # Legacy cleanup: voxtype was removed from the repo; older installs left a link
  # (and possibly a .bak) here. Also clears ghostty links from even older installs.
  APPSUP="$HOME/Library/Application Support"
  for link in "$APPSUP/voxtype/config.toml" "$APPSUP/com.mitchellh.ghostty/config"; do
    if is_link_to_dots "$link"; then
      echo "[ 🗑️  Removing lingering symlink: $link ]"
      rm -f "$link"
    fi
  done
  restore_target "$APPSUP/voxtype/config.toml"
  remove_empty_dirs "$APPSUP/voxtype" "$APPSUP/com.mitchellh.ghostty"
fi

# =========================================================
# 2. RESTORE BACKUPS (.bak)
# =========================================================
echo "[ 📦 Restoring original backups (*.bak)... ]"
restore_package "home" "$HOME"
restore_package "local" "$HOME/.local"
restore_package "config" "$HOME/.config"
restore_package "containers" "$HOME/.config/containers"
if [ "${IS_MAC:-0}" -eq 1 ]; then
  restore_package "Library" "$HOME/Library"
fi

# =========================================================
# 3. REMOVE DIRECTORIES INSTALL.SH CREATED (only if now empty)
# =========================================================
remove_empty_dirs \
  "$HOME/.local/share/gnome-shell/extensions" \
  "$HOME/.local/share/gnome-shell" \
  "$HOME/.local/share" \
  "$HOME/.config/systemd/user" \
  "$HOME/.config/systemd" \
  "$HOME/.config/rclone" \
  "$HOME/.local/lib" \
  "$HOME/.local/bin"

echo "✅ Fortress links removed and original backups restored."
echo "   Not reverted: installed packages, Flatpaks, Jottacloud CLI, Nerd Fonts,"
echo "   GNOME extensions/dconf, and system repo/GPG entries. Remove those manually if wanted."
