#!/usr/bin/env bash
# Installs CLI tools from $DOTS/Brewfile and $DOTS/install-pkg.sh on Omarchy via `omarchy pkg add`
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DRY_RUN=0
INCLUDE_AUR=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)
      DRY_RUN=1
      ;;
    --aur)
      INCLUDE_AUR=1
      ;;
    -h|--help)
      echo "Usage: just tools omarchy-cli [--dry-run|-n] [--aur]"
      echo "  --dry-run, -n  Preview resolved packages without installing"
      echo "  --aur          Also attempt to install non-repo leftovers via 'omarchy pkg aur add'"
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $arg (use --dry-run/-n or --aur)" >&2
      exit 1
      ;;
  esac
done

if ! command -v omarchy >/dev/null 2>&1 || ! command -v omarchy-pkg-add >/dev/null 2>&1; then
  echo "❌ Omarchy CLI ('omarchy pkg add') not found. This recipe is for Omarchy hosts." >&2
  exit 1
fi

DOTS="$(resolve_dots_dir)"
BREWFILE="$DOTS/Brewfile"
INSTALL_PKG="$DOTS/install-pkg.sh"

if [ ! -f "$BREWFILE" ] && [ ! -f "$INSTALL_PKG" ]; then
  echo "❌ Neither $BREWFILE nor $INSTALL_PKG was found." >&2
  exit 1
fi

# Homebrew/Cargo/NPM/install-pkg name -> Arch/Omarchy repo package name
declare -A PKG_MAP=(
  ["gh"]="github-cli"
  ["gnu-which"]="which"
  ["node"]="nodejs"
  ["pipx"]="python-pipx"
  ["sevenzip"]="7zip"
  ["fd-find"]="fd"
  ["yq"]="go-yq"
  ["android-platform-tools"]="android-tools"
  ["@google/gemini-cli"]="gemini-cli"
)

# Non-CLI libs, Homebrew-only tools, GUI/compositors, and services managed separately by Omarchy
declare -A SKIP_PKGS=(
  ["libtool"]=1
  ["glib"]=1
  ["automake"]=1
  ["avahi"]=1
  ["jpeg-turbo"]=1
  ["libtiff"]=1
  ["boost"]=1
  ["pipewire"]=1
  ["libayatana-appindicator"]=1
  ["libsm"]=1
  ["miniupnpc"]=1
  ["numactl"]=1
  ["pkgconf"]=1
  ["portaudio"]=1
  ["bbrew"]=1
  ["sunshine"]=1
  ["weston"]=1
  ["yazi-build"]=1
  ["yazi-cli"]=1
  ["yazi-fm"]=1
)

# Optional AUR name overrides when --aur is passed
declare -A AUR_MAP=(
  ["browsh"]="browsh-bin"
  ["linutil_tui"]="linutil-bin"
  ["shellcheck"]="shellcheck-bin"
)

# Index available synced repo packages and currently installed packages once
declare -A REPO_PKGS=()
while IFS= read -r p; do
  [ -n "$p" ] && REPO_PKGS["$p"]=1
done < <(pacman -Slq)

declare -A INSTALLED_PKGS=()
while IFS= read -r p; do
  [ -n "$p" ] && INSTALLED_PKGS["$p"]=1
done < <(pacman -Qq)

# Collect raw CLI tool names from Brewfile and install-pkg.sh
raw_pkgs=()

