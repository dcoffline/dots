# Starship Configuration

## Purpose
This directory contains the Starship prompt configuration files for the project.

## Architecture
- `starship.toml`: The primary configuration file used by the shell.
- `starship_titus.toml`: An alternative configuration (likely based on Titus's setup).

## Recent Changes
- **macOS Indicator**: Added a macOS indicator (Apple logo) to the Starship prompt, integrated into the same segment as the container indicator for visual consistency across different environments.
- **Two-Line Prompt Implementation**: Modified the configuration to a two-line layout. The status bar remains on the first line, with the command prompt (`$character`) moved to the second line to provide more typing space.
- **Git Branch Color Update**: Changed the `git_branch` text color to `#3B4252` (dark gray/blue) to improve readability on the cyan background (`#86BBD8`).
- **Git Status Preservation**: Kept the `git_status` color as `red` as per user preference.
- **Bold Git Status Symbols**: Added `bold` formatting to the `git_status` style in `starship.toml` for better visibility of warning symbols.
- **Config Fix**: Removed invalid OS symbol definitions (symbol1, symbol2, etc.) from the `[os.symbols]` section in `starship.toml` that were causing startup warnings. Attempted to add `BlackArch` but removed it as it's not a recognized variant in the `[os.symbols]` module.
- **2D OS Emblems**: Replaced emoji-based OS symbols (like 🐧, 🍎, 🎩, 🎯) with modern 2D emblems from Nerd Fonts (, , , ) for a cleaner, more consistent visual style across Linux distributions and macOS.

## Future Notes
- Any future color adjustments should consider the Nord-inspired palette already in use (`#3B4252`, `#434C5E`, `#4C566A`, etc.).
