# just-tui

A linutil-style (Chris Titus) ratatui TUI for browsing and running recipes from a
justfile — built for Eric's `~/.justfile` (dotfiles maintenance menu).

## Layout

- **Left pane**: section tabs, parsed from the justfile's `# TITLE` separator
  blocks (`# ====...` / `# SECTION NAME` / `# ====...`).
- **Right pane**: recipes in the selected section with their doc comments.
- **Preview pane** (bottom right): raw recipe source via `just --show <recipe>`.

## Keybindings

| Key | Action |
|---|---|
| `j` / `Down`, `k` / `Up` | Move selection |
| `Tab` / `Shift-Tab` | Cycle sections |
| `Enter` | Run recipe (goes through confirm prompt) |
| `/` | Open search filter across all recipes |
| `Esc` | Cancel search / confirm; otherwise quit |
| `q` | Quit |
| `y` / `n` | Confirm / cancel execution |
| `Ctrl-C` (run view) | Kill the running recipe |
| `Enter` (run view) | Close run view back to menu |

## Safety

Every recipe requires an explicit `y/n` confirmation before execution. There is
no skip-confirmation flag. Recipes with parameters prompt for each argument
first (one input row per param).

## Execution

Recipes spawn `just <name> <args>` inside a real PTY (`portable-pty`), output
streams live into the run view, and a SUCCESS/FAILED banner shows on exit.
Ctrl-C kills the child; Enter closes back to the menu.

## Usage

```sh
just-tui                        # use ~/.justfile
just-tui --justfile ~/src/dots/home/.justfile
just-tui --print-parse          # headless test: print section->recipe tree
```

## Build

```sh
cargo build --release
```

Works on Bazzite/Fedora and macOS. Requires `just` on PATH.

## Install as `just tui` recipe

Add to `~/.justfile` (see `just-recipe.stub`):

```just
# Launch the just-tui recipe browser
tui:
    @~/src/projects/just-tui/target/release/just-tui --justfile "{{justfile()}}"
```

## Notes

- Sections are parsed directly from disk (grouping never relies on `just --list`);
  `just --show` is used only for previews.
- `just --list --list-heading ""` output is available in code (`runner::list_recipes`)
  but the tree itself comes from the on-disk parse.
- just 1.21.0 has no `--list-submodule-aligned`; not needed here.
