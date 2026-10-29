# 🛡️ The Fortress — Multi-OS Dotfiles & Homelab Stack

An XDG-compliant, modular Bash environment and containerized homelab architecture tailored for **macOS**, **immutable Linux** (Bazzite, Fedora Silverblue), **mutable Linux** (Fedora, Debian/Ubuntu, Arch), and **WSL**.

---

## 🌟 Key Highlights

- **Pure Bash Modular Shell**: Fast, clean, unified configuration loaded from `~/.config/bash/` across all platforms.
- **GNU Stow Management**: Clean symlinking organized into modular packages (`home`, `config`, `local`, and macOS `Library`).
- **Idempotent Installation & Backup**: Automatically detects pre-existing conflicting configurations and backs them up to `*.bak` before symlinking.
- **Complete Uninstall Routine**: Safe, clean teardown via [`uninstall.sh`](uninstall.sh) that unstows packages, cleans lingering symlinks, and restores original `*.bak` configurations.
- **Environment & Distrobox Aware**: Automatically detects host vs container environments, immutable vs mutable systems, macOS vs Linux, and desktop environments (KDE Plasma vs GNOME).
- **Consolidated Homebrew & Native Package Automation**: Unified package management on macOS and Linuxbrew (`Brewfile`) for CLI tools, fast binary bottles, standalone Linux services (Jottacloud), Flatpaks, and selective Cargo/npm tools—eliminating unnecessary containerized binary wrappers.
- **Transparent Secrets Management & Pre-Push Guards**: Encrypted with **`git-crypt`** for sensitive credentials (`home/.secrets`, per-container `local/share/**/*.env`) backed by an automated pre-push security scanner and Stow link-integrity checker.
- **Justfile Automation**: Comprehensive task runner managing updates, rclone mounts, disaster recovery backups (Athena, Immich, Honcho, Nextcloud), voice-to-text engines, and systemd monitoring.
- **Podman Quadlet & AI Development Suite**: Production-ready, systemd-managed rootless container suite featuring autonomous AI agent environments (Athena/Hermes, Honcho, Odysseus, Vane, FreeLLMAPI).

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
│   ├── .bash_profile           # Login shell profile
│   ├── .justfile               # Task runner recipes (status, update, mount, backup-athena, etc.)
│   └── .secrets                # Encrypted credentials & API tokens (git-crypt encrypted)
│
├── config/                     # Symlinked to ~/.config/
│   ├── bash/                   # Modular bash files (alias.bash, function.bash, os.bash, path.bash)
│   ├── containers/             # Rootless container management
│   │   ├── systemd/            # Active Podman Quadlet definitions (.container, .network)
│   │   └── archive/            # Archived/legacy container definitions (Plex, Zurg, Samba, etc.)
│   ├── systemd/user/           # User-level systemd service units & timers (.service, .timer)
│   ├── environment.d/          # Global environment definitions (envvars.conf)
│   ├── dconf-backups/          # GNOME Shell and TilingShell dconf dumps
│   └── atuin/, autostart/, btop/, fastfetch/, ghostty/, micro/, nvim/, rclone/, searxng/,
│       starship.toml, sunshine/, voxtype/, waveterm/, yazi/
│
├── local/                      # Symlinked to ~/.local/
│   ├── bin/                    # Custom executables & wrappers (athena, gods-eye-view, monctl, rmount, etc.)
│   └── share/                  # App data (Homepage dashboards, GNOME shell extensions, bash-preexec)
│
├── Library/                    # Symlinked to ~/Library/ (macOS only)
│   └── LaunchAgents/           # Background agents (com.eric.rclone-mount.plist)
│
└── archive/                    # Archived legacy scripts and macOS LaunchAgents
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
4. **Executes [`install-pkg.sh`](install-pkg.sh)** to install system packages, Rust CLI binaries (using `cargo-binstall`), CascadiaCode Nerd Fonts, Flatpaks, and GNOME Shell extensions.
5. **Configures desktop integrations** (e.g. enabling `logomenu-fixed` GNOME Shell extension).

---

### 2. Clean Uninstallation

If you ever need to remove the Fortress dotfiles and restore your system to its previous state:

```bash
cd ~/src/dots
./uninstall.sh
```

