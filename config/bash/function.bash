# ────── SHELL FUNCTIONS ──────

# Toggle Tablet control for S11
s11() {
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  if pgrep -f "scrcpy.*R52YA06N8FA" >/dev/null 2>&1; then
    echo "Disconnecting tablet..."
    pkill -9 -f "scrcpy.*R52YA06N8FA"
  else
    echo "Connecting tablet..."
    scrcpy --otg -s R52YA06N8FA >/dev/null 2>&1 &
    disown
  fi
}

# Portable in-place sed (handles differences between BSD/macOS and GNU/Linux)
sedi() {
  if [[ "$OSTYPE" == darwin* ]] || [ "${IS_MAC:-0}" -eq 1 ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Remove duplicates from PATH, keeping the first occurrence
cleanpath() {
  local new_path=""
  local dir
  while IFS= read -r -d: dir; do
    if [[ ! ":$new_path:" == *":$dir:"* ]]; then
      new_path="${new_path:+$new_path:}$dir"
    fi
  done <<<"${PATH:+$PATH:}"
  export PATH="$new_path"
}

# Run a command with secrets injected, without polluting the parent shell
witsec() {
  if [ ! -f "$HOME/.secrets" ]; then
    echo "Error: .secrets file not found!"
    return 1
  fi
  (
    set -a
    source "$HOME/.secrets"
    set +a
    "$@"
  )
}

# Update Git Repository
gitup() {
  export NOW=$(date +"%Y-%m-%d_%H%M%S")
  local msg="${*:-$NOW}"
  git add -A
  git diff --cached --quiet || git commit -m "$msg"
  git pull --rebase --autostash -X ours && git push
}

# Update DOTS Repository
dotup() {
  export NOW=$(date +"%Y-%m-%d_%H%M%S")
  local msg="${*:-$NOW}"
  \cd "$DOTS" >/dev/null || return 1
  git add -A
  git diff --cached --quiet || git commit -m "$msg"
  git pull --rebase --autostash -X ours && git push
  \cd - >/dev/null || true
}

# Edit, source and update BASH configs
ebrc() {
  "$EDITOR" "$DOTS/home/.bashrc" &&
    source "$DOTS/home/.bashrc" &&
    dotup "Updated bashrc"
}
eali() {
  "$EDITOR" "$DOTS/config/bash/alias.bash" &&
    source "$DOTS/config/bash/alias.bash" &&
    dotup "Updated shell aliases"
}
efun() {
  "$EDITOR" "$DOTS/config/bash/function.bash" &&
    source "$DOTS/config/bash/function.bash" &&
    dotup "Updated shell functions"
}
sbrc() {
  source "$DOTS/home/.bashrc"
}
sali() {
  source "$DOTS/config/bash/alias.bash"
}
sfun() {
  source "$DOTS/config/bash/function.bash"
}

# Yazi Shell Wrapper
y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  local cwd="$(command cat "$tmp")"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  \rm -f -- "$tmp" &>/dev/null
}

# Smart cd: zoxide fallback + auto-ls on every directory change
unalias cd 2>/dev/null || true
cd() {
  if (( $# == 0 )); then
    builtin cd ~ && ls
  elif [[ "$1" == "-" || -d "$1" ]]; then
    builtin cd "$@" && ls
  elif declare -F z &>/dev/null; then
    if z "$@"; then
      printf "\U000F17A9 %s\n" "$PWD"
      ls
    else
      echo "Error: Directory not found"
      return 1
    fi
  else
    builtin cd "$@" && ls
  fi
}

# IP address lookup
alias whatismyip="whatsmyip"
whatsmyip() {
  # Internal IP Lookup.
  echo -n "Internal IP: "
  if command -v ip &>/dev/null; then
    local default_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}')
    if [ -n "$default_iface" ]; then
      ip addr show "$default_iface" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1
    else
      hostname -I | awk '{print $1}'
    fi
  elif command -v ipconfig &>/dev/null; then
    local default_iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    if [ -n "$default_iface" ]; then
      ipconfig getifaddr "$default_iface"
    else
      ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1
    fi
  else
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1
  fi

  # External IP Lookup
  echo -n "External IP: "
  curl -4s ifconfig.me
  echo ""
}

# Goes up a specified number of directories  (i.e. up 4)
up() {
  local d=""
  limit=$1
  for ((i = 1; i <= limit; i++)); do
    d=$d/..
  done
  d=$(echo $d | sed 's/^\///')
  if [ -z "$d" ]; then
    d=..
  fi
  cd $d
}

# Copy file with a progress bar
cpp() {
  (
    set -e
    strace -q -ewrite cp -- "${1}" "${2}" 2>&1 |
      awk '{
      count += $NF
        if (count % 10 == 0) {
          percent = count / total_size * 100
          printf "%3d%% [", percent
          for (i=0;i<=percent;i++)
            printf "="
          printf ">"
            for (i=percent;i<100;i++)
              printf " "
            printf "]\r"
        }
    }
    END { print "" }' total_size="$(stat -c '%s' "${1}")" count=0
  )
}

# Copy and go to the directory
cpg() {
  if [ -d "$2" ]; then
    cp "$1" "$2" && cd "$2"
  else
    cp "$1" "$2"
  fi
}

# Move and go to the directory
mvg() {
  if [ -d "$2" ]; then
    mv "$1" "$2" && cd "$2"
  else
    mv "$1" "$2"
  fi
}

# Create and go to the directory
mkdirg() {
  mkdir -p "$1"
  cd "$1"
}

# Searches for text in all files in the current folder
ftext() {
  # -i case-insensitive
  # -I ignore binary files
  # -H causes filename to be printed
  # -r recursive search
  # -n causes line number to be printed
  # optional -F treat search term as a literal, not a regular expression
  # optional -l only print filenames and not the matching lines ex. grep -irl "$1" *
  grep -iIHrn --color=always "$1" . | less -r
}

# Extracts any archive(s) (if unp isn't installed)
extract() {
  for archive in "$@"; do
    if [ -f "$archive" ]; then
      case $archive in
      *.tar.bz2) tar xvjf $archive ;;
      *.tar.gz) tar xvzf $archive ;;
      *.bz2) bunzip2 $archive ;;
      *.rar) rar x $archive ;;
      *.gz) gunzip $archive ;;
      *.tar) tar xvf $archive ;;
      *.tbz2) tar xvjf $archive ;;
      *.tgz) tar xvzf $archive ;;
      *.zip) unzip $archive ;;
      *.Z) uncompress $archive ;;
      *.7z) 7z x $archive ;;
      *) echo "don't know how to extract '$archive'..." ;;
      esac
    else
      echo "'$archive' is not a valid file!"
    fi
  done
}

