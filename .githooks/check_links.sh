#!/usr/bin/env bash
# Stow-link integrity check for the dots repo.
# Single implementation shared by two triggers (do not fork this logic):
#   - `just check-links` (interactive guard)
#   - .githooks/pre-push step (c) (publish gate)
# Healthy = every tracked dots file resolves (readlink -f) into the repo from
# its $HOME stow location via a RELATIVE symlink. Catches symlink-destroying
# atomic-rename edits (2026-10-14 + 2026-10-15 incidents: editing through
# ~/.justfile replaced the symlink with a regular file and the repo copy
# silently diverged) AND absolute stow links (2026-10-16: stow 2.3.1 skips
# absolute links during unstow, then aborts restow with "existing target is
# not owned by stow" — took down `update all`).
set -euo pipefail

# DOTS resolution order: env override -> git CWD -> house default.
# Env-first lets the pre-push hook pin it to the repo being pushed. It is
# deliberately NEVER derived from the justfile path: when the stow link is
# destroyed, that path IS the broken file (naive derivation false-greens
# with "OK: 0 files" — fault-injection verified 2026-10-15).
if [ -z "${DOTS:-}" ]; then
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  DOTS="${top:-$HOME/src/dots}"
fi
if ! git -C "$DOTS" rev-parse --git-dir >/dev/null 2>&1; then
  echo "check-links: $DOTS is not a git repo — set DOTS or restore ~/src/dots" >&2
  exit 1
fi

failed=0; abs=0; checked=0
is_mac="$(uname -s)"
while IFS= read -r path; do
  pkg="${path%%/*}"; rest="${path#*/}"
  case "$pkg" in
    home)    base="$HOME" ;;
    config)  base="$HOME/.config" ;;
    local)   base="$HOME/.local" ;;
    Library) base="$HOME/Library" ;;
    *) continue ;;
  esac
  # Exemptions: home/.secrets is the git-crypt reinstall backup (the live
  # ~/.secrets is authoritative, never stowed); Library/ is macOS-only;
  # the antigravitycli session link deliberately points outside dots.
  case "$path" in
    home/.secrets) continue ;;
    Library/*) [ "$is_mac" = "Darwin" ] || continue ;;
    config/environment.d/.antigravitycli/*) continue ;;
  esac
  t="$base/$rest"
  checked=$((checked+1))
  # Healthy = exists AND resolves into the repo. NOT "-L required": files
  # under folded directory symlinks resolve fine without being links.
  # readlink -f alone false-greens on ABSOLUTE links (2026-10-15 'update
  # all' outage): they resolve fine here but stow 2.3.1 cannot restow them,
  # so require stow-style relative links whenever the live node is a link.
  if [ -e "$t" ] && [ "$(readlink -f "$t" 2>/dev/null)" = "$DOTS/$path" ]; then
    if [ -L "$t" ]; then
      lt="$(readlink "$t")"
      case "$lt" in
        /*) echo "ABSOLUTE LINK (stow-hostile, must be relative): $t -> $lt"
            abs=$((abs+1)); failed=1 ;;
      esac
    fi
    continue
  fi
  if [ -L "$t" ]; then
    echo "BROKEN LINK: $t -> $(readlink "$t")"
  elif [ -e "$t" ]; then
    echo "REGULAR FILE (link destroyed): $t"
  else
    echo "MISSING: $t (dots/$path not stowed)"
  fi
  failed=1
done < <(git -C "$DOTS" ls-files home/ config/ local/ Library/)

if [ "$failed" -eq 0 ]; then
  echo "OK: $checked tracked dots files all resolve into $DOTS (relative links)"
  exit 0
fi
echo "Re-stow: stow -R -t \"$HOME\" home; stow -R -t \"$HOME/.config\" config; stow -R -t \"$HOME/.local\" local; stow -R -t \"$HOME/Library\" Library" >&2
if [ "$abs" -gt 0 ]; then
  echo "Absolute-link fix — from the directory that holds the link, run:" >&2
  echo "  ln -sfn \"\$(realpath --relative-to=. $DOTS/<pkg>/<path>)\" <linkname>" >&2
fi
exit 1
