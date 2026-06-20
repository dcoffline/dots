# Workspace Bar

A GNOME Shell extension that replaces the Activities button with workspace buttons showing numbers and application icons in the top panel. Inspired by the workspace workflow of [elementary OS](https://elementary.io/).

## Features

### Workspace Buttons
- Each workspace shows its **number** and **app icons** for all open windows
- **Active workspace** is highlighted with the GNOME accent color border
- Click a workspace to switch to it
- Click the active workspace to toggle the **Activities Overview**
- **Middle-click** any workspace to toggle Overview
- **Scroll wheel** over the bar to cycle through workspaces

### Window Interaction
- Click an **app icon** to focus that window
- If in Overview, clicking an already-focused icon closes Overview; clicking a different icon activates it

### Drag and Drop
- **Drag a window icon** to another workspace button to move the window there
- **Drag between workspaces** (into the gap) to create a **new workspace** with that window
- **Drag a workspace button** onto another to **reorder workspaces**
- Visual insertion indicator when dragging between gaps

### Accent Color Integration
- Active workspace border automatically follows the system accent color (blue, teal, green, yellow, orange, red, pink, purple, slate)

### Preferences
- **Size**: Small, Medium, or Large (controls icon size, font size, spacing, and roundness)
- **Position**: Left, Center, or Right box in the top panel
- **Position Index**: Fine-tune placement within the chosen panel box
- **Left Margin**: Horizontal offset in pixels

## Compatibility

GNOME Shell 45, 46, 47, 48, 49.

## Installation

### From extensions.gnome.org

Visit the [Workspace Bar](https://extensions.gnome.org/extension/workspace-bar/) page and toggle the switch to install.

### Manual

```bash
git clone https://gitlab.com/jguece/workspace-bar.git ~/.local/share/gnome-shell/extensions/workspace-bar@jguece
cd ~/.local/share/gnome-shell/extensions/workspace-bar@jguece
glib-compile-schemas schemas/
```

Log out and back in (Wayland) or restart GNOME Shell with `Alt+F2` → `r` (X11), then enable:

```bash
gnome-extensions enable workspace-bar@jguece
```

## License

This project is licensed under the [GPL-3.0](LICENSE).