# Upload a text file or piped output to Hastebin and return the URL
hb() {
  local response
  local hasteKey

  # 1. Check for a file argument FIRST (Prevents Distrobox false-positives)
  if [ $# -gt 0 ]; then
    if [ -f "$1" ]; then
      # File Mode
      response=$(curl -s -X POST --data-binary @"$1" "https://bin.christitus.com/documents")
    else
      echo "Error: File '$1' does not exist."
      return 1
    fi
  # 2. If no file, check if data is being piped in
  elif [ ! -t 0 ]; then
    # Pipe Mode: Using raw @- tells curl to read standard input
    response=$(curl -s -X POST --data-binary @- "https://bin.christitus.com/documents")
  # 3. If neither, show usage instructions
  else
    echo "Usage: hb <filename> OR <command> | hb"
    return 1
  fi
  # Check if curl succeeded
  if [ $? -eq 0 ]; then
    # Extract the key
    hasteKey=$(echo "$response" | grep -o '"key":"[^"]*' | cut -d'"' -f4)
    if [ -n "$hasteKey" ]; then
      echo "https://bin.christitus.com/$hasteKey"
    else
      echo "Error parsing response: $response"
    fi
  else
    echo "Failed to upload the document."
  fi
}

# Monitor streaming logs side-by-side
monitor-streams() {
  tmux new-session -d -s streamlogs 'podman logs -f --tail 50 stremthru'
  tmux split-window -h -t streamlogs 'podman logs -f --tail 50 aiostreams'
  tmux attach-session -t streamlogs
}

# Intelligent Multi-Environment Updater (Host & Distroboxes)
update() {
  local target=""
  local just_args=()

  for arg in "$@"; do
    case "$arg" in
      --containers|-c|containers)
        just_args+=(--containers)
        ;;
      all|host|fedora|ubuntu|athena)
        target="$arg"
        ;;
      *)
        echo "Usage: update [all | host | fedora | ubuntu | athena] [--containers|-c]"
        return 1
        ;;
    esac
  done

  # ── Container Context ──────────────────────────────────────────
  if [ -f /run/.containerenv ]; then
    if [ "$target" = "all" ]; then
      echo "🌐 Inside container. Delegating 'update all' to host..."
      distrobox-host-exec bash -ic "update all ${just_args[*]}"
      return $?
    fi

    echo "📦 Updating current container (${CONTAINER_ID:-distrobox})..."
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf upgrade -y --skip-unavailable
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get upgrade -y
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Syu --noconfirm
    fi
    return
  fi

  # ── Host Context (Bazzite / Silverblue) ─────────────────────────
  case "$target" in
    all)
      echo "🛡️  [1/2] Updating Host (Brew, Flatpaks, ujust, dotfiles)..."
      just update "${just_args[@]}"

      if command -v distrobox >/dev/null 2>&1 && distrobox list --no-color 2>/dev/null | awk -F '|' 'NR>1 {gsub(/[ \t]+/, "", $2); if (length($2) > 0) count++} END {exit (count > 0 ? 0 : 1)}'; then
        echo -e "\n📦 [2/2] Updating all Distroboxes..."
        distrobox-upgrade --all
      fi

      echo -e "\n✅ Update completed successfully!"
      ;;
    fedora)
      if command -v distrobox >/dev/null 2>&1 && distrobox list --no-color 2>/dev/null | grep -qw "fedora"; then
        echo "📦 Updating 'fedora' Distrobox..."
        distrobox enter fedora -- sudo dnf upgrade -y --skip-unavailable
      else
        echo "⚠️ 'fedora' Distrobox not found."
      fi
      ;;
    ubuntu)
      if command -v distrobox >/dev/null 2>&1 && distrobox list --no-color 2>/dev/null | grep -qw "ubuntu"; then
        echo "📦 Updating 'ubuntu' Distrobox..."
        distrobox enter ubuntu -- sh -c "sudo apt-get update && sudo apt-get upgrade -y"
      else
        echo "⚠️ 'ubuntu' Distrobox not found."
      fi
      ;;
    athena)
      if command -v distrobox >/dev/null 2>&1 && distrobox list --no-color 2>/dev/null | grep -qw "athena"; then
        echo "📦 Updating 'athena' Distrobox..."
        distrobox enter athena -- sh -c "sudo apt-get update && sudo apt-get upgrade -y"
      else
        echo "⚠️ 'athena' Distrobox not found."
      fi
      ;;
    host|"")
      echo "🛡️  Updating Host..."
      just update "${just_args[@]}"
      ;;
  esac
}

