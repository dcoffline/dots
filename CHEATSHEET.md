# 🛡️ The Fortress: Chezmoi Cheat-Sheet

## 🚀 Initial Bootstrap
On any new machine (Host or Container), simply run:
```bash
./install.sh
```
This script will:
1. Install `chezmoi`.
2. Initialize the repository.
3. Automatically run package managers (Brew/DNF/Cargo) based on the environment.

---

## 🛠️ Ongoing Maintenance

### 🔄 The "Everything" Update
To update all binaries (Host & Container), dump current GNOME/Brew state, and sync to GitHub:
```bash
update
```
*(This is an alias for `~/.local/bin/update`)*

### 📝 Editing Configs
Always use these aliases to ensure changes are tracked in the repo and applied to your home directory:
*   `ebrc`: Edit `.bashrc`
*   `esrc`: Edit `.shellenv`
*   `efun`: Edit `.functions`

*Note: These will automatically run `chezmoi apply` and `source` the file upon exit.*

### ➕ Adding New Files
To start tracking a new file in your home directory:
```bash
chezmoi add ~/.path/to/file
```

---

## 🏗️ Architecture Reference

| Component | Location | Purpose |
| :--- | :--- | :--- |
| **Source Repo** | `~/src/gh/dcoffline/dots` | Where your files *actually* live. |
| **Applied Files** | `~/*` | What your system *actually* uses. |
| **Config Logic** | `.chezmoi.toml.tmpl` | Handles environment detection (Host vs Container). |
| **Install Logic**| `run_onchange_install-packages.sh.tmpl` | The "brains" of the package installation. |
| **Entry Points** | `dot_bashrc`, `dot_profile` | Stubs that load the real config from `.config/bash/`. |

---

## 💡 Pro-Tips
*   **Dry Run:** See what `chezmoi apply` would do without doing it: `chezmoi diff`
*   **Manual Apply:** If you edit files directly in the repo, run: `chezmoi apply`
*   **Secret Sauce:** Your `~/.secrets` file is ignored by Git but managed by Chezmoi as `dot_secrets`. Use it for API keys and tokens.