**What [`uninstall.sh`](uninstall.sh) does:**
1. **Removes Stow Symlinks**: Executes `stow -D` against `home`, `local`, `config`, and `Library`.
2. **Purges Lingering Symlinks**: Scans target directories and deletes any remaining symlinks that resolve to the `dots` repository.
3. **Restores Backups (`*.bak`)**: Recursively searches for all `<target>.bak` files and directories created during installation and restores them to their original paths.
4. **Cleans Desktop Integrations**: Safely removes injected extensions (e.g., `logomenu-fixed`) from `org.gnome.shell.enabled-extensions`.

---

## 📦 Containerized Services (Podman Quadlets & Distrobox)

Containerized workloads run as user-managed systemd services via Podman Quadlets located in [`config/containers/systemd/`](config/containers/systemd/), complemented by dedicated Distrobox containers for specialized AI workflows:

| Category | Active Services | Description |
| :--- | :--- | :--- |
| **Media Suite** | **Jellyfin** | Media streaming server (`jellyfin`) with hardware acceleration |
| | **AioStreams** | Fast streaming middleware & add-on manager |
| | **MediaFlow** | Media proxy and stream flow controller |
| | **Threadfin** | M3U / XMLTV proxy and channel manager for live TV |
| | **Immich** | Self-hosted photo/video backup suite (`immich`, `immich-db`, `immich-ml`, `immich-redis`) |
| | **Nextcloud** | Cloud storage & collaboration suite (`nextcloud`, `nextcloud-db`, `nextcloud-redis`, `nextcloud-notify-push`, `collabora`) |
| **AI & Automation** | **Athena / Hermes** | Autonomous AI agent environment in dedicated **Distrobox** container (`athena`), launched via host wrappers (`athena`, `thena`, `hermes`) |
| | **Hermes Studio** | Web UI & management console for Hermes agent workflows |
| | **Honcho** | Cognitive memory engine for AI agents (`honcho`, `honcho-db`, `honcho-redis`) |
| | **Odysseus & Vane** | Specialized AI conversational & routing engines |
| | **FreeLLMAPI** | LLM API proxy and virtualization layer |
| | **Ollama** | Local LLM inference engine with AMD ROCm / Vulkan acceleration |
| | **SearXNG & Relay** | Privacy-respecting metasearch engine with relay proxy |
| | **Open-WebUI** | Full-featured conversational frontend for local and remote models |
| | **Open-Terminal** | Containerized web terminal utility |
| | **PKA-Web** | Personal Knowledge Architecture web interface |
| | **Open-SEO** | Search engine optimization & DataForSEO query tool |
| | **ZCC-Webhook** | Webhook integration receiver for external event automation |
| **Infrastructure** | **Cloudflared** | Zero Trust encrypted ingress tunnels connecting homelab services |
| | **Homepage** | Unified dashboard organizing homelab services, bookmarks, and metrics |
| | **Shlink** | Self-hosted URL shortener with REST API (`shlink`, `shlink-db`, `shlink-webui`) |
| | **Vaultwarden** | Bitwarden-compatible lightweight credential vault |
| | **Syncthing** | Continuous peer-to-peer folder synchronization |

> [!NOTE]
> **Archived Containers**: Legacy service definitions (Plex, Zurg, Samba, Homarr, Paperclip, Scriber, Activepieces, standalone Jellyfin) are preserved in [`config/containers/archive/`](config/containers/archive/) for reference and rollback.

Manage Quadlets directly with systemd:
```bash
systemctl --user status <service-name>.service
systemctl --user restart <service-name>.service
```

---

## 🎮 Desktop & Gaming Helpers (`local/bin/`)

The [`local/bin/`](local/bin/) directory contains custom scripts stowed directly into `$HOME/.local/bin/`:

