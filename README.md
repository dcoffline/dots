# 🛡️ The Fortress — Dotfiles & Homelab Stack

A modular Bash environment, GNU Stow symlink management, and Podman Quadlet homelab definitions. Targets **macOS**, **immutable Linux** (Bazzite, Silverblue; Linuxbrew-based), and **mutable Linux** (Fedora, Debian/Ubuntu, Arch).

---

## Layout

Each top-level package is stowed into a fixed target. Nothing else in the repo is linked.

```
~/src/dots/
├── install.sh / uninstall.sh   Bootstrap and reverse (see below)
├── install-pkg.sh              Package and app installer (skipped with --no-apps)
├── Brewfile                    Homebrew packages (macOS, Linuxbrew)
├── CHEATSHEET.md               Aliases and command reference
├── GEMINI.md                   Agent-facing notes on this repo
├── .githooks/                  pre-push secret scan and symlink check (opt-in, see Security)
│
├── home/        → ~/           .bashrc, .bash_profile, .justfile, .secrets (git-crypt)
├── config/      → ~/.config/   bash/, just/ modules, environment.d/, systemd/user/,
│                               ghostty/, kitty/, nvim/, sunshine/, yazi/, ...
├── local/       → ~/.local/    bin/ (helper scripts), share/ (app data; *.env is git-crypt)
├── Library/     → ~/Library/   macOS only: LaunchAgents/
│
├── containers/  → ~/.config/containers/   opt-in with --containers
│   ├── systemd/                Active Quadlets, grouped by stack (ai/, content/, hermes/,
│   │                           homelab/, immich/, jellyfin/, nextcloud/, shlink/) plus
│   │                           top-level open-seo, syncthing, vaultwarden
│   └── archive/                Retired Quadlets kept for rollback (not stowed as active)
│
└── archive/                    Old scripts and LaunchAgents, not linked
```

---

## Toolchain: Homebrew First

Host CLI tools, including the Rust and Go binaries, come from the `Brewfile`. There is no cargo or rustup step. The Rust toolchain is `brew "rust"`, and the CLI tools that used to be built with cargo are Homebrew formulas. The Brewfile is the one list to edit.

- In Distrobox containers, `/home` is mounted from the host, so `/home/linuxbrew/.linuxbrew/bin` is on `PATH` in every container. Containers run the host's Homebrew binaries directly. There are no per-container copies and no `distrobox-export` wrappers for CLI tools.
- Distrobox stays for environments that need their own distro userland, such as the `athena` container that runs Hermes.
- `install-pkg.sh` still installs dnf/apt package lists on non-Homebrew hosts. Those lists are the only place packages live outside the Brewfile.

## Install

```bash
git clone https://github.com/dcoffline/dots.git ~/src/dots
cd ~/src/dots
./install.sh              # full install
./install.sh --containers # also link Quadlets into ~/.config/containers
./install.sh --no-apps    # stow symlinks only; skip package installs
```

What `install.sh` does, in order:

1. **Ensures GNU Stow** via brew, dnf, apt, or pacman.
2. **Backs up conflicts.** Any existing file or directory at a target path that is not already a link into this repo is moved to `<path>.bak`.
3. **Stows** `home`, `local`, and `config` into `~`, `~/.local`, and `~/.config`. With `--containers` it also stows `containers/`. Without it, container links left by an earlier run are removed. On macOS it also stows `Library/`.
4. **Runs `install-pkg.sh`** unless `--no-apps` is set. That covers the Brewfile, dnf/apt package lists on non-Homebrew hosts, Nerd Fonts, Flatpaks, the standalone Jottacloud CLI (`~/.local/bin`), and, on GNOME hosts only, the GNOME extension list and the dconf dump in `config/dconf-backups/`.

The install is idempotent: a second run leaves the same links and backups in place.

---

## Uninstall

```bash
cd ~/src/dots
./uninstall.sh
```

Reverses everything `install.sh` does to your home directory:

1. Runs `stow -D` for every package, including `containers` and, on macOS, `Library`.
2. Removes any remaining symlink that points into the repo, including links to files since deleted from the repo.
3. Removes legacy macOS voxtype and ghostty links from earlier installs.
4. Restores every `*.bak` to its original path. If a path has been replaced by something that is not a repo link, the uninstaller leaves the `.bak` in place and prints a warning rather than deleting anything.
5. Removes directories the installer created, but only if they are empty.

