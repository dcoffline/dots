# =============================================================================
# MULTI-OS DOTFILES MANAGEMENT (FORTRESS JUSTFILE ROUTER)
# =============================================================================
# Domain modules live in $DOTS/config/just/ (stowed -> ~/.config/just/)
# Shared helpers & large scripts live in $DOTS/config/just/lib/

mod system '~/.config/just/system.just'
mod cloud '~/.config/just/cloud.just'
mod containers '~/.config/just/containers.just'
mod backup '~/.config/just/backup.just'
mod desktop '~/.config/just/desktop.just'
mod tools '~/.config/just/tools.just'
mod media '~/.config/just/media.just'
import? '~/.config/just/local.just'

# Running 'just' with no arguments displays all modules and recipes
default:
    @just --list --list-submodules

# Launch the just-tui recipe browser (q to quit, Enter to run with y/n confirm)
tui:
    @~/.local/bin/just-tui --justfile "{{justfile()}}"

# =============================================================================
# BACKWARDS-COMPATIBLE TOP-LEVEL ALIASES (hidden from `just --list`)
# Keeps rmount, systemd user services, bash aliases/functions, and muscle
# memory working seamlessly alongside the namespaced `just <mod> <recipe>` CLI.
# =============================================================================

# system
[private]
alias check-links := system::check-links
[private]
alias status := system::status
[private]
alias update := system::update
[private]
alias link-persistent := system::link-persistent
[private]
alias clean-apple := system::clean-apple

# cloud
[private]
alias mount := cloud::mount
[private]
alias unmount := cloud::unmount
[private]
alias check-mounts := cloud::check-mounts
[private]
alias update-rclone := cloud::update-rclone
[private]
alias restow-nextcloud := cloud::restow
[private]
alias sync-gdrive := cloud::sync-gdrive
[private]
alias resync-gdrive := cloud::resync-gdrive

# containers
[private]
alias build-local-images := containers::build-images
[private]
alias stow-containers := containers::stow
[private]
alias unstow-containers := containers::unstow

# backup
[private]
alias backup-nextcloud := backup::nextcloud
[private]
alias backup-athena := backup::athena
[private]
alias restore-athena := backup::restore-athena
[private]
alias backup-immich := backup::immich
[private]
alias backup-honcho := backup::honcho
[private]
alias backup-apps := backup::apps

# desktop
[private]
alias update-sunshine := desktop::update-sunshine
[private]
alias fix-sunshine := desktop::fix-sunshine
[private]
alias fix-flicker := desktop::fix-flicker

# tools
[private]
alias install-omarchy-cli := tools::omarchy-cli
[private]
alias install-agy := tools::agy
[private]
alias install-voxtype := tools::voxtype
[private]
alias install-openwispr := tools::openwispr

# media
[private]
alias threadfin-fix-epg := media::threadfin-fix-epg
[private]
alias gelato-sync := media::gelato-sync
[private]
alias gelato-list := media::gelato-list
[private]
alias gelato-prune := media::gelato-prune
[private]
alias gelato-prune-ids := media::gelato-prune-ids
[private]
alias gelato-reset := media::gelato-reset
[private]
alias jf-restart := media::jf-restart
[private]
alias gelato-sync-run := media::gelato-sync-run
