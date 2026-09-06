# 🛡️ The Fortress: Cheat Sheet

Quick reference for everyday commands, aliases, container shortcuts, and system maintenance tasks.

---

## 🚀 Bootstrap & Uninstallation

| Action | Command | Details |
| :--- | :--- | :--- |
| **Install / Bootstrap** | `./install.sh` | Installs Stow, backs up conflicting files to `*.bak`, symlinks dotfiles, and executes `install-pkg.sh` |
| **Clean Uninstall** | `./uninstall.sh` | Unlinks all Stow packages, cleans lingering symlinks, removes custom GNOME extensions, and restores `*.bak` backups |

---

## 🛠️ Ongoing Maintenance & System Status

| Command / Alias | Target | Description |
| :--- | :--- | :--- |
| `update` | `just update` | Complete maintenance: Git pull, package upgrades (Brew/DNF/APT/Pacman/Cargo), state dump (Brewfile/dconf), re-stow, and Git push snapshot |
| `status` | `just status` | Visual health check of system & user systemd units with failed service diagnostics |
| `dots` | `cd $DOTS` | Jump directly to dotfiles repository (`~/src/dots`) |
| `dotup "<msg>"` | Custom function | Stages all changes in `$DOTS`, commits with timestamp or message, and pushes to GitHub |
| `gitup "<msg>"` | Custom function | Stages all changes in current repo, commits with timestamp or message, and pushes |

---

## 📝 Config Editing & Live Reload

Editing aliases automatically save, source the changes immediately into the current shell, and commit/push to GitHub:

| Edit Command | Target Config File | Reload Only (No Edit) |
| :--- | :--- | :--- |
| `ebrc` | `home/.bashrc` | `sbrc` |
| `eali` | `config/bash/alias.bash` | `sali` |
| `efun` | `config/bash/function.bash` | `sfun` |

---

## ⚡ `just` Task Runner Reference

Run `just` with no arguments to list all available recipes, or run any of the following:

```bash
# System & Maintenance
just status                          # Health report on systemd host and user services
just update                          # Full Fortress maintenance protocol (update, sync, push)
just rounded-blur                    # Rebuilds gnome-rounded-blur library via Fedora container

# Cloud Storage (Rclone)
just mount                           # Mounts cloud storage remotes (macOS & Linux auto-aware)
just unmount                         # Gracefully stops all rclone mounts & clears PIDs
just check-mounts                    # Health check watchdog verifying rclone mount responsiveness
just sync-gdrive                     # Bidirectional bisync between local Nextcloud & Google Drive
just resync-gdrive                   # Force initial / recovery bisync with Google Drive

# Backups & Disaster Recovery
just backup-athena [target_dir]      # Snapshot dev projects, Hermes state, Quadlets, units, Gemini, secrets
just restore-athena [backup_path]    # Interactive snapshot restoration (defaults to latest)
just backup-nextcloud                # Dumps MariaDB, config directory, and Quadlet definitions

# Development & Speech Tools
just install-voxtype                 # Installs Voxtype push-to-talk voice-to-text (GPU/CPU on Linux, Cask on macOS)
just install-openwispr               # Installs OpenWispr speech engine, hotkey daemon, and desktop unit
just install-agy                     # Installs Google Antigravity CLI
just clean-apple [target_dir]        # Scans and deletes macOS sidecar files (._*) and .DS_Store
```

---

## ☁️ Cloud Storage (Rclone) Shortcuts

| Alias | Underlying Command | Description |
| :--- | :--- | :--- |
| `rmount` | `just mount` *(or `dhe just mount`)* | Mounts Archive, Backup, GDrive, Nextcloud, OneDrive, Timeline, and Zurg |
| `rumount` | `just unmount` | Unmounts all active rclone endpoints |
| `rlsmount` | `mount \| grep rclone` | Lists currently mounted rclone filesystems |
| `rcheck` | `just check-mounts` | Verifies mount responsiveness and restarts dead mounts |
| `rremount` | `rumount; sleep 3; rmount` | Full remount cycle |
| `rlog` | `tail /tmp/rclone-mount.log` | Displays recent rclone mount activity logs |

---

## 🤖 Podman Quadlets & AI Tools

### Interactive Shells & Access
| Alias | Action |
| :--- | :--- |
| `athena` | Open interactive chat session with Hermes Agent (`hermes chat`) |
| `thena` | Open Hermes chat in headless/raw mode (`hermes chat -z`) |
| `hermes` | Exec into Hermes CLI environment |
| `ollama` | Exec into Ollama CLI environment |
| `nc-occ` | Run Nextcloud `occ` command within container as `www-data` |
| `nc-sql` | Open MariaDB interactive prompt for Nextcloud |
| `nc-redis` | Connect to Nextcloud Redis CLI |
| `immich-sql` | Open PostgreSQL interactive shell for Immich |
| `immich-redis` | Connect to Immich Redis CLI |
| `pshell <name>` | Open `/bin/bash` or `/bin/sh` inside any running container |

### Logs & Diagnostics
| Command | Action |
| :--- | :--- |
| `psl` | Formatted container status table (Name, Status, Ports) |
| `podip <name>` | Inspect and print container IP address |
| `podclean` | Prune all stopped containers, dangling images, networks, and volumes |
| `lzd` | Launch LazyDocker TUI |
| `logs-hermes` / `logs-ollama` / `logs-openwebui` | Tail latest 100 log lines from respective AI services |
| `logs-nc` / `logs-immich` / `logs-tunnel` | Tail latest 100 log lines from Nextcloud, Immich, or Cloudflared |
| `monitor-streams` | Tmux split-screen monitoring `stremthru` and `aiostreams` logs |

---

## 📦 Distrobox & Host Integration

### When Inside a Distrobox Container
- `dhe <command>`: Execute command on the host (`distrobox-host-exec`)
- `dex <app>`: Export container application desktop entry to host (`distrobox-export --app`)
- `deb <binary>`: Export container binary to `$HOME/.local/bin` (`distrobox-export --bin`)
- `susc <args>`: Host `sudo systemctl`
- `scu <args>`: Host `systemctl --user`
- `scudr`: Host `systemctl --user daemon-reload`
- `brew`: Call host Homebrew binary

### When On the Host
- `def` / `defr`: Enter Fedora container (user / root)
- `dea` / `dear`: Enter Arch container (user / root)
- `deu` / `deur`: Enter Ubuntu container (user / root)

---

## 📂 Architecture Reference

| Component | Repository Path | Target Location | Purpose |
| :--- | :--- | :--- | :--- |
| **Home Package** | `home/` | `~` | Shell entrypoints (`.bashrc`, `.bash_profile`), `.justfile` |
| **Config Package** | `config/` | `~/.config/` | Shell modules (`bash/`), Quadlets (`containers/systemd/`), systemd units (`systemd/user/`), app configs |
| **Local Package** | `local/` | `~/.local/` | Custom binaries & scripts (`bin/`), extension assets (`share/`) |
| **macOS Library** | `Library/` | `~/Library/` | macOS LaunchAgents (`LaunchAgents/com.eric.*.plist`) |
| **Secrets** | Local only | `~/.secrets`, `~/.config/rclone/rclone.conf` | Sensitive credentials (chmod 600, excluded from Git) |