**Not reverted** (system-wide installs; not tracked by stow): packages from brew/dnf/apt/pacman, Flatpak apps, the Jottacloud CLI and its yum/apt repo and GPG key entries, Nerd Fonts, GNOME extensions, and dconf settings. Remove those by hand if you want them gone.

---

## Containers (Podman Quadlets)

Quadlets are stowed into `~/.config/containers/systemd` with `--containers` and run as user systemd units. Manage them with:

```bash
systemctl --user status <name>.service
systemctl --user restart <name>.service
```

| Stack | Active services | Location |
| :--- | :--- | :--- |
| **Media** | Jellyfin, MediaFlow | `jellyfin/` |
| **Photos & Files** | Immich (`immich`, `-db`, `-ml`, `-redis`); Nextcloud (`nextcloud`, `-db`, `-redis`, `-notify-push`, Collabora) | `immich/`, `nextcloud/` |
| **Documents & Finance** | Paperless-ngx (with Gotenberg, Tika, Redis); Actual Budget; Homebox | `content/` |
| **AI** | Ollama (ROCm); Open WebUI; SearXNG + relay; Vane; FreeLLMAPI; Open-Terminal; Open-SEO | `ai/`, top-level `open-seo` |
| **Agent memory & webhooks** | Honcho (`honcho`, `-db`, `-redis`); ZCC webhook | `hermes/` |
| **Infrastructure** | Cloudflared tunnel; Homepage dashboard; OpenAI-Edge-TTS; Shlink (`shlink`, `-db`, `-webui`); Vaultwarden; Syncthing | `homelab/`, `shlink/`, top-level |

Athena/Hermes is not a Quadlet. It runs in the `athena` Distrobox container and is launched from the host with the `athena`, `thena`, and `hermes` wrappers in `local/bin/`.

> [!NOTE]
> **Archived** (in `containers/archive/`, not active): Plex, Zurg, Samba, Kiwix, Prowlarr, Seerr, Homarr, FlareSolverr, ChromaDB, Activepieces, AIOMetadata, AIOStreams, Comet, MediaFusion, Odysseus, Paperclip, PKA-Web, Quartz, Remux, Scriber, Scrob, Threadfin, and the old standalone Hermes.

---

## Helper Scripts (`local/bin/`)

Stowed into `~/.local/bin/`.

| Script | Purpose |
| :--- | :--- |
| `athena`, `thena`, `hermes` | Launch Hermes in the `athena` Distrobox. `athena` runs a chat; `thena` runs the shorthand form; `hermes` is the raw wrapper. |
| `strm-resolver` | Resolves Stremio IDs to debrid stream URLs through AIOStreams (port 8098) |
| `strm-sync` | Builds `.strm` and `.nfo` files for Jellyfin from AIOMetadata catalogs |
| `gdmreset`, `wave`, `browsh` | Display-manager restart, Wave terminal, Browsh |
| `loginctl` | Shim that no-ops on macOS and passes through to `/usr/bin/loginctl` elsewhere |
| `natscroll` | macOS helper |

---

## Security

- **git-crypt** encrypts `home/.secrets`, `local/share/**/*.env`, and `*.secret`. After cloning on a new machine: `git-crypt unlock <key-file>`.
- **`.gitignore`** blocks credential-shaped files such as `config/rclone/rclone.conf`.
- **Pre-push hook** (`.githooks/pre-push`) runs `secret_scan.py` and `check_links.sh`. Git does not run it by default. Enable it once per clone:
  ```bash
  git config core.hooksPath .githooks
  ```

---

## Maintenance

`just` is the task runner. Recipes live in `home/.justfile`, with modules in `config/just/`.

| Command | Description |
| :--- | :--- |
| `just update` | Pull, upgrade packages (Brewfile), and re-stow |
| `just status` | Health overview of system and user systemd services |
| `just mount` / `just unmount` | Mount and unmount configured rclone remotes |
| `just check-mounts` | Watchdog that checks rclone mounts and recovers hung ones |
| `just backup-athena` / `just restore-athena` | Back up and restore Athena state, Quadlets, user units, and secrets |
| `just backup-nextcloud` | Back up the Nextcloud database, config, and Quadlets |
| `just sync-gdrive` / `just resync-gdrive` | Bisync Nextcloud with Google Drive, or do a one-time re-sync |
| `just install-openwispr` | Install OpenWispr speech-to-text and its desktop launcher |
| `just install-agy` | Install or update the Google Antigravity CLI |
| `just clean-apple [dir]` | Remove macOS `._*` and `.DS_Store` junk |

For interactive aliases and shortcuts, see **[CHEATSHEET.md](CHEATSHEET.md)**.
