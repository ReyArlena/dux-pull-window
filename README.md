# Dux Shell Plugin: Pull Window

[Dux Shell](https://github.com/duxlabs-dev/dux-shell) launcher plugin that finds an open window and
pulls it onto the workspace you are on. The opposite of sending the active window away with
SUPER + SHIFT + number.

Type the trigger, then part of a window title or app name:

```
:pw              every window not on this workspace, most recently used first
:pw firefox      Firefox windows
:pw gh pr        windows whose class or title matches "gh" then "pr"
```

Choosing a window moves it to the active workspace of the focused monitor (the one under the mouse,
where the launcher opens) and focuses it. If a special workspace (scratchpad) is open there, the
window goes onto that instead.

Handy for getting windows onto a headless or virtual output, such as a Sunshine streaming display.

## Requirements

- Dux Shell 2.0.0 or newer
- Hyprland (uses `hyprctl`)
- `jq`

A startup check verifies these when the plugin is enabled.

## Install

```bash
git clone https://github.com/ReyArlena/dux-pull-window ~/.config/dms/plugins/dux-pull-window
dms ipc call plugin-scan scan
dms ipc call plugins enable pullWindow
```

## Configuration

DMS Settings → Plugins → Pull Window:

- **Trigger** - launcher prefix, default `:pw`.

## License

MIT
