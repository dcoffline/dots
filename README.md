# 🛡️ The Fortress — Multi-OS Dotfiles & Homelab Stack

An XDG-compliant, modular Bash environment and containerized homelab architecture tailored for **macOS**, **immutable Linux** (Bazzite, Fedora Silverblue), **mutable Linux** (Fedora, Debian/Ubuntu, Arch), and **WSL**.

---

## 🌟 Key Highlights

- **Pure Bash Modular Shell**: Fast, clean, unified configuration loaded from `~/.config/bash/` across all platforms.
- **GNU Stow Management**: Clean symlinking organized into modular packages (`home`, `config`, `local`, and macOS `Library`).
- **Idempotent Installation & Backup**: Automatically detects pre-existing conflicting configurations and backs them up to `*.bak` before symlinking.
- **Complete Uninstall Routine**: Safe, clean teardown via [`uninstall.sh`](file:///Users/eric/src/dots/uninstall.sh) that unstows packages, cleans lingering symlinks, and restores original `*.bak` configurations.
- **Environment & Distrobox Aware**: Automatically detects host vs container environments, immutable vs mutable systems, and macOS vs Linux.
- **Multi-tiered Package Automation**: Automatically provisions CLI & GUI tools via **Homebrew** (`Brewfile`), **DNF**, **APT**, **Pacman**, **Cargo** (`cargo-binstall`), **Flatpak**, and **GNOME Extensions**.
- **Justfile Automation**: Comprehensive task runner managing updates, rclone mounts, disaster recovery backups (Athena, Nextcloud), voice-to-text engines, and systemd monitoring.
- **Podman Quadlet Application Stack**: Production-ready, systemd-managed rootless container suite.

---

## 🏗️ Architecture & Structure

```
~/src/dots/
├── install.sh                  # Bootstrap script: checks stow, backs up conflicts, links dotfiles, installs pkgs
├── uninstall.sh                # Uninstaller: unlinks stow packages, cleans symlinks, restores *.bak backups
├── install-pkg.sh              # Multi-OS package installer (Brew, DNF/APT/Pacman, Cargo, Flatpaks, GNOME)
├── Brewfile                    # Declarative Homebrew package definitions (macOS & Linuxbrew)
├── CHEATSHEET.md               # Quick command & alias reference card
│
├── home/                       # Symlinked to ~ ($HOME)
│   ├── .bashrc                 # Primary shell entry point
│   ├── .bash_profile         # Login shell profile
│   ├── .justfile               # Task runner recipes (status, update, mount, backup-athena, etc.)
│   └── .secrets                # (Optional) Local secrets file (gitignored / chmod 600)
│
├── config/                     # Symlinked to ~/.config/
│   ├── bash/                   # Modular bash files (alias.bash, function.bash, os.bash, path.bash)
│   ├── containers/systemd/     # Podman Quadlet container definitions (.container, .network)
│   ├── systemd/user/           # User-level systemd service units & timers (.service, .timer)
│   ├── environment.d/          # Global environment definitions (envvars.conf)
│   ├── dconf-backups/          # GNOME Shell and TilingShell dconf dumps
│   ├── atuin/, btop/, ghostty/, nvim/, searxng/, sunshine/, voxtype/, waveterm/, yazi/, starship.toml
│
├── local/                      # Symlinked to ~/.local/
│   ├── scripts/                # Utility scripts (rmount, monctl, voxtype-clean, dpon/dpoff, gdmreset)
│   └── share/                  # App data (Homepage, GNOME shell extensions, bash-preexec)
│
└── Library/                    # Symlinked to ~/Library/ (macOS only)
    └── LaunchAgents/           # Background agents (rclone-mount, smb-media-mount plists)
```

---

## 🚀 Quick Start

### 1. Installation / Bootstrap

Clone the repository and execute the installer:

```bash
git clone https://github.com/dcoffline/dots.git ~/src/dots
cd ~/src/dots
./install.sh
```

**What `./install.sh` does:**
1. **Ensures GNU Stow is installed** via the system package manager (Brew, DNF, APT, or Pacman).
2. **Backs up pre-existing conflicting files**: Scans target locations (`~`, `~/.config`, `~/.local`, and `~/Library` on macOS). If a target file/directory exists and is not already linked to this repository, it is safely moved to `<target>.bak`.
3. **Symlinks dotfiles** using GNU Stow (`home`, `config`, `local`, and `Library` if on macOS).
4. **Executes [`install-pkg.sh`](file:///Users/eric/src/dots/install-pkg.sh)** to install system packages, Rust CLI binaries (using `cargo-binstall`), CascadiaCode Nerd Fonts, Flatpaks, and GNOME Shell extensions.
5. **Configures desktop integrations** (e.g. enabling `logomenu-fixed` GNOME Shell extension).

---

### 2. Clean Uninstallation

If you ever need to remove the Fortress dotfiles and restore your system to its previous state:

```bash
cd ~/src/dots
./uninstall.sh
```

**What [`uninstall.sh`](file:///Users/eric/src/dots/uninstall.sh) does:**
1. **Removes Stow Symlinks**: Executes `stow -D` against `home`, `local`, `config`, and `Library`.
2. **Purges Lingering Symlinks**: Scans target directories and deletes any remaining symlinks that resolve to the `dots` repository.
3. **Restores Backups (`*.bak`)**: Recursively searches for all `<target>.bak` files and directories created during installation and restores them to their original paths.
4. **Cleans Desktop Integrations**: Safely removes injected extensions (e.g., `logomenu-fixed`) from `org.gnome.shell.enabled-extensions`.

---

## 📦 Containerized Services (Podman Quadlets)

Containerized workloads run as user-managed systemd services via Podman Quadlets located in [`config/containers/systemd/`](file:///Users/eric/src/dots/config/containers/systemd/):

| Category | Services |
| :--- | :--- |
| **Media Suite** | **Plex** (+ Zurg WebDAV), **Jellyfin**, **Immich** (Server, Machine Learning, DB, Redis), **Nextcloud** (MariaDB, Redis, Notify-Push), **MediaFlow**, **AioStreams**, **Samba** |
| **AI & Automation** | **Hermes Agent** (Athena), **Open-WebUI**, **Ollama**, **Paperclip**, **Honcho** (App, DB, Redis), **Scriber**, **SearXNG**, **Activepieces** (+ Redis) |
| **Infrastructure & Dashboards** | **Cloudflared** (Zero Trust Tunnels), **Homepage**, **Homarr**, **Vaultwarden**, **Syncthing**, **Open-Terminal**, **ZCC-Webhook**, **PKA-Web** |

Manage Quadlets directly with systemd:
```bash
systemctl --user status <service-name>.service
systemctl --user restart <service-name>.service
```

---

## 🛠️ Maintenance & Common Tasks

The Fortress uses [`just`](file:///Users/eric/src/dots/home/.justfile) as a unified task runner across all platforms:

| Command / Alias | Description |
| :--- | :--- |
| `update` *(or `just update`)* | Pulls latest dots, upgrades system/cargo binaries, dumps Brewfile/GNOME state, re-stows, and commits/pushes snapshot |
| `status` *(or `just status`)* | Colorized health overview of all system and user systemd services with error reporting |
| `rmount` / `rumount` | Mounts / unmounts configured Rclone cloud storage remotes (`just mount` / `just unmount`) |
| `just check-mounts` | Health check watchdog verifying rclone mount responsiveness |
| `just backup-athena` | Comprehensive backup of dev projects, Hermes state, Quadlets, user systemd units, Gemini/AGY, and secrets |
| `just restore-athena` | Interactive disaster recovery restoring from Athena backup snapshots |
| `just backup-nextcloud` | Backs up Nextcloud MariaDB database, configs, and Quadlet definitions |
| `just sync-gdrive` | Bidirectional bisync between local Nextcloud storage and Google Drive |
| `just install-voxtype` | Installs and configures Voxtype push-to-talk voice-to-text (Vulkan GPU/AVX2 on Linux, Cask on macOS) |
| `just install-openwispr`| Downloads and configures OpenWispr speech-to-text service and desktop launcher |
| `just clean-apple [dir]`| Scans and cleans macOS metadata junk (`._*` sidecar files and `.DS_Store`) |

For a complete list of interactive aliases and shortcuts, see the **[CHEATSHEET.md](file:///Users/eric/src/dots/CHEATSHEET.md)**.

