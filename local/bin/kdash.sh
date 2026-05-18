#!/bin/bash

# This script launches Kitty with a simple horizontal split.
# You will then manually create the right-side panes.

echo "Launching Kitty with a simple 'btop | right-panel' layout..."
echo "Once Kitty opens:"
echo "  1. Inside the new 'right-panel' tab/shell:"
echo "     a. Press Ctrl+Shift+Enter to create a new horizontal pane (this will be for yazi)."
echo "     b. In the top pane (which is still the original 'right-panel' shell):"
echo "        i.  Type 'ticker' and press Enter."
echo "        ii. Press Ctrl+Shift+\\ (backslash) to split this top pane horizontally."
echo "        iii. In the new pane that appears, type 'kew view' and press Enter."
echo "     c. Navigate to the bottom pane (yazi) using Ctrl+Shift+Right/Left arrows if needed."

# Start Kitty detached
kitty --detach

# Wait a moment
sleep 1

# Launch the simple layout: btop on the left, a shell on the right
kitty \
  --title "Dashboard" \
  --config /dev/null \
  -o allow_remote_control=yes \
  -o enabled_layouts=horizontal,vertical \
  btop \
  new-window bash

echo "Kitty window launched. Please follow the manual steps above."