# Set Ptyxis terminal opacity for the active default profile (e.g. ptrans 0.85)
ptrans() {
  local dconf_cmd=(dconf)
  if [ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    dconf_cmd=(distrobox-host-exec dconf)
  fi

  local uuid
  uuid="$("${dconf_cmd[@]}" read /org/gnome/Ptyxis/default-profile-uuid 2>/dev/null | tr -d "'")"
  if [ -z "$uuid" ]; then
    echo "Error: Could not determine Ptyxis default-profile-uuid." >&2
    return 1
  fi

  if [ -z "${1:-}" ]; then
    local current
    current="$("${dconf_cmd[@]}" read "/org/gnome/Ptyxis/Profiles/${uuid}/opacity" 2>/dev/null)"
    echo "Current Ptyxis opacity ($uuid): ${current:-1.0}"
    echo "Usage: ptrans <decimal> (e.g. ptrans 0.85)"
    return 0
  fi

  local val="$1"
  [[ "$val" != *.* ]] && val="${val}.0"

  "${dconf_cmd[@]}" write "/org/gnome/Ptyxis/Profiles/${uuid}/opacity" "$val"
}



# ────── PORTABLE UTILITIES (ADOPTED FROM OMARCHY) ──────

# Open files/URLs with default app on Linux (macOS already has native open)
unalias open 2>/dev/null
if [[ "${IS_LINUX:-0}" -eq 1 || "$OSTYPE" == linux* ]]; then
  function open {
    xdg-open "$@" >/dev/null 2>&1 &
  }
fi

# Open Neovim in current directory or with given arguments
n() {
  if [ "$#" -eq 0 ]; then
    command nvim .
  else
    command nvim "$@"
  fi
}

# Fuzzy file preview picker (keeps `ff` free for fastfetch)
fp() {
  if [[ "${TERM:-}" == "xterm-kitty" ]] && command -v bat &>/dev/null; then
    fzf --preview 'case $(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac' "$@"
  elif command -v bat &>/dev/null; then
    fzf --preview 'bat --style=numbers --color=always {}' "$@"
  else
    fzf "$@"
  fi
}

# Fuzzy-pick a file and open it in $EDITOR
eff() {
  local file
  file=$(fp "$@") && [[ -n $file ]] && "${EDITOR:-nvim}" "$file"
}

# ── SSH Auto-Reconnect & Terminal Mode Disarm ───────────────────
# Wrap ssh to disarm stuck terminal modes (mouse tracking, focus reporting,
# alternate screen) and auto-reconnect when an interactive session drops.
ssh() {
  local rc started

  started=$SECONDS
  command ssh "$@"
  rc=$?

  [[ -t 1 ]] || return $rc
  _ssh_disarm

  if (( rc != 255 )) || [[ ! -t 0 ]] || ! _ssh_interactive "$@" ||
    (( SECONDS - started < 30 )); then
    return $rc
  fi

  (
    while true; do
      echo "Connection lost. Reconnecting (Ctrl-C to stop)..."
      sleep 2
      command ssh "$@"
      rc=$?
      _ssh_disarm
      (( rc != 255 )) && exit $rc
    done
  )
}

_ssh_disarm() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?1049l\e[?25h'
}

_ssh_interactive() {
  local value_opts="BbcDEeFIiJLlmOoPpQRSWw"
  local argv=("$@") arg letters i dest="" opts_done=""

  while (($#)); do
    arg="$1"
    shift

    if [[ -z $opts_done && $arg == "--" ]]; then
      opts_done=1
    elif [[ -z $opts_done && $arg == -?* ]]; then
      letters="${arg#-}"
      for ((i = 0; i < ${#letters}; i++)); do
        if [[ $value_opts == *"${letters:i:1}"* ]]; then
          (( i == ${#letters} - 1 )) && shift
          break
        fi
      done
    elif [[ -z $dest ]]; then
      dest="$arg"
    else
      return 1
    fi
  done

  [[ -n $dest ]] || return 1

  local resolved
  resolved=$(command ssh -G "${argv[@]}" 2>/dev/null) || return 1
  ! grep -i '^remotecommand ' <<<"$resolved" | grep -qvi '^remotecommand none$'
}

# ── SSH Local Port Forwarding ───────────────────────────────────
fip() {
  (( $# < 2 )) && echo "Usage: fip <host> <port1> [port2] ..." && return 1
  local host="$1"
  shift
  for port in "$@"; do
    ssh -f -N -L "${port}:localhost:${port}" "$host" && echo "Forwarding localhost:$port -> $host:$port"
  done
}

dip() {
  (( $# == 0 )) && echo "Usage: dip <port1> [port2] ..." && return 1
  for port in "$@"; do
    pkill -f "ssh.*-L ${port}:localhost:${port}" && echo "Stopped forwarding port $port" || echo "No forwarding on port $port"
  done
}

lip() {
  pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+" || echo "No active forwards"
}

# ── Git Worktrees ───────────────────────────────────────────────
# Create a new worktree and branch from within current git directory
ga() {
  if [[ -z "${1:-}" ]]; then
    echo "Usage: ga <branch-name>"
    return 1
  fi

  local branch="$1"
  local base
  base="$(basename "$PWD")"
  local wt_path="../${base}--${branch}"

  git worktree add -b "$branch" "$wt_path" || return 1
  command -v mise &>/dev/null && mise trust "$wt_path"
  cd "$wt_path"
}

# Remove worktree and branch from within active worktree directory
gd() {
  local confirmed=0
  if command -v gum &>/dev/null; then
    gum confirm "Remove worktree and branch?" && confirmed=1
  else
    local reply
    read -rp "Remove worktree and branch? (y/N): " reply
    [[ "$reply" =~ ^[Yy]$ ]] && confirmed=1
  fi

  if (( confirmed )); then
    local cwd branch root worktree

    cwd="$(pwd)"
    worktree="$(basename "$cwd")"

    # split on first `--`
    root="${worktree%%--*}"
    branch="${worktree#*--}"

    # Protect against accidentally nuking a non-worktree directory
    local git_dir
    git_dir="$(git rev-parse --git-dir 2>/dev/null)" || { echo "Error: Not a git repository"; return 1; }
    if [[ "$root" != "$worktree" && "$git_dir" == *"/worktrees/"* ]]; then
      cd "../$root" || return 1
      git worktree remove "$cwd" --force || return 1
      git branch -D "$branch"
    else
      echo "Error: Not an active linked worktree"
      return 1
    fi
  fi
}

# ── Tmux Dev Layouts ────────────────────────────────────────────
# Create a Tmux Dev Layout with editor, ai, and terminal
# Usage: tdl <ai_cmd> [<second_ai_cmd>]
tdl() {
  [[ -z "${1:-}" ]] && { echo "Usage: tdl <ai_cmd> [<second_ai_cmd>]"; return 1; }
  [[ -z "${TMUX:-}" ]] && { echo "You must start tmux to use tdl."; return 1; }

  local current_dir="${PWD}"
  local editor_pane ai_pane ai2_pane
  local ai="$1"
  local ai2="${2:-}"

  editor_pane="$TMUX_PANE"
  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  # Split window vertically - top 85%, bottom 15%
  tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir"

  # Split editor pane horizontally - AI on right 30%
  ai_pane=$(tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')

  # If second AI provided, split the AI pane vertically
  if [[ -n $ai2 ]]; then
    ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
    tmux send-keys -t "$ai2_pane" "$ai2" C-m
  fi

  tmux send-keys -t "$ai_pane" "$ai" C-m
  tmux send-keys -t "$editor_pane" "${EDITOR:-nvim} ." C-m

  # Select the editor pane for focus (fixes Omarchy's undefined $opencode_pane)
  tmux select-pane -t "$editor_pane"
}

# Create a Tmux Dev Square layout with editor, diff watch, terminal, and opencode
tds() {
  [[ -n "${1:-}" ]] && { echo "Usage: tds"; return 1; }
  [[ -z "${TMUX:-}" ]] && { echo "You must start tmux to use tds."; return 1; }

  local current_dir="${PWD}"
  local editor_pane diff_pane terminal_pane opencode_pane

  editor_pane="$TMUX_PANE"
  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  terminal_pane=$(tmux split-window -v -p 50 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  diff_pane=$(tmux split-window -h -p 50 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  opencode_pane=$(tmux split-window -h -p 50 -t "$terminal_pane" -c "$current_dir" -P -F '#{pane_id}')

  tmux send-keys -t "$editor_pane" -l "${EDITOR:-nvim} ."
  tmux send-keys -t "$editor_pane" C-m
  tmux send-keys -t "$diff_pane" -l "hunk diff --watch"
  tmux send-keys -t "$diff_pane" C-m
  tmux send-keys -t "$opencode_pane" -l "opencode"
  tmux send-keys -t "$opencode_pane" C-m

  tmux select-pane -t "$editor_pane"
}

# Create multiple tdl windows with one per subdirectory in the current directory
tdlm() {
  [[ -z "${1:-}" ]] && { echo "Usage: tdlm <ai_cmd> [<second_ai_cmd>]"; return 1; }
  [[ -z "${TMUX:-}" ]] && { echo "You must start tmux to use tdlm."; return 1; }

  local ai="$1"
  local ai2="${2:-}"
  local base_dir="$PWD"
  local first=true
  local tdl_command

  tmux rename-session "$(basename "$base_dir" | tr '.:' '--')"

  for dir in "$base_dir"/*/; do
    [[ -d $dir ]] || continue
    local dirpath="${dir%/}"

    printf -v tdl_command 'tdl %q' "$ai"
    [[ -n $ai2 ]] && printf -v tdl_command '%s %q' "$tdl_command" "$ai2"

    if $first; then
      printf -v tdl_command 'cd %q && %s' "$dirpath" "$tdl_command"
      tmux send-keys -t "$TMUX_PANE" "$tdl_command" C-m
      first=false
    else
      local pane_id
      pane_id=$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')
      tmux send-keys -t "$pane_id" "$tdl_command" C-m
    fi
  done
}

# Create a multi-pane tiled swarm layout with the same command started in each pane
tsl() {
  [[ ! "${1:-}" =~ ^[1-9][0-9]*$ || -z "${2:-}" ]] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
  [[ -z "${TMUX:-}" ]] && { echo "You must start tmux to use tsl."; return 1; }

  local count="$1"
  shift
  local cmd
  if (( $# == 1 )); then
    cmd="$1"
  else
    printf -v cmd '%q ' "$@"
    cmd="${cmd% }"
  fi
  local current_dir="${PWD}"
  local -a panes

  tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"
  panes+=("$TMUX_PANE")

  while (( ${#panes[@]} < count )); do
    local new_pane
    local split_target="${panes[-1]}"
    new_pane=$(tmux split-window -h -t "$split_target" -c "$current_dir" -P -F '#{pane_id}')
    panes+=("$new_pane")
    tmux select-layout -t "${panes[0]}" tiled
  done

  for pane in "${panes[@]}"; do
    tmux send-keys -t "$pane" "$cmd" C-m
  done

  tmux select-pane -t "${panes[0]}"
}
