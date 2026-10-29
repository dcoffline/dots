# Dotfiles Project

## Purpose
This project manages the configuration and installation of a development environment (The Fortress) across both immutable hosts (like Bazzite or Fedora Silverblue) and mutable environments (like Fedora Distrobox or standard Fedora Workstation).

## Architecture
- **`install.sh`**: The bootstrap script. It installs `stow` and initializes the configuration.
- **Stow**: Manages dotfiles by symlinking them to `$HOME`.
- **`install-pkg.sh`**: A script that handles package installation (Brew, DNF, Cargo, etc.) based on the detected environment.
- **`Brewfile`**: Defines the package set for Homebrew-managed environments.
- **`config/`**: Contains the dotfiles for `~/.config`.
- **`local/`**: Contains scripts and data for `~/.local`.
- **`config/containers/systemd/`**: Quadlet files for managing containerized services.
- **`config/systemd/user`**: Service files for --user systemd services.
- **Secrets Management**: Sensitive files (`home/.secrets`, `local/share/**/*.env`, `*.secret`) are transparently encrypted and tracked using **`git-crypt`**. Commits are guarded by a pre-push secret scanner and a symlink integrity checker (`check_links.sh`).

## Idempotency Rules & Gotchas
- Since `~` is shared between host and container, most dotfiles should remain static and universal.
- In Distrobox containers, `/home` (including `/home/linuxbrew/.linuxbrew`) is mounted from the host, making all host Homebrew CLI binaries directly accessible inside containers without wrapper shims.

## Recent Changes
- **Homebrew CLI & Tool Consolidation**:
  - Migrated CLI tools (`gh`, `glab`, `shellcheck`, `sops`, `stress-ng`, `cava`, `fastfetch`, `make`, `pipx`) and Rust/Go binaries (`atuin`, `bat`, `dysk`, `eza`, `fd`, `lf`, `ripgrep`, `starship`, `tealdeer`, `television`, `yazi`, `zoxide`) into native Homebrew bottles in `Brewfile`.
  - Removed reliance on a dedicated Fedora Distrobox container for DNF CLI binaries and cleaned up `distrobox-export` wrapper scripts in `~/.local/bin/`.
  - Added standalone native Jottacloud CLI installation (`jotta-cli` and `jottad`) for Linux into `~/.local/bin/`, updating `jotta.service` to run natively on the host.
- **KDE Plasma & Desktop Streaming**:
  - Adapted host scripts, display services, and `install.sh` guards for KDE Plasma on Bazzite (guarded GNOME GSettings schema execution).
  - Enhanced Sunshine / Moonlight remote streaming: BetterDisplay virtual displays on macOS, dynamic resolution and multi-aspect ratio switching (16:9, 16:10, 21:9) on Linux (`dpon`/`dpoff`, `monctl`, `sunshine-wait-display`, `touchup`).
- **Secrets & Security Overhaul**:
  - Decoupled monolithic secrets into scoped, per-service `.env` files in `local/share/` (Immich, Nextcloud-DB, AioStreams, Open-SEO, FreeLLMAPI).
  - Tracked and encrypted via `git-crypt` (`home/.secrets`, `local/share/**/*.env`, `*.secret`).
  - Added pre-push security scan hook to prevent accidental plaintext credential commits.
  - Added pre-push `check_links.sh` gate to guarantee GNU Stow symlink integrity.
- **AI & Homelab Quadlet Updates**:
  - Integrated Athena / Hermes Studio, Honcho cognitive memory engine, Odysseus, Vane, and FreeLLMAPI into rootless Quadlet suites.
  - Automated disaster recovery and backup tasks (`backup-immich`, `backup-honcho`, `backup-nextcloud`, `backup-athena`).
  - Streamlined media stack (Jellyfin, AioStreams, MediaFlow, Threadfin; retired legacy Zurg/MediaFusion).
- **Migration to GNU Stow**: Reverted from Chezmoi back to GNU Stow for simplicity.
- **Pure Bash Migration**: Reverted back to 100% Bash across all environments (macOS, Linux hosts, and containers) for consistency and simplicity.

## Future Notes
- When adding new CLI tools, add them directly to the `Brewfile` (using `if OS.mac?` or `if OS.linux?` if platform-specific).
- GUI apps should be added to the `FLATPAK_APPS` array in `install-pkg.sh`.
