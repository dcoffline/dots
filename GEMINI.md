# Dotfiles Project

## Purpose
This project manages the configuration and installation of a development environment (The Fortress) across both immutable hosts (like Bazzite or Fedora Silverblue) and mutable environments (like Fedora Distrobox or standard Fedora Workstation).

## Architecture
- **`install.sh`**: The bootstrap script. It installs `stow` and initializes the configuration.
- **Stow**: Manages dotfiles by symlinking them to `$HOME`.
- **`install-packages.sh`**: A script that handles package installation (Brew, DNF, Cargo, etc.) based on the detected environment.
- **`Brewfile`**: Defines the package set for Homebrew-managed environments.
- **`config/`**: Contains the dotfiles for `~/.config`.
- **`local/`**: Contains scripts and data for `~/.local`.
- **`config/containers/systemd/`**: Quadlet files for managing containerized services.
- **Secrets Management**: Sensitive files are stored in `~/.secrets` which is gitignored and must be backed up manually.

## Idempotency Rules & Gotchas
- Since `~` is shared between host and container, most dotfiles should remain static and universal.

## Recent Changes
- **Migration to GNU Stow**: Reverted from Chezmoi back to GNU Stow for simplicity.
  - Renamed `dot_` directories back to standard names.
  - Restored `install-packages.sh` to a standard bash script.
- **Pure Bash Migration**: Migrated the entire configuration to be 100% Bash compliant, removing Zsh and Fish dependencies.

## Future Notes
- When adding new CLI tools, ensure they are added to both `install-packages.sh` (DNF/Cargo/NPM sections) and the `Brewfile` to maintain parity across environments.
- GUI apps should be added to the `FLATPAK_APPS` array in `install-packages.sh`.