| Script | Purpose |
| :--- | :--- |
| `athena` / `thena` | Interactive chat and shorthand (`-z`) launcher for the containerized Hermes agent |
| `hermes` | Distrobox execution wrapper seamlessly bridging host shell and the `athena` container |
| `gods-eye-view` | Management script and application launcher for the God's Eye View intelligence console |
| `monctl` | Resolution and refresh rate switcher for Sunshine / Moonlight streaming sessions |
| `lutris-fullscreen` | Helper forcing borderless fullscreen on Lutris and Ubisoft Connect titles |
| `stremio-steam-fullscreen` | Launches Stremio flatpak forced into fullscreen for Steam Big Picture / Moonlight |
| `stremio-web-fullscreen` | Launches Stremio Chrome web app in fullscreen mode for Moonlight streaming |
| `dpon` / `dpoff` | Multi-OS monitor power state and virtual display (BetterDisplay/Wayland) toggle utilities |
| `sunshine-wait-display` | Waits and ensures virtual / remote display is active before Sunshine streaming starts |
| `touchup` | Display geometry, scaling, and Sunshine virtual display alignment utility |
| `osk` | On-screen keyboard toggle helper for handheld / remote desktop sessions |
| `dock` | Display dock state manager and screen reconfiguration utility |
| `voxtype-clean` | Post-processing pipeline routing speech-to-text transcripts through local Ollama LLMs |
| `wave` | Launches Wave terminal configured for Wayland / XWayland transparent rendering |
| `zcc_webhook_watch.sh` | Health watchdog for the ZCC webhook unit and tunnel, managed by systemd timer |
| `rmount` | Helper wrapper around `just mount` for cloud storage remotes |
| `gdmreset` | Restarts the Display Manager session |
| `browsh` | Terminal web browser wrapper |

---

## 🔐 Secrets & Security Architecture

The Fortress implements a defense-in-depth security model combining encrypted repositories, scoped per-service configurations, and automated git pre-push gates:

- **Transparent Encryption with `git-crypt`**:
  - `home/.secrets` (general environment secrets)
  - `local/share/**/*.env` (isolated per-service container environments, e.g. Immich, Nextcloud-DB, AioStreams, Open-SEO, FreeLLMAPI)
  - `*.secret` files
- **Per-Service Secret Isolation**: Container-specific tokens and database passwords have been decoupled from a single monolithic file into individual, service-scoped `.env` files tracked under `local/share/`.
- **Pre-Push Security Scanner**: A Git pre-push hook scans outgoing commit ranges for plaintext credential patterns, API tokens, and ensures all secrets-class files are encrypted before pushing to GitHub.
- **Symlink Integrity Guard**: A pre-push hook (`check_links.sh`) validates that all active symlinks cleanly point into the `dots` repository without dangling references.
- **Unlocking Repository**: After cloning on a new machine, unlock secrets using your GPG key or symmetric key:
  ```bash
  git-crypt unlock /path/to/git-crypt-key
  ```

---

## 🛠️ Maintenance & Common Tasks

The Fortress uses [`just`](home/.justfile) as a unified task runner across all platforms:

| Command / Alias | Description |
| :--- | :--- |
| `update` *(or `just update`)* | Pulls latest dots, upgrades system/cargo binaries, dumps Brewfile/GNOME state, re-stows, and commits/pushes snapshot |
| `status` *(or `just status`)* | Colorized health overview of all system and user systemd services with error reporting |
| `mount` / `unmount` | Mounts / unmounts configured Rclone cloud storage remotes (`just mount` / `just unmount`) |
| `just check-mounts` | Health check watchdog verifying rclone mount responsiveness and auto-recovering hangs |
| `just backup-athena` | Comprehensive backup of dev projects, Hermes state, Quadlets, user systemd units, Gemini/AGY, and secrets |
| `just restore-athena` | Interactive disaster recovery restoring from Athena backup snapshots |
| `just backup-nextcloud` | Backs up Nextcloud MariaDB database, configs, and Quadlet definitions |
| `just sync-gdrive` | Bidirectional bisync between local Nextcloud storage and Google Drive |
| `just resync-gdrive` | Recovery / initial synchronization of Google Drive with Nextcloud Documents |
| `just install-voxtype` | Installs and configures Voxtype push-to-talk voice-to-text (Vulkan GPU/AVX2 on Linux, Cask on macOS) |
| `just install-openwispr`| Downloads and configures OpenWispr speech-to-text service and desktop launcher |
| `just install-agy` | Installs or updates the Google Antigravity CLI |
| `just clean-apple [dir]`| Scans and cleans macOS metadata junk (`._*` sidecar files and `.DS_Store`) |

For a complete list of interactive aliases and shortcuts, see **[CHEATSHEET.md](CHEATSHEET.md)**.