if [ -f "$BREWFILE" ]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
      pkg="${BASH_REMATCH[1]}"
      pkg="${pkg##*/}" # strip tap prefix (e.g. bjarneo/cliamp/cliamp -> cliamp)
      raw_pkgs+=("$pkg")
    elif [[ "$line" =~ ^cargo[[:space:]]+\"([^\"]+)\" ]]; then
      raw_pkgs+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^go[[:space:]]+\"([^\"]+)\" ]]; then
      pkg="${BASH_REMATCH[1]}"
      raw_pkgs+=("${pkg##*/}")
    elif [[ "$line" =~ ^npm[[:space:]]+\"([^\"]+)\" ]]; then
      raw_pkgs+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^cask[[:space:]]+\"android-platform-tools\" ]]; then
      raw_pkgs+=("android-platform-tools")
    fi
  done < "$BREWFILE"
fi

if [ -f "$INSTALL_PKG" ]; then
  # Extract ARCH_PACKAGES=(...) and CARGO_PACKAGES=(...) arrays from install-pkg.sh
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && raw_pkgs+=("$pkg")
  done < <(
    awk '
      /^[[:space:]]*(ARCH_PACKAGES|CARGO_PACKAGES)=\(/ { in_arr=1; next }
      in_arr && /\)/ { in_arr=0; next }
      in_arr {
        sub(/#.*/, "")
        for (i=1; i<=NF; i++) {
          gsub(/["'\'']/, "", $i)
          if ($i != "") print $i
        }
      }
    ' "$INSTALL_PKG"
  )
fi

# Normalize, deduplicate, and classify
declare -A SEEN=()
TO_INSTALL=()
ALREADY_INSTALLED=()
UNAVAILABLE=()

for raw in "${raw_pkgs[@]}"; do
  pkg="$raw"

  # Versioned Homebrew python formulas (e.g. python@3.12 -> python)
  if [[ "$pkg" == python@* ]]; then
    pkg="python"
  fi

  # Skip pure libraries / non-CLI entries
  if [[ -n "${SKIP_PKGS[$pkg]+x}" ]]; then
    continue
  fi

  # Map Brewfile/Cargo/NPM names to Arch package names
  if [[ -n "${PKG_MAP[$pkg]+x}" ]]; then
    pkg="${PKG_MAP[$pkg]}"
  fi

  # Avoid pacman conflicts with already-installed drop-in alternatives
  if [[ "$pkg" == "rust" && -n "${INSTALLED_PKGS[rustup]+x}" ]]; then
    continue
  elif [[ "$pkg" == "go-yq" && -n "${INSTALLED_PKGS[yq]+x}" ]]; then
    continue
  elif [[ "$pkg" == "tealdeer" && -n "${INSTALLED_PKGS[tldr]+x}" ]]; then
    continue
  elif [[ "$pkg" == "7zip" && -n "${INSTALLED_PKGS[p7zip]+x}" ]]; then
    continue
  fi

  # Deduplicate
  if [[ -n "${SEEN[$pkg]+x}" ]]; then
    continue
  fi
  SEEN["$pkg"]=1

  if [[ -n "${INSTALLED_PKGS[$pkg]+x}" ]]; then
    ALREADY_INSTALLED+=("$pkg")
  elif [[ -n "${REPO_PKGS[$pkg]+x}" ]]; then
    TO_INSTALL+=("$pkg")
  else
    UNAVAILABLE+=("$pkg")
  fi
done

# Sort arrays for readable output
if (( ${#TO_INSTALL[@]} > 0 )); then
  mapfile -t TO_INSTALL < <(printf '%s\n' "${TO_INSTALL[@]}" | sort)
fi
if (( ${#ALREADY_INSTALLED[@]} > 0 )); then
  mapfile -t ALREADY_INSTALLED < <(printf '%s\n' "${ALREADY_INSTALLED[@]}" | sort)
fi
if (( ${#UNAVAILABLE[@]} > 0 )); then
  mapfile -t UNAVAILABLE < <(printf '%s\n' "${UNAVAILABLE[@]}" | sort)
fi

echo "=== Omarchy CLI Tools (from Brewfile & install-pkg.sh) ==="
echo "  Already installed : ${#ALREADY_INSTALLED[@]}"
echo "  To install (repo) : ${#TO_INSTALL[@]}"
echo "  Not in repos      : ${#UNAVAILABLE[@]}"

if (( ${#TO_INSTALL[@]} > 0 )); then
  echo ""
  echo "📦 Arch/Omarchy repo packages to install:"
  printf '  %s\n' "${TO_INSTALL[@]}"
  if (( DRY_RUN )); then
    echo ""
    echo "[dry-run] Would run:"
    echo "  omarchy pkg add ${TO_INSTALL[*]}"
  else
    echo ""
    echo "[ Installing via 'omarchy pkg add'... ]"
    omarchy pkg add "${TO_INSTALL[@]}"
    echo "✅ Installed ${#TO_INSTALL[@]} CLI package(s) via omarchy pkg add."
  fi
else
  echo ""
  echo "✅ All available Arch/Omarchy repo CLI packages are already installed!"
fi

if (( ${#UNAVAILABLE[@]} > 0 )); then
  echo ""
  echo "ℹ️  Not available in synced Arch/Omarchy repos ($(uname -m)):"
  printf '  %s\n' "${UNAVAILABLE[@]}"

  if (( INCLUDE_AUR )); then
    AUR_PKGS=()
    for u in "${UNAVAILABLE[@]}"; do
      aur_name="${AUR_MAP[$u]:-$u}"
      if [[ -z "${INSTALLED_PKGS[$aur_name]+x}" ]]; then
        AUR_PKGS+=("$aur_name")
      fi
    done
    if (( ${#AUR_PKGS[@]} > 0 )); then
      if (( DRY_RUN )); then
        echo ""
        echo "[dry-run] Would run for AUR:"
        echo "  omarchy pkg aur add ${AUR_PKGS[*]}"
      else
        echo ""
        echo "[ Attempting AUR installs via 'omarchy pkg aur add'... ]"
        for aur_pkg in "${AUR_PKGS[@]}"; do
          omarchy pkg aur add "$aur_pkg" || echo "⚠️  Skipped AUR package '$aur_pkg' (unavailable or build failed)"
        done
      fi
    fi
  else
    echo "   Tip: re-run with --aur to try installing these via 'omarchy pkg aur add' (or install via cargo)."
  fi
fi
