#!/usr/bin/env bash
# Unified Rclone launcher that runs the centralized just recipe

if command -v just &>/dev/null; then
  exec just mount "$@"
elif [ -x /opt/homebrew/bin/just ]; then
  exec /opt/homebrew/bin/just mount "$@"
else
  echo "Error: 'just' command runner not found in PATH or /opt/homebrew/bin/just" >&2
  exit 1
fi
