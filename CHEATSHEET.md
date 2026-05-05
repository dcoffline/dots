# 🛡️ The Fortress: Chezmoi Cheat-Sheet

## 🚀 Initial Bootstrap
On any new machine (Host or Container), simply run:
```bash
./install.sh
```
This script will:
1. Install `stow`.
2. Initialize the repository.
3. Automatically run package managers (Brew/DNF/Cargo) based on the environment.

---

## 🛠️ Ongoing Maintenance

### 🔄 The "Everything" Update
To update all binaries (Host & Container), dump current GNOME/Brew state, and sync to GitHub:
```bash
update
```
*(This is a call to `~/.local/bin/update` which is on the PATH)*

### 📝 Editing Configs
Always use these aliases to ensure changes are tracked in the repo and applied to your home directory:
*   `ebrc`: Edit `.bashrc`
*   `esrc`: Edit `.shellenv`
*   `efun`: Edit `.functions`

*Note: These will automatically run `gitupdate` and `source` the file upon exit.*

---

## 🏗️ Architecture Reference

| Component | Location | Purpose |
| :--- | :--- | :--- |
| **Source Repo** | `~/src/gh/dcoffline/dots` | Where your files *actually* live. |
| **Applied Files** | `~/*` | What your system *actually* uses. |
| **Config Logic** | `install.sh` and `update`  | Handles environment detection (Host vs Container). |
| **Entry Points** | `~/.bashrc`, `~/.profile` | Stubs that load the real config from `~/.config/bash/`. |
