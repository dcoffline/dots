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
- **Secrets Management**: Sensitive files are stored in `~/.config/bash/.secrets` or `~/.config/zsh/.secrets` which are gitignored and must be backed up manually.

## Idempotency Rules & Gotchas
- Since `~` is shared between host and container, most dotfiles should remain static and universal.

## Recent Changes
- **macOS & Zsh Re-integration**: Re-introduced Zsh configuration and Oh My Zsh themes. Improved macOS support and overall script robustness.
- **Migration to GNU Stow**: Reverted from Chezmoi back to GNU Stow for simplicity.
  - Renamed `dot_` directories back to standard names.
  - Updated `install-pkg.sh` to handle package management.
- **Pure Bash Migration (Legacy)**: Previously migrated to 100% Bash, but Zsh support was later restored for better cross-platform compatibility.

## Future Notes
- When adding new CLI tools, ensure they are added to both `install-pkg.sh` (DNF/Cargo/NPM sections) and the `Brewfile` to maintain parity across environments.
- GUI apps should be added to the `FLATPAK_APPS` array in `install-pkg.sh`.
