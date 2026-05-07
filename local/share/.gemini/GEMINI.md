# Global Personal Memory

- **Configuration Directories**: Always use XDG standard paths. Store all Gemini global personal memory files and rules in `~/.local/share/.gemini` rather than `~/.gemini`.

## Shell Configuration
- When configuring Zsh to use system-wide settings, source `/etc/profile.d/*.sh` scripts using `emulate sh` rather than sourcing `/etc/bashrc` directly. This avoids Bash-specific syntax errors and prompt incompatibilities.

Example snippet for `.zshrc`:
```zsh
if [[ -d /etc/profile.d ]]; then
  for i in /etc/profile.d/*.sh(N); do
    if [[ -r "$i" ]]; then
      emulate sh -c "source '$i'"
    fi
  done
  unset i
fi
```

## Behavioral Mandates
- **Clean Home Policy:** Gemini CLI configuration and memory are stored in `~/.local/share/.gemini`. The `GEMINI_CLI_HOME` environment variable should be set to `$XDG_DATA_HOME`.
- **Automatic Documentation:** At the end of every conversation, automatically create or update a `GEMINI.md` file in the root of the project. This file must summarize the project's purpose, architecture, recent changes made during the session, and notes for future development.
- **Proactive Memory Management:** Always suggest adding to Global Personal Memory in addition to the project-specific `GEMINI.md` when the information has cross-project utility.

- **XDG Compliance:** Always prioritize and respect XDG Base Directory specifications (e.g., `~/.config` for config, `~/.local/share` for data, `~/.cache` for cache) when configuring new tools, moving files, or managing environment variables to keep the home directory clean.
