# .bashrc — The One True Config (BASH edition)

# ────── NON-INTERACTIVE-SAFE ENVIRONMENT ──────
# Omarchy env bootstrap (no-op on non-Omarchy hosts; handles non-interactive env + interactive extras)
[ -f "$HOME/.config/bash/omarchy.bash" ] && source "$HOME/.config/bash/omarchy.bash"

# OS / container detection
[ -f "$HOME/.config/bash/os.bash" ] && source "$HOME/.config/bash/os.bash"

# Load environment variables
set -a
[ -f "$HOME/.config/environment.d/envvars.conf" ] &&
  source "$HOME/.config/environment.d/envvars.conf"
set +a
[ -n "${EDITOR:-}" ] && export SUDO_EDITOR="$EDITOR"

# Load functions (provides cleanpath for path.bash)
[ -f "$HOME/.config/bash/function.bash" ] && source "$HOME/.config/bash/function.bash"

# Load path configuration (OS-aware)
[ -f "$HOME/.config/bash/path.bash" ] && source "$HOME/.config/bash/path.bash"

# ────── INTERACTIVE GUARD ──────
[[ $- != *i* ]] && return

# ────── INTERACTIVE HYGIENE ──────
export GPG_TTY=$(tty 2>/dev/null)

# Clear 32-bit Steam extest preload if terminal inherited Steam's environment
if [[ "${LD_PRELOAD:-}" == *"/usr/lib/extest/libextest.so"* ]]; then
  unset LD_PRELOAD
fi

# Bat-colored man pages
if command -v bat &>/dev/null; then
  export BAT_THEME=ansi
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# ────── BASH SETTINGS ──────
shopt -s histappend
HISTSIZE=32768
HISTFILESIZE=32768
HISTTIMEFORMAT="%F %T "
HISTCONTROL=ignoreboth:erasedups
HISTFILE="$HOME/.config/bash/.histfile"

# Disable command hashing so mise / PATH switches take effect immediately
set +h

# Readline bindings (prefix history search, colored menu completion)
[ -f "$HOME/.config/bash/inputrc.bash" ] && bind -f "$HOME/.config/bash/inputrc.bash"

# Lazy-load bash-completion on first Tab when not already loaded
if [[ -z "${BASH_COMPLETION_VERSINFO:-}" ]]; then
  _bash_completion_file=""
  for _bc in /usr/share/bash-completion/bash_completion /opt/homebrew/etc/profile.d/bash_completion.sh; do
    if [[ -f "$_bc" ]]; then
      _bash_completion_file="$_bc"
      break
    fi
  done
  if [[ -n "$_bash_completion_file" ]]; then
    _lazy_bash_completion() {
      complete -r -D 2>/dev/null || true
      unset -f _lazy_bash_completion
      if [[ -f "$_bash_completion_file" ]]; then
        source "$_bash_completion_file"
        if declare -F _completion_loader >/dev/null; then
          _completion_loader "$1"
        fi
        return 124
      fi
    }
    complete -D -F _lazy_bash_completion
  fi
  unset _bc
fi

# Source system-wide bashrc on non-container Fedora/Bazzite Linux hosts
[[ "${IS_LINUX:-0}" -eq 1 && -z "${CONTAINER_ID:-}" && -f /etc/bashrc ]] && . /etc/bashrc

# Load aliases
[ -f "$HOME/.config/bash/alias.bash" ] && source "$HOME/.config/bash/alias.bash"

# ────── CLI TOOLS ──────
# Mise version manager
if command -v mise &>/dev/null; then
  eval "$(mise activate bash)"
  declare -F cleanpath &>/dev/null && cleanpath
fi

