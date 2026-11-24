#!/usr/bin/env bash
# Fortress Maintenance Protocol (Updates, Syncs, Dotfiles)
# Pass --containers (or -c) to include Podman Quadlet symlinks (~/.config/containers)

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ "$(uname -s)" != "Darwin" ]] && { [ -f /run/.containerenv ] || ! command -v omarchy-update >/dev/null 2>&1; }; then
  sudo -v
  # Sudo keep-alive
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi
set -e

SHELLINI="config/dconf-backups/gnome-shell.ini"
DOTS="$(resolve_dots_dir)"

# By default, containers are only included if explicitly requested via --containers
# or if we are on the primary container host 'bee'
INCLUDE_CONTAINERS=0
if [ "$(hostname)" = "bee" ]; then
  INCLUDE_CONTAINERS=1
fi
for arg in "$@"; do
  case "$arg" in
    --containers|-c|containers)
      INCLUDE_CONTAINERS=1
      ;;
    --no-containers)
      INCLUDE_CONTAINERS=0
      ;;
    *)
      echo "Unknown option: $arg (use --containers/-c or --no-containers)"
      exit 1
      ;;
  esac
done

STOW_CONFIG_ARGS=(--ignore=".DS_Store" --ignore='^\._')
# Repo local/share/<container>/ dirs are the source of truth for per-container
# .env files (git-crypt). Plain stow handles everything: existing live dirs
# get per-file links (only the .env/entrypoint link in, data untouched); a
# fresh machine gets whole-dir folds seeded from the repo. 2026-11-15: the
# old 11-name skip-list and its dynamic replacement were both removed -
# dry-run proved plain stow produces zero conflicts on bee. If update ever
# errors "cannot stow over existing target", a live file diverged from the
# repo: diff and commit the correct side (that error is the drift signal).
STOW_LOCAL_ARGS=(--ignore=".DS_Store" --ignore='^\._')

apply_container_links() {
  if [ "$INCLUDE_CONTAINERS" -eq 1 ]; then
    echo "[ 🐳 Stowing Podman container Quadlets... ]"
    mkdir -p "$HOME/.config/containers"
    stow -d "$DOTS" -R --ignore=".DS_Store" --ignore='^\._' -t "$HOME/.config/containers" containers
  else
    if [ -d "$HOME/.config/containers" ]; then
      stow -d "$DOTS" -D --ignore=".DS_Store" --ignore='^\._' -t "$HOME/.config/containers" containers 2>/dev/null || true
      rmdir "$HOME/.config/containers" 2>/dev/null || true
    fi
    if [ -L "$HOME/.config/containers" ] && [[ "$(readlink -f "$HOME/.config/containers" 2>/dev/null)" == "$DOTS/"* ]]; then
      rm -rf "$HOME/.config/containers"
    elif [ -L "$HOME/.config/containers/systemd" ] && [[ "$(readlink -f "$HOME/.config/containers/systemd" 2>/dev/null)" == "$DOTS/"* ]]; then
      rm -rf "$HOME/.config/containers/systemd"
    fi
  fi
}

if [ -f /run/.containerenv ]; then
  ENV_TYPE="container"
  echo "[ 🏗️  Container environment detected ]"
elif [ -f /run/ostree-booted ] || [[ "$(uname -s)" == "Darwin" ]]; then
  ENV_TYPE="immutable"
  echo "[ 🛡️  Immutable host detected ]"
elif command -v omarchy-update >/dev/null 2>&1; then
  ENV_TYPE="mutable"
  echo "[ 🏹 Omarchy host detected ]"
else
  ENV_TYPE="mutable"
  echo "[ 💻 Standard mutable host detected ]"
fi

cd "$DOTS" || exit 1
[ -f ./config/environment.d/envvars.conf ] && source ./config/environment.d/envvars.conf
[ -f ./config/bash/function.bash ] && source ./config/bash/function.bash
[ -f ./config/bash/os.bash ] && source ./config/bash/os.bash
DOTS="$(resolve_dots_dir)"
export DOTS

