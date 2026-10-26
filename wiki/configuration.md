# Configuration

Everything is in `~/.config/pshell/config.json`. Save the file and the bar updates. You do not need to restart anything.

This page covers the bar itself: where it sits, its size, fonts, colours, spacing, and which widgets go where. Each feature's own settings are on its own page.

## A small config

```json
{
  "position": "top",
  "size": 30,
  "bg": "#1e1e2e",
  "fg": "#cdd6f4",

  "left":   [ { "type": "workspaces" } ],
  "center": [ { "type": "clock", "format": "ddd dd MMM  HH:mm" } ],
  "right":  [
    { "exec": "free -h | awk '/^Mem:/ {print \"mem \" $3}'", "interval": 5 },
    { "exec": "my-battery", "interval": 30, "onClick": "gnome-power-statistics" }
  ]
}
```

The repository has a fuller example in `config.example.json`.

## Sections

The bar has three sections: `left`, `center` and `right`. Each is a list of widgets, drawn in order.

An entry is one of three things:

| Entry | What it is |
|---|---|
| `{ "type": "clock" }` | A built-in widget. See [Widgets](widgets.md). |
| `{ "exec": "date +%H:%M", "interval": 60 }` | A script widget: a command whose output is shown. See [Script widgets](script-widgets.md). |
| `{ "id": "me.gpu" }` | A QML widget from `~/.config/pshell/widgets/`. See [QML widgets](qml-widgets.md). |

Any other key on an entry is a setting for that widget.

## The bar

| Key | What it does | Default |
|---|---|---|
| `position` | `top`, `bottom`, `left` or `right` | `top` |
| `size` | Bar height (or width, when vertical) in pixels | `30` |
| `barIconSize` | Size of icons in the bar, in pixels | 55% of `size` |
| `terminal` | The terminal pshell opens things in. See [below](#terminal). | see below |

`barIconSize` covers the tray, battery and control centre together, so they stay the same size. Icons inside panels size themselves from the font and are not affected. The tray can still override it with its own `iconSize` or `iconScale`.

## Fonts

| Key | What it does | Default |
|---|---|---|
| `font` | Font family for text | `monospace` |
| `fontSize` | Base font size in pixels. Panels scale from this. | `12` |
| `barFontSize` | Size of text in the bar itself. Panels and popouts keep `fontSize`. | `fontSize` |
| `iconFont` | Font for glyph icons | `JetBrainsMono Nerd Font` |

Glyph icons drawn from the Nerd Font in the bar size from `bar.icon-font` under `shell` instead:

```json
{ "barFontSize": 11, "barIconSize": 13, "shell": { "bar.icon-font": 12 } }
```

The control centre and most panels use [Material Symbols](https://fonts.google.com/icons), which pshell ships in `assets/fonts/`. You do not need to install it. See [Theming](theming.md#icons).

## Colours

| Key | What it does | Default |
|---|---|---|
| `bg` | Background | `#1e1e2e` |
| `fg` | Text | `#cdd6f4` |
| `accent` | Highlights and "on" states | `#89b4fa` |
| `dim` | Dimmed text | `#6c7086` |
| `urgent` | Warnings, and things that cannot be undone | `#f38ba8` |

These are the colours used as written. To take colours from your wallpaper instead, set `"theme": "wallpaper"`. Any colour you set here still wins over the wallpaper's. See [Theming](theming.md).

## Spacing

Three distances, each with its own setting:

| Key | What it does | Default |
|---|---|---|
| `gap` | Space between two widgets | `12` |
| `padding` | Space from the bar's edge to the first or last widget | the same as `gap` |
| `margin` | Space from the screen edge to the bar | `0` |

```json
{
  "gap": 6,
  "padding": 4,
  "margin": 8
}
```

A `margin` above zero lifts the bar off the screen edge and rounds its corners. The compositor keeps that space reserved, so a maximised window stops at the margin instead of sliding under it.

A number sets the margin on every side. An object sets only the sides it names, and the rest stay at zero:

```json
{ "margin": { "top": 4, "left": 10, "right": 10 } }
```

Each widget has some padding of its own, which is why the last widget does not touch the bar's edge even with `"padding": 0`. That padding comes from `bar.icon-slot` being wider than `barIconSize`. To make the buttons tighter, override it under `shell`:

```json
{ "shell": { "bar.icon-slot": 20 } }
```

### Corners and panel spacing

| Key | What it does | Default |
|---|---|---|
| `cornerRadius` | Corner rounding of panels, in pixels | Hyprland's `decoration:rounding` |
| `gapsOut` | Space between panels and the screen edge | half of Hyprland's `general:gaps_out` |
| `spacingScale` | Multiplies all spacing inside panels | `1.0` |
| `scaleWithFont` | Whether panel spacing also grows with `fontSize` | `true` |

pshell asks Hyprland for its rounding and gaps, so panels match your windows without extra setup. Set these only if you want something different.

## Style tokens

pshell's look is driven by a set of named style tokens. These are the same token names Omarchy uses, which is what lets Omarchy widgets run here (see [QML widgets](qml-widgets.md#omarchy-widgets)). You can override any token in two places:

- the `shell` object in `config.json`, as in the `bar.icon-slot` example above;
- a `~/.config/pshell/shell.toml` file, in the same format as Omarchy's `shell.toml`.

Most people will not need this. The keys above cover the common cases.

## Terminal

`terminal` is the terminal pshell opens things in. Today that is only the system updater (see [Session](session.md#system-updates)).

```json
{ "terminal": "kitty -1" }
```

It is a program name or a path, followed by any arguments of its own. The arguments are split on spaces and passed straight to the program, not through a shell. There is no quoting, so a path with a space in it will not work.

If you leave it out, pshell uses `$TERMINAL`, then the first of ghostty, kitty, alacritty, foot and wezterm that is installed. A terminal that is not installed is skipped for the next one.

## The settings app writes this file

The settings window (`pshell settings toggle`) saves its changes to `config.json`. So do a few commands, like `pshell wallpaper set` and `pshell theme setScheme`.

The first time this happens, the file is rewritten as two-space JSON. Nothing is lost, since JSON has no comments, but your key order and hand formatting will not survive.

## Where pshell keeps things

| Path | What is in it |
|---|---|
| `~/.config/pshell/config.json` | Your settings |
| `~/.config/pshell/state.json` | Things pshell remembers for itself: pinned audio devices, the settings window's last page and size, the weather's resolved coordinates |
| `~/.config/pshell/widgets/` | Your QML widgets |
| `~/.config/pshell/templates/` and `templates.json` | Your own theme templates |
| `~/.config/pshell/shell.toml` | Optional style token overrides |
| `~/.local/state/pshell/` | Clipboard history, notification history, the last weather reading, AI usage records |
| `~/.cache/pshell/` | Wallpaper thumbnails, and copies of QML widgets loaded on Qt 6.12 and later |

The settings app's About page shows the paths of `config.json` and `state.json`, along with the theme, colour scheme and font in use.
