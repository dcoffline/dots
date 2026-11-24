# =============================================================================
# SYSTEM MAINTENANCE
# =============================================================================

# Implementation lives in .githooks/check_links.sh, shared with the pre-push gate.
# Verifies every tracked dots file resolves into the dots repo via relative symlinks
check-links:
    #!/usr/bin/env bash
    set -euo pipefail
    exec bash "${DOTS:-$HOME/src/dots}/.githooks/check_links.sh"

# Checks the status of system and user systemd services and reports any failures
status:
    #!/usr/bin/env bash
    set -uo pipefail
    source "$HOME/.config/just/lib/common.sh"

    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "⚠️ Systemd is not available on macOS."
      exit 0
    fi

    BOLD="\033[1m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RED="\033[31m"
    CYAN="\033[36m"
    DIM="\033[2m"
    RESET="\033[0m"

    echo -e "${BOLD}${CYAN}================================================================${RESET}"
    echo -e "${BOLD}${CYAN}                 SYSTEMD STATUS OVERVIEW                        ${RESET}"
    echo -e "${BOLD}${CYAN}================================================================${RESET}\n"

    # 1. System-level Status
    sys_state=$(host_exec systemctl is-system-running 2>/dev/null || host_exec systemctl is-system-running 2>&1 || echo "unknown")
    sys_failed_count=$(host_exec systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null | grep -v "^$" | wc -l)
    sys_running_srv=$(host_exec systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | grep -v "^$" | wc -l)
    sys_active_units=$(host_exec systemctl list-units --state=active --no-legend --no-pager 2>/dev/null | grep -v "^$" | wc -l)

    echo -e "${BOLD}⚙️  SYSTEM (Host)${RESET}"
    if [ "$sys_state" = "running" ] && [ "$sys_failed_count" -eq 0 ]; then
      echo -e "   Status: ${GREEN}● running${RESET} | Running Services: ${BOLD}${sys_running_srv}${RESET} | Active Units: ${BOLD}${sys_active_units}${RESET} | Failed: ${GREEN}0${RESET}"
    else
      echo -e "   Status: ${RED}● ${sys_state}${RESET} | Running Services: ${BOLD}${sys_running_srv}${RESET} | Active Units: ${BOLD}${sys_active_units}${RESET} | Failed: ${RED}${sys_failed_count}${RESET}"
    fi

    # 2. User-level Status
    user_state=$(host_exec systemctl --user is-system-running 2>/dev/null || host_exec systemctl --user is-system-running 2>&1 || echo "unknown")
    user_failed_count=$(host_exec systemctl --user list-units --state=failed --no-legend --no-pager 2>/dev/null | grep -v "^$" | wc -l)
    user_running_srv=$(host_exec systemctl --user list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | grep -v "^$" | wc -l)
    user_active_units=$(host_exec systemctl --user list-units --state=active --no-legend --no-pager 2>/dev/null | grep -v "^$" | wc -l)

    echo -e "\n${BOLD}👤 USER ($(whoami))${RESET}"
    if [ "$user_state" = "running" ] && [ "$user_failed_count" -eq 0 ]; then
      echo -e "   Status: ${GREEN}● running${RESET} | Running Services: ${BOLD}${user_running_srv}${RESET} | Active Units: ${BOLD}${user_active_units}${RESET} | Failed: ${GREEN}0${RESET}"
    else
      echo -e "   Status: ${RED}● ${user_state}${RESET} | Running Services: ${BOLD}${user_running_srv}${RESET} | Active Units: ${BOLD}${user_active_units}${RESET} | Failed: ${RED}${user_failed_count}${RESET}"
    fi

    echo ""

    # 3. Detailed Failure Reports if needed
    has_failure=false

    if [ "$sys_failed_count" -gt 0 ] || ([ "$sys_state" != "running" ] && [ "$sys_state" != "unknown" ]); then
      has_failure=true
      echo -e "${RED}${BOLD}❌ System-Level Failed Units (${sys_failed_count}):${RESET}"
      host_exec systemctl --failed --no-pager
      echo ""
    fi

    if [ "$user_failed_count" -gt 0 ] || ([ "$user_state" != "running" ] && [ "$user_state" != "unknown" ]); then
      has_failure=true
      echo -e "${RED}${BOLD}❌ User-Level Failed Units (${user_failed_count}):${RESET}"
      host_exec systemctl --user --failed --no-pager
      echo ""
    fi

    if [ "$has_failure" = false ]; then
      echo -e "${GREEN}${BOLD}✅ All systemd units and services are healthy!${RESET}\n"
    else
      echo -e "${YELLOW}${BOLD}💡 Tip:${RESET} To inspect a failed service, run:"
      echo -e "   ${DIM}systemctl status <unit>${RESET} or ${DIM}systemctl --user status <unit>${RESET}"
      echo -e "   ${DIM}journalctl -xeu <unit>${RESET} or ${DIM}journalctl --user -xeu <unit>${RESET}\n"
    fi

# Initiates the Fortress Maintenance Protocol (Updates, Syncs, Backups; pass --containers/-c to include Quadlets)
update *args:
    #!/usr/bin/env bash
    exec bash "$HOME/.config/just/lib/update.sh" {{args}}

# Relinks all 2T persistent data directories back into ~/.local/share
link-persistent:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$HOME/.local/share" "$HOME/.config/bash"
    for dir in "$HOME/.mnt/2T/local/"*; do
        name="$(basename "$dir")"
        # Skip special dotfiles
        [[ "$name" == .* ]] && continue
        ln -sfn "$(realpath --relative-to="$HOME/.local/share" "$dir")" "$HOME/.local/share/$name"
    done
    ln -sfn "$HOME/.mnt/2T/local/.atuin" "$HOME/.atuin"
    ln -sfn "$HOME/.mnt/2T/local/.histfile" "$HOME/.config/bash/.histfile"
    echo "✅ All persistent folders linked from 2T successfully."

# Clean up macOS AppleDouble sidecar files (._*) in a target directory
[no-cd]
clean-apple target_dir="":
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET_DIR="{{target_dir}}"
    TARGET_DIR="${TARGET_DIR:-$HOME/.mnt/10T/Documents/Notes}"
    if [ ! -d "$TARGET_DIR" ] && [ -d "/var/home/eric/.mnt/10T/Documents/Notes" ]; then
        TARGET_DIR="/var/home/eric/.mnt/10T/Documents/Notes"
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Error: Directory '$TARGET_DIR' does not exist."
        exit 1
    fi

    echo "Target directory: $TARGET_DIR"
    echo "Searching for macOS hidden sidecar files (._*)..."

    FILE_COUNT=$(find "$TARGET_DIR" -name "._*" | wc -l)
    echo "Found $FILE_COUNT '._*' files/directories."

    if [ "$FILE_COUNT" -eq 0 ]; then
        echo "No '._*' files found. Nothing to clean!"
        exit 0
    fi

    read -p "Do you want to delete these $FILE_COUNT files/directories? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting..."
        find "$TARGET_DIR" -name "._*" -print0 | xargs -0 rm -rf
        echo "Done! Cleaned up $FILE_COUNT '._*' files."
    else
        echo "Cancelled. No files were deleted."
    fi
