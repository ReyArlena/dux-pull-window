# Dux Shell Plugin: Pull Window

[Dux Shell](https://github.com/duxlabs-dev/dux-shell) launcher plugin that finds an open window and
pulls it onto the workspace you are on, on Hyprland or Sway. The opposite of sending the active
window away with SUPER + SHIFT + number.

Type the trigger, then part of a window title or app name:

```
:pw              every open window, most recently used first
:pw firefox      Firefox windows
:pw gh pr        windows whose class or title matches "gh" then "pr"
```

Choosing a window moves it to the workspace you are on and focuses it, without switching to the
window's own workspace, so it also works for windows on headless or virtual outputs you cannot
see. On Hyprland that is the active workspace of the focused monitor, or its special workspace
(scratchpad) when one is open there. Choosing a window that is already there just focuses it.

The list follows the compositor's window events, so new and closed windows show up straight away.
With nothing typed, windows are in most recently used order (on Sway, from when the plugin loaded;
before that, in Sway's own focus order).

Handy for getting windows onto a headless or virtual output, such as a Sunshine streaming display.

## Requirements

- Dux Shell 2.0.0 or newer
- Hyprland 0.55 or newer with a Lua config (`hyprland.lua`; the plugin moves windows with the Lua
  dispatcher syntax) and `jq`, or
- Sway (uses `swaymsg`)

A startup check verifies the compositor, the tools and the Hyprland version when the plugin is
enabled; it does not check for a Lua config.

## Install

```bash
git clone https://github.com/ReyArlena/dux-pull-window ~/.config/dms/plugins/dux-pull-window
dms ipc call plugin-scan scan
dms ipc call plugins enable pullWindow
```

## Configuration

DMS Settings → Plugins → Pull Window:

- **Trigger** - launcher prefix, default `:pw`. Applied with Save or Enter.

## License

MIT
