#!/bin/bash

# The Fortress Uninstaller
set -e

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source OS and environment detection if available
[ -f "$SCRIPT_DIR/config/environment.d/envvars.conf" ] && set -a && source "$SCRIPT_DIR/config/environment.d/envvars.conf" && set +a
[ -f "$SCRIPT_DIR/config/bash/os.bash" ] && source "$SCRIPT_DIR/config/bash/os.bash"

echo "🛡️  Unwinding the Fortress (Uninstalling dotfiles)..."

# =========================================================
# HELPER FUNCTIONS FOR RESTORING BACKUPS
# =========================================================

# Helper: check if a target is a symlink pointing into the dotfiles repository
is_link_to_dots() {
  local target="$1"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(readlink -f "$target" 2>/dev/null || readlink "$target")"
    if [[ "$link_target" == "$SCRIPT_DIR"* ]]; then
      return 0
    fi
  fi
  return 1
}

# Helper: restore backup if .bak exists
restore_target() {
  local target="$1"
  if [ -e "${target}.bak" ] || [ -L "${target}.bak" ]; then
    echo "[ 🔄 Restoring backup: ${target}.bak -> $target ]"
    rm -rf "$target"
    mv "${target}.bak" "$target"
  fi
}

# Helper: recursively find and restore .bak files/directories for a package
restore_item_recursive() {
  local src="$1"
  local dst="$2"

  [ -e "$src" ] || return 0

  # If a backup for this item exists, restore it
  if [ -e "${dst}.bak" ] || [ -L "${dst}.bak" ]; then
    echo "[ 🔄 Restoring backup: ${dst}.bak -> $dst ]"
    rm -rf "$dst"
    mv "${dst}.bak" "$dst"
  elif [ -d "$src" ]; then
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

# =========================================================
# 1. REMOVE STOW SYMLINKS
# =========================================================
echo "[ 🧹 Removing symlinks with Stow... ]"
if command -v stow >/dev/null 2>&1; then
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME" home 2>/dev/null || true
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.local" local 2>/dev/null || true
  stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/.config" config 2>/dev/null || true
  if [ "${IS_MAC:-0}" -eq 1 ]; then
    stow -d "$SCRIPT_DIR" --ignore='.DS_Store' --ignore='^\._' -D -t "$HOME/Library" Library 2>/dev/null || true
  fi
fi

# Cleanup any lingering symlinks
cleanup_lingering_symlinks "home" "$HOME"
cleanup_lingering_symlinks "local" "$HOME/.local"
cleanup_lingering_symlinks "config" "$HOME/.config"
if [ "${IS_MAC:-0}" -eq 1 ]; then
  cleanup_lingering_symlinks "Library" "$HOME/Library"
fi

# =========================================================
# 2. RESTORE BACKUPS (.bak)
# =========================================================
echo "[ 📦 Restoring original backups (*.bak)... ]"
restore_package "home" "$HOME"
restore_package "local" "$HOME/.local"
restore_package "config" "$HOME/.config"
if [ "${IS_MAC:-0}" -eq 1 ]; then
  restore_package "Library" "$HOME/Library"
fi

# =========================================================
# 3. GNOME EXTENSION CLEANUP (IF APPLICABLE)
# =========================================================
if command -v gsettings >/dev/null 2>&1; then
  current_extensions=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
  if [[ "$current_extensions" == *"logomenu-fixed@dcoffline"* ]]; then
    echo "[ ⚙️  Disabling logomenu GNOME Shell extension... ]"
    new_extensions=$(echo "$current_extensions" | sed "s/'logomenu-fixed@dcoffline', //g; s/, 'logomenu-fixed@dcoffline'//g; s/'logomenu-fixed@dcoffline'//g")
    gsettings set org.gnome.shell enabled-extensions "$new_extensions" 2>/dev/null || true
  fi
fi

echo "✅ Fortress uninstalled cleanly and original environment restored!"