# Gate: live stow tree must resolve into the repo (relative links) before
# `update` touches it. Absolute links break stow -R (2026-10-16 outage:
# stow 2.3.1 skips absolute links on unstow then aborts with "not owned
# by stow"); atomic-rename edits destroy stow links silently. Catch both.
bash "$DOTS/.githooks/check_links.sh" --pre-stow
export INCLUDE_CONTAINERS

echo "[ Syncing with GitHub... ]"
git pull --rebase --autostash -X ours || echo "⚠️ Warning: Git pull failed. Continuing..."
gitup "update ${NOW:-}" || echo "⚠️ Warning: Git sync failed. Continuing..."

echo "[ Initiating Fortress Maintenance Protocol... ]"

if [ "$ENV_TYPE" = "container" ]; then
  echo "[ Updating Container binaries... ]"
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf upgrade -y --skip-unavailable
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get upgrade -y
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Syu --noconfirm
  fi

  echo "[ Syncing Host State... ]"
  distrobox-host-exec sh -c "cd '$DOTS' && /home/linuxbrew/.linuxbrew/bin/brew bundle dump --force && sed -i '/^flatpak/d' Brewfile"
  if distrobox-host-exec printenv XDG_CURRENT_DESKTOP 2>/dev/null | grep -qi gnome; then
    distrobox-host-exec dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
    sed -i -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
    sed -i -E '/^(playback-history|history|timer-last-trigger)=/d' "$DOTS/$SHELLINI"
  fi

  echo "[ Applying Dotfile Updates... ]"
  mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin" "$HOME/.local/share/gnome-shell/extensions"
  stow -R --ignore=".DS_Store" --ignore='^\._' -t "$HOME" home
  stow -R "${STOW_CONFIG_ARGS[@]}" -t "$HOME/.config" config
  apply_container_links
  stow -R "${STOW_LOCAL_ARGS[@]}" -t "$HOME/.local" local
  bash "$DOTS/.githooks/check_links.sh"

  echo "[ Backing up to GitHub... ]"
  git add Brewfile "$SHELLINI"
  git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
  git pull --rebase --autostash -X ours && git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."

  echo "[ Starting Immutable Host Update... ]"
  distrobox-host-exec sudo ujust update

elif [ "$ENV_TYPE" = "immutable" ]; then
  if [ "${IS_MAC:-0}" -eq 1 ]; then
    echo "[ Updating macOS packages... ]"
    if command -v brew >/dev/null 2>&1; then
      export HOMEBREW_NO_ASK=1
      brew update || echo "⚠️ Warning: Homebrew update failed. Continuing..."
      brew upgrade -y || echo "⚠️ Warning: Homebrew upgrade reported errors. Continuing..."
    fi
    if command -v mas >/dev/null 2>&1; then
      mas upgrade || echo "⚠️ Warning: Mac App Store upgrade failed."
    fi
  fi

  echo "[ Syncing Host State... ]"
  brew bundle dump --force && sedi '/^flatpak/d' Brewfile || echo "⚠️ Warning: Homebrew dump failed."
  if command -v dconf >/dev/null 2>&1 && [[ "${XDG_CURRENT_DESKTOP:-}" =~ "GNOME" ]]; then
    dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
    sedi -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
    sedi -E '/^(playback-history|history|timer-last-trigger)=/d' "$DOTS/$SHELLINI"
  fi

  echo "[ Applying Dotfile Updates... ]"
  stow -R --ignore=".DS_Store" --ignore='^\._' -t "$HOME" home
  stow -R "${STOW_CONFIG_ARGS[@]}" -t "$HOME/.config" config
  apply_container_links
  stow -R "${STOW_LOCAL_ARGS[@]}" -t "$HOME/.local" local
  if [ "${IS_MAC:-0}" -eq 1 ]; then
    if [ -f "$HOME/Library/LaunchAgents/sh.brew.sunshine.plist" ] && [ ! -L "$HOME/Library/LaunchAgents/sh.brew.sunshine.plist" ]; then
      echo "Restoring symlink for sh.brew.sunshine.plist (overwritten by Homebrew)..."
      rm -f "$HOME/Library/LaunchAgents/sh.brew.sunshine.plist"
    fi
    stow -R --ignore=".DS_Store" --ignore='^\._' -t "$HOME/Library" Library
  fi
  bash "$DOTS/.githooks/check_links.sh"

  echo "[ Backing up to GitHub... ]"
  if [ "${OS_TYPE:-}" = "mac" ]; then
    git add Brewfile
    git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
    git pull --rebase --autostash -X ours && git push origin main || echo "⚠️ Warning: Git push failed."
  elif [ "${OS_TYPE:-}" = "linux" ]; then
    CONTAINER_NAME=$(distrobox list --no-color 2>/dev/null | awk -F '|' 'NR>1 {gsub(/[ \t]+/, "", $2); print $2}' | head -n 1)
    if [ -n "$CONTAINER_NAME" ]; then
      distrobox enter "$CONTAINER_NAME" -- sh -c "cd '$DOTS' && git add Brewfile '$SHELLINI' && git commit -m \"System snapshot: $(date +'%Y-%m-%d')\" || true && git pull --rebase --autostash -X ours && git push origin main"
    else
      git add Brewfile "$SHELLINI"
      git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
      git pull --rebase --autostash -X ours && git push origin main || echo "⚠️ Warning: Git push failed."
    fi
    echo "[ Starting Immutable Host Update... ]"
    sudo ujust update
  fi