# Stat-cached init helper for starship & zoxide (GNU + macOS BSD stat compatible)
_source_cached_init() {
  local name="$1" bin="$2" stamp="$3"
  shift 3
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/bash"
  local cache="$cache_dir/$name.bash"
  local header="# cached-init:$bin:$stamp"
  local first=""

  if [[ -n $stamp && -s $cache ]]; then
    IFS= read -r first <"$cache" 2>/dev/null || true
    if [[ $first == "$header" ]]; then
      source "$cache"
      return
    fi
  fi

  local output
  output=$("$bin" "$@" 2>/dev/null) || return
  [[ -n $output ]] || return

  if [[ -n $stamp ]] && mkdir -p "$cache_dir" 2>/dev/null; then
    local tmp="$cache.$$"
    if printf '%s\n%s\n' "$header" "$output" >"$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null; then
      source "$cache"
      return
    fi
    rm -f "$tmp"
  fi

  eval "$output"
}

_init_bins=()
_init_starship=""
_init_zoxide=""
if [[ ${TERM:-} != "dumb" ]]; then
  _init_starship=$(type -P starship) && _init_bins+=("$_init_starship")
fi
_init_zoxide=$(type -P zoxide) && _init_bins+=("$_init_zoxide")

if (( ${#_init_bins[@]} > 0 )); then
  _init_stamps=()
  if [ "${IS_MAC:-0}" -eq 1 ]; then
    while IFS= read -r _s; do _init_stamps+=("$_s"); done < <(stat -Lf '%d:%i:%z:%m' "${_init_bins[@]}" 2>/dev/null)
  else
    while IFS= read -r _s; do _init_stamps+=("$_s"); done < <(stat -Lc '%d:%i:%s:%Y' "${_init_bins[@]}" 2>/dev/null)
  fi
  _stamp_idx=0
  if [[ -n $_init_starship ]]; then
    _source_cached_init starship "$_init_starship" "${_init_stamps[$_stamp_idx]:-}" init bash --print-full-init
    (( _stamp_idx++ ))
  fi
  if [[ -n $_init_zoxide ]]; then
    _source_cached_init zoxide "$_init_zoxide" "${_init_stamps[$_stamp_idx]:-}" init bash
  fi
fi
unset _init_bins _init_stamps _stamp_idx _init_starship _init_zoxide _s
unset -f _source_cached_init

# Fast fzf (key-bindings only when available to avoid ~25ms completion re-wrapping)
if command -v fzf &>/dev/null; then
  if [[ -f /usr/share/fzf/key-bindings.bash ]]; then
    source /usr/share/fzf/key-bindings.bash
  elif [[ -f /usr/share/fzf/shell/key-bindings.bash ]]; then
    source /usr/share/fzf/shell/key-bindings.bash
  elif [[ -f /opt/homebrew/opt/fzf/shell/key-bindings.bash ]]; then
    source /opt/homebrew/opt/fzf/shell/key-bindings.bash
  elif [[ -f /home/linuxbrew/.linuxbrew/opt/fzf/shell/key-bindings.bash ]]; then
    source /home/linuxbrew/.linuxbrew/opt/fzf/shell/key-bindings.bash
  else
    source <(fzf --bash)
  fi
fi

# Atuin Setup (Host and Container Safe)
if command -v atuin &>/dev/null; then
  # Configure Atuin hooks in container
  if [[ -n "${CONTAINER_ID:-}" ]]; then
    unset ATUIN_SESSION
    unset ATUIN_HISTORY_ID
  fi

  # bash-preexec for Atuin (host OR container)
  if [[ -z "${__bp_imported:-}" ]]; then
    # Clear PS0 to avoid leakage from previous corrupted state
    unset PS0
    if [ -f /usr/share/bash-preexec/bash-preexec.sh ]; then
      source /usr/share/bash-preexec/bash-preexec.sh
    elif [ -f "$HOME/.local/share/bash-preexec.sh" ]; then
      source "$HOME/.local/share/bash-preexec.sh"
    fi
    # Force DEBUG trap mode to avoid PS0 issues on Bash 5.3+
    __bp_hook_preexec_proc=__bp_hook_preexec_into_debug
  fi

  eval "$(atuin init bash)"
fi

### bling.sh source start
test -f /usr/share/bazzite-cli/bling.sh && source /usr/share/bazzite-cli/bling.sh
### bling.sh source end
