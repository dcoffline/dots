# Dotfiles Project

## Purpose
This project manages the configuration and installation of a development environment (The Fortress) across both immutable hosts (like Bazzite or Fedora Silverblue) and mutable environments (like Fedora Distrobox or standard Fedora Workstation).

## Architecture
- **`install.sh`**: The bootstrap script. It installs `chezmoi` and initializes the configuration.
- **Chezmoi**: Manages dotfiles by copying them to `$HOME`.
  - **`.chezmoi.toml.tmpl`**: Detects the environment (Immutable Host vs. Container) and stores it in the `envType` variable.
  - **`run_onchange_install-packages.sh.tmpl`**: A Chezmoi run script that handles package installation (Brew, DNF, Cargo, etc.) based on the detected `envType`.
- **`Brewfile`**: Defines the package set for Homebrew-managed environments.
- **`dot_config/`**: Contains the dotfiles for `~/.config`.
- **`dot_local/`**: Contains scripts and data for `~/.local`.
- **`dot_config/containers/systemd/`**: Quadlet files for managing containerized services.
- **Secrets Management**: Sensitive files (like `~/.secrets`) are encrypted in the source repository using **Age**. 
  - Source file: `encrypted_dot_secrets.age`
  - Key location: `~/.config/chezmoi/key.txt` (This file MUST be backed up to a secure location like Bitwarden).
  - Config: Defined in `.chezmoi.toml.tmpl`.

## Idempotency Rules & Gotchas
- **Chezmoi Templating**: Use `.tmpl` extensions for files that need to adapt to different environments. However, since `~` is shared between host and container, most dotfiles should remain static and universal.
- **Run Scripts**: Scripts prefixed with `run_onchange_` will only run if their content (or the files they depend on) changes.

## Recent Changes
- **Migration to Chezmoi**: Replaced GNU Stow with Chezmoi for better management of dotfiles and environment-specific logic.
  - Consolidated `home/`, `config/`, and `local/` into a single root structure using Chezmoi's `dot_` convention.
  - Moved package installation logic from `install.sh` into a Chezmoi `run_onchange_` script.
- **Pure Bash Migration**: Migrated the entire configuration to be 100% Bash compliant, removing Zsh and Fish dependencies.

## Future Notes
- When adding new CLI tools, ensure they are added to both `run_onchange_install-packages.sh.tmpl` (DNF/Cargo/NPM sections) and the `Brewfile` to maintain parity across environments.
- GUI apps should be added to the `FLATPAK_APPS` array in `run_onchange_install-packages.sh.tmpl`.
