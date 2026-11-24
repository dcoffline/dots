# =============================================================================
# MULTI-OS DOTFILES MANAGEMENT (FORTRESS JUSTFILE ROUTER)
# =============================================================================
# Domain recipes live in ~/.config/just/*.just (stowed from $DOTS/config/just/).
# Shared helpers & large scripts live in $DOTS/config/just/lib/.
#
# Flat recipe names on purpose: systemd user units and shell aliases call these
# names directly, and bee's immutable /usr/bin/just is 1.21.0, which has no
# stable `mod`, `alias x := mod::y`, or `--list-submodules`. Plain `import`
# works on every just version we run.

import '~/.config/just/system.just'
import '~/.config/just/cloud.just'
import '~/.config/just/containers.just'
import '~/.config/just/backup.just'
import '~/.config/just/desktop.just'
import '~/.config/just/tools.just'
import '~/.config/just/media.just'
import? '~/.config/just/local.just'

# Running 'just' with no arguments displays all recipes
default:
    @just --list

# Launch the just-tui recipe browser (q to quit, Enter to run with y/n confirm)
tui:
    @~/.local/bin/just-tui --justfile "{{justfile()}}"