elif command -v omarchy-update >/dev/null 2>&1; then
  echo "[ Syncing Dotfiles... ]"
  stow -R --ignore='.DS_Store' --ignore='^\._' -t "$HOME" home
  stow -R "${STOW_LOCAL_ARGS[@]}" -t "$HOME/.local" local
  stow -R "${STOW_CONFIG_ARGS[@]}" -t "$HOME/.config" config
  apply_container_links
  bash "$DOTS/.githooks/check_links.sh"

  echo "[ Backing up to GitHub... ]"
  git pull --rebase --autostash -X ours && git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."

  echo "[ Starting Omarchy Update... ]"
  omarchy update

else
  echo "[ Updating System binaries... ]"
  if command -v brew >/dev/null 2>&1; then brew update && brew upgrade; fi
  if command -v dnf >/dev/null 2>&1; then sudo dnf upgrade -y --skip-unavailable; fi
  if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get upgrade -y; fi
  if command -v pacman >/dev/null 2>&1; then sudo pacman -Syu; fi
  if command -v npm >/dev/null 2>&1; then sudo npm update -g; fi

  echo "[ Syncing Host State & Dotfiles... ]"
  if command -v dconf >/dev/null 2>&1 && [[ "${XDG_CURRENT_DESKTOP:-}" =~ "GNOME" ]]; then
    dconf dump /org/gnome/shell/ >"$DOTS/$SHELLINI"
    sedi -E "s/([a-zA-Z0-9_-]*api-key)=['\"][^'\"]*['\"]/\1=''/g" "$DOTS/$SHELLINI"
    sedi -E '/^(playback-history|history|timer-last-trigger)=/d' "$DOTS/$SHELLINI"
  fi
  if command -v brew >/dev/null 2>&1; then brew bundle dump --force && sedi '/^flatpak/d' Brewfile; fi

  stow -R --ignore='.DS_Store' --ignore='^\._' -t "$HOME" home
  stow -R "${STOW_LOCAL_ARGS[@]}" -t "$HOME/.local" local
  stow -R "${STOW_CONFIG_ARGS[@]}" -t "$HOME/.config" config
  apply_container_links
  if [ "${IS_MAC:-0}" -eq 1 ]; then
    if [ -f "$HOME/Library/LaunchAgents/sh.brew.sunshine.plist" ] && [ ! -L "$HOME/Library/LaunchAgents/sh.brew.sunshine.plist" ]; then
      echo "Restoring symlink for sh.brew.sunshine.plist (overwritten by Homebrew)..."
      rm -f "$HOME/Library/LaunchAgents/sh.brew.sunshine.plist"
    fi
    stow -R --ignore='.DS_Store' --ignore='^\._' -t "$HOME/Library" Library
  fi
  bash "$DOTS/.githooks/check_links.sh"

  git add "$SHELLINI" Brewfile
  git commit -m "System snapshot: $(date +'%Y-%m-%d')" || true
  git pull --rebase --autostash -X ours && git push origin main || echo "⚠️ Warning: Could not push updates to GitHub."
fi
echo "[ Fortress Maintenance Complete ]"
