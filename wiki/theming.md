# Theming

pshell can take its colours from your wallpaper, and write matching colour files for your terminal, GTK apps and other programs. This page covers how that works, how to hook each app up, and how icons are drawn.

## Colours from the wallpaper

Set `theme` to `wallpaper` and point `wallpaper` at an image:

```json
{
  "theme": "wallpaper",
  "wallpaper": "~/wallpapers/black.jpg",
  "mode": "dark"
}
```

pshell runs [matugen](https://github.com/InioX/matugen) on the image and fills in every colour you have not set yourself. A colour you set still wins, so adding `"accent": "#89b4fa"` keeps your accent and takes the rest from the wallpaper.

You need `matugen` installed. Without it, pshell uses the colours from `config.json` and logs a warning.

One matugen run does two jobs:

1. It prints the palette, which pshell maps onto the bar: `surface` is the background, `on_surface` is text, `primary` is the accent, `error` is urgent, and `outline` is dimmed text.
2. It writes a set of theme files, so your terminal, GTK apps and btop use the same colours as the bar.

Both come from the same run, so they always match.

`config.json` reloads when it changes. A script that changes your wallpaper by writing the `wallpaper` key recolours the bar and rewrites the theme files. Nothing needs restarting, and there is no daemon. Changing the wallpaper from pshell's own [picker](wallpaper.md) does the same.

With `"theme": "manual"`, which is the default, matugen never runs and no files are written.

## What gets generated

pshell never edits an app's real config. Each template writes to a file that pshell owns, such as `pshell-colors.css`, or a theme called `pshell` in the app's theme folder. You add one line to your own config, once, to use it.

| Name | Writes | What you add, once |
|---|---|---|
| `gtk3` | `~/.config/gtk-3.0/pshell-colors.css` | `@import url("pshell-colors.css");` in `~/.config/gtk-3.0/gtk.css` |
| `gtk4` | `~/.config/gtk-4.0/pshell-colors.css` | `@import url("pshell-colors.css");` in `~/.config/gtk-4.0/gtk.css` |
| `kitty` | `~/.config/kitty/pshell-colors.conf` | `include pshell-colors.conf` in `kitty.conf`. Running kitty windows reload on their own. |
| `ghostty` | `~/.config/ghostty/themes/pshell` | `theme = pshell` in `~/.config/ghostty/config` |
| `alacritty` | `~/.config/alacritty/pshell-colors.toml` | `import = ["~/.config/alacritty/pshell-colors.toml"]` under `[general]` in `alacritty.toml`. Alacritty reloads imports on its own. |
| `btop` | `~/.config/btop/themes/pshell.theme` | `color_theme = "pshell"` in `btop.conf`, or pick it in btop's options |
| `zed` | `~/.config/zed/themes/pshell.json` | `"theme": "pshell"` in Zed's `settings.json` |
| `qtct` | `~/.config/qt6ct/colors/pshell.conf` | Pick `pshell` as the colour scheme in qt6ct. Qt apps outside the shell need `QT_QPA_PLATFORMTHEME=qt6ct`. |
| `swayosd` | `~/.config/swayosd/style.css` | Nothing. This is the file swayosd reads. Restart `swayosd-server` after a theme change, since it reads the file at start. |
| `walker` | `~/.config/walker/themes/pshell/style.css` | `theme = "pshell"` in `~/.config/walker/config.toml`. See the note below. |
| `walker-keybind` | `~/.config/walker/themes/pshell/keybind.xml` | Nothing beyond the `walker` row. It puts each keybind hint on one line, and has no colours in it. |
| `hyprland` | `~/.config/hypr/pshell-colors.lua` | `pcall(require, "pshell-colors")` at the end of `~/.config/hypr/hyprland.lua`. See the note below. |

GTK 3 and GTK 4 get the same colours from one shared template. Missing folders are created. An app you do not have just gets a file it never reads, which is why none of this needs setting up per app.

**Walker.** Walker re-reads the stylesheet every time it opens, so later theme changes show up on the next open. But it only looks for the theme folder at startup. If you run walker as a service (`walker --gapplication-service`), restart it once after the first render. Render the theme before you set `theme = "pshell"`, because walker shows no styling at all for a theme folder that is not there.

**Hyprland.** This colours window borders and group bars. The `pcall` lets Hyprland start cleanly before the file exists. Hyprland only watches files it has already loaded, so run `hyprctl reload` once after the first render. After that, it recolours by itself on every theme change. This only works with a Lua config; there is no hyprlang version.

### Terminal colours

Terminals get a real set of 16 ANSI colours, not 16 shades of the accent. pshell starts from the standard xterm colours and has matugen blend each one toward the wallpaper, so red stays a red. Black, white and the greys come from the palette's surface colours instead, because a colour with no hue would blend into a random pastel.

### Turning templates off

To keep pshell away from one app, list its name:

```json
{ "disabledTemplates": ["kitty"] }
```

## Your own templates

Put template files in `~/.config/pshell/templates/` and list them in `~/.config/pshell/templates.json`. They are rendered after the built-in ones, from the same matugen run.

```json
[
  {
    "name": "waybar",
    "input": "waybar-colors.css",
    "output": "~/.config/waybar/pshell-colors.css",
    "postHook": "pkill -SIGUSR2 waybar || true"
  }
]
```

| Field | What it does |
|---|---|
| `name` | A name for the template, used in warnings |
| `input` | The template file, relative to `~/.config/pshell/templates/` |
| `output` | Where to write it. An absolute path, or one starting with `~/`. |
| `postHook` | Optional. A command to run after writing. |

Templates use matugen's own syntax, such as `{{colors.primary.default.hex}}`. The blended terminal colours are `{{colors.ansi_0.default.hex}}` through `ansi_15`.

`templates.json` is watched, so saving it renders everything again. A broken entry is skipped with a warning that names it, and the built-in templates still render.

## Scheme and mode

| Key | What it does | Default |
|---|---|---|
| `theme` | `wallpaper` to take colours from the wallpaper, or `manual` | `manual` |
| `mode` | `dark` or `light`. Leave it out to follow the desktop. | follow the desktop |
| `matugenScheme` | The palette algorithm | `scheme-tonal-spot` |
| `matugenPrefer` | Which colour wins when an image has several candidates | `saturation` |
| `disabledTemplates` | Built-in templates not to write | none |

When `mode` is not set, pshell reads the GTK `color-scheme` setting and follows it as it changes. So the control centre's Dark Mode tile, GNOME settings, or any script that writes that setting restyles the shell along with your apps. Setting `mode` pins it, and the desktop setting is ignored. This needs `gsettings`. Without it, or when the desktop's scheme is `default`, pshell stays dark.

matugen will not guess between several source colours when there is no terminal to ask it, which is why `matugenPrefer` always has a value.

You can change all of this from a keybind or a script:

```sh
pshell theme setScheme scheme-vibrant
pshell theme setPrefer saturation
pshell theme setMode light        # light, dark, or auto to follow the desktop
pshell theme reload               # run matugen again now
pshell theme current              # what is in use
```

The `set` commands write `config.json`, so they are the same as editing the file. A value matugen would reject is ignored and nothing is written. The command still prints nothing and exits 0; the warning only shows up in the shell's log, so check with `pshell theme current`.

The settings app's Theme page has the same scheme, prefer and mode as dropdowns, with a row of swatches showing the palette. It uses the same setters, so it cannot save a value the command line would refuse.

## Icons

pshell draws icons from two sets.

**Your icon theme.** Most widgets use icons from your icon theme by name, so they follow whatever theme you use. Only standard freedesktop names are used, which every common theme has. They are recoloured to the text colour.

Qt needs a platform theme to know which icon theme you use. pshell sets `QT_QPA_PLATFORMTHEME=gtk3`, so it reads the GTK setting. If themed icons are missing, check that first.

**Material Symbols.** The control centre and most panels use [Material Symbols](https://fonts.google.com/icons) Rounded, the same set and the same icon choices as [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). The font ships in `assets/fonts/`, so these icons look right even with no icon theme installed.

If you write QML for pshell: `Services/Icons.qml` finds a themed icon by name and `Ui/BarIcon.qml` draws it. `Services/Glyphs.qml` names a Material Symbol and `Ui/MaterialIcon.qml` draws it:

```qml
MaterialIcon {
    name: Glyphs.battery(45, false)   // "battery_3_bar"
    filled: true
    size: 18
}
```

`Ui/BarIconButton.qml` takes either kind: `iconSource` or `iconSources` for themed files, `iconName` or `iconNames` for symbols.
