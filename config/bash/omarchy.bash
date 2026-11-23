# ~/.config/bash/omarchy.bash — Omarchy-only shell integration
# No-op on non-Omarchy hosts; avoids sourcing Omarchy's full default/bash/rc
# so portable tools (starship, zoxide, fzf, inputrc, aliases) never run twice.

[ -r /usr/share/omarchy/default/bash/env-bootstrap ] || return 0

# Environment & PATH bootstrap (OMARCHY_PATH, mise wrappers/shims) — needed even for non-interactive shells
if [ -z "${_OMARCHY_ENV_BOOTSTRAPPED:-}" ]; then
  source /usr/share/omarchy/default/bash/env-bootstrap
fi

# Mirror /etc/profile.d/locale.sh for non-login SSH / herdr remote sessions
if [ -z "${LANG:-}" ]; then
  [ -r /etc/locale.conf ] && source /etc/locale.conf
  LANG="${LANG:-C.UTF-8}"
  export LANG LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY \
    LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT \
    LC_IDENTIFICATION
fi

# Stop here for non-interactive shells
[[ $- != *i* ]] && return 0

# Shell-scoped browser launcher (detached from terminal tree without breaking xdg-settings)
export BROWSER="${BROWSER:-omarchy-launch-browser}"

# Dynamic Tab completion for `omarchy` and hide individual `omarchy-*` commands
[ -r "$OMARCHY_PATH/default/bash/completions" ] && source "$OMARCHY_PATH/default/bash/completions"

# Omarchy-specific tool helpers
if command -v herdr &>/dev/null && [ -r "$OMARCHY_PATH/default/bash/fns/herdr" ]; then
  source "$OMARCHY_PATH/default/bash/fns/herdr"
fi

if command -v try &>/dev/null; then
  try() {
    unset -f try
    eval "$(SHELL=/bin/bash command try init ~/Work/tries)"
    try "$@"
  }
fi

# Omarchy-specific aliases
alias a='omarchy-agent --inline'
alias mup='MISE_MINIMUM_RELEASE_AGE=0 mise up'
