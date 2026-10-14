# pshell

My own Wayland status bar, built on Quickshell. Inspired by Omarchy and
DankMaterialShell.

A widget is either a program that prints a line to stdout, or a QML file. It
also runs bar widgets built for Omarchy, unmodified.

About 300 lines of QML.

## Install

```sh
git clone https://github.com/hdprajwal/pshell ~/.config/quickshell/pshell
mkdir -p ~/.config/pshell
cp ~/.config/quickshell/pshell/config.example.json ~/.config/pshell/config.json
qs -p ~/.config/quickshell/pshell
```

You need `quickshell` installed.

To start it with Hyprland, add this to `~/.config/hypr/hyprland.conf`:

```
exec-once = qs -p ~/.config/quickshell/pshell
```

or, with a Lua config (Hyprland 0.55+), to `~/.config/hypr/hyprland.lua`:

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/pshell")
end)
```

If another shell — DankMaterialShell, say — also starts at login, stop it
from doing so, or you get two bars. DMS starts from a systemd unit rather
than from the Hyprland config: `systemctl --user disable --now dms.service`.

### The `pshell` command

Every door into the shell is an IPC call, and typing the path each time gets
old. `bin/pshell` is a one-line wrapper around them:

```
pshell lock                    lock the screen
pshell unlock                  unlock it again
pshell preview                 draw the lockscreen without locking
pshell run                     start the shell
pshell launcher                open the application launcher
pshell clipboard               open the clipboard history
pshell nightlight              warm the screen, or stop (needs hyprsunset)
pshell updates                 pending package updates (needs cachy-update or arch-update)
pshell bar toggle              hide or show the bar (also show, hide)
pshell settings toggle         any IPC target, by name
pshell ipc show                straight through to qs ipc
```

Everything there is an IPC call into the shell except `launcher`, which runs
[walker](https://github.com/abenz1267/walker) — see below for why that is
not a shell feature, and what you need installed.

Symlink it, and it needs nothing else:

```sh
ln -s ~/.config/quickshell/pshell/bin/pshell ~/.local/bin/pshell
```

If you would rather it lived with the rest of your pshell things, copy it
out of the checkout and say where the checkout is:

```sh
cp ~/.config/quickshell/pshell/bin/pshell ~/.config/pshell/pshell
ln -s ~/.config/pshell/pshell ~/.local/bin/pshell
export PSHELL_DIR=~/.config/quickshell/pshell   # in your shell rc
```

It looks for the shell in three places, in this order: the checkout the
script sits in, then `$PSHELL_DIR`, then `~/.config/quickshell/pshell`.

Location first is deliberate. A symlink is resolved before that check, so
`<checkout>/bin/pshell` always drives its own checkout however you reached
it — a second clone, or a worktree, answers for itself, which is what makes
it safe to try a branch without uninstalling anything. `PSHELL_DIR` is for
the copy that lives outside any checkout, and cannot silently redirect one
checkout's own command at another.

Everything below is written with this on your `$PATH`. Without it, every
`pshell x y` is `qs -p ~/.config/quickshell/pshell ipc call pshell.x y`.

## Config

Everything is in `~/.config/pshell/config.json`. Save the file and the bar
updates. You do not need to restart it.

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

`position` takes `top`, `bottom`, `left`, or `right`.

`terminal` is the terminal pshell opens things in -- today only the system
updater, see [System updates](#system-updates). A program name or a path,
optionally followed by arguments of its own, such as `"kitty -1"`. The
arguments are split on spaces and passed straight to the program, never
through a shell, so there is no quoting: a path with a space in it cannot be
used. Leave it out and pshell uses `$TERMINAL`, then the first of ghostty,
kitty, alacritty, foot and wezterm it finds.

### Spacing

Three distances, each with its own knob:

| | | default |
|---|---|---|
| `gap` | between two widgets | `12` |
| `padding` | from the bar's edge to the first or last widget | whatever `gap` is |
| `margin` | from the screen edge to the bar | `0` |

```json
{
  "gap": 6,
  "padding": 4,
  "margin": 8
}
```

A non-zero `margin` lifts the bar off the screen and rounds its corners, and
the compositor keeps the space reserved, so a maximised window stops outside
the margin rather than sliding under it. A number margins every side; an
object margins only the sides it names:

```json
{ "margin": { "top": 4, "left": 10, "right": 10 } }
```

Each widget also carries padding of its own, which is why the last widget does
not sit flush against the bar's edge even at `"padding": 0`. That comes from
`bar.icon-slot` being wider than `barIconSize`; override it under `shell` if
you want the buttons themselves tighter:

```json
{ "shell": { "bar.icon-slot": 20 } }
```

`barIconSize` sets the pixel size of every icon drawn in the bar, defaulting to
55% of the bar height. It covers the tray, battery and control centre together,
so they stay in step. Icons inside popouts size themselves off the font instead
and are not affected. A widget can still override it: the tray takes `iconSize`
for an exact size or `iconScale` for its own fraction of the bar height.

## Wallpaper

pshell paints the desktop background itself: one window per screen, on the
layer-shell background layer, under everything else. No swaybg, no hyprpaper,
no daemon to restart on every change — the image named by `wallpaper` is
drawn by the same shell that draws the bar, and changing it crossfades to the
new picture instead of flashing through a process swap.

| | | default |
|---|---|---|
| `wallpaper` | the image on screen | none — the background colour |
| `wallpaperDir` | where the candidates live | `~/wallpapers` |

With no `wallpaper` set, or a path that does not resolve to an image, the
background is a flat `bg`-coloured surface rather than a hole.

The settings app's Wallpaper page shows `wallpaperDir` as a grid of
thumbnails; click one to set it. The same moves are scriptable through the
`pshell.wallpaper` IPC target:

```
pshell wallpaper set ~/wallpapers/foo.png
pshell wallpaper next                       cycle through the directory
pshell wallpaper previous
pshell wallpaper random                     never the one already up
pshell wallpaper current
pshell wallpaper list                       one path per line
pshell wallpaper rescan                     after adding files to the directory
```

Every one of them is a single write of `wallpaper` in `config.json`, which is
also why a wallpaper picked here re-themes everything below: the palette is
derived from the same key.

## Colours from the wallpaper

Set `theme` to `wallpaper` and point `wallpaper` at an image. pshell runs
[matugen](https://github.com/InioX/matugen) over it and fills in the colours you
have not set yourself:

```json
{
  "theme": "wallpaper",
  "wallpaper": "~/wallpapers/black.jpg",
  "mode": "dark"
}
```

Anything you set explicitly still wins, so `"accent": "#89b4fa"` alongside the
above keeps your accent and derives the rest.

One matugen run does two jobs: it prints the palette as JSON, which pshell
reads off stdout and maps onto the bar — `surface` to the background,
`on_surface` to text, `primary` to the accent, `error` to urgent, `outline` to
dimmed text — and it renders a set of theme files to disk, so the terminal,
GTK apps and btop wear the same colours as the bar. Same process, same
palette; the two cannot drift.

Because `config.json` reloads on save, a script that changes your wallpaper can
rewrite the `wallpaper` field and the bar recolours itself — and now the theme
files re-render with it. There is nothing to restart and no daemon watching
anything.

`theme: "wallpaper"` is what switches all of this on. On `"manual"` nothing
runs and nothing is generated — no files appear behind your back.

### What gets generated, and how to use it

pshell never edits an app's real config. Each template renders to a file that
pshell alone owns and may overwrite — `pshell-colors.*`, or a theme named
`pshell` in the app's theme directory — and your own config includes or
selects it once. Terminals get a real ANSI set, not sixteen shades of the
accent: pshell seeds matugen with the standard xterm sixteen and lets it blend
each toward the wallpaper, so red stays in the red family. The achromatic
slots — black, white, the greys — come from the palette's surface ramp
instead, because a seed with no hue blends into a pastel of whatever hue
matugen guesses.

| name | writes | you add, once |
|---|---|---|
| `gtk3` | `~/.config/gtk-3.0/pshell-colors.css` | `@import url("pshell-colors.css");` in `~/.config/gtk-3.0/gtk.css` |
| `gtk4` | `~/.config/gtk-4.0/pshell-colors.css` | `@import url("pshell-colors.css");` in `~/.config/gtk-4.0/gtk.css` |
| `kitty` | `~/.config/kitty/pshell-colors.conf` | `include pshell-colors.conf` in `kitty.conf` — running kittys reload on their own |
| `ghostty` | `~/.config/ghostty/themes/pshell` | `theme = pshell` in `~/.config/ghostty/config` |
| `alacritty` | `~/.config/alacritty/pshell-colors.toml` | `[general]` `import = ["~/.config/alacritty/pshell-colors.toml"]` in `alacritty.toml` — alacritty live-reloads imports |
| `btop` | `~/.config/btop/themes/pshell.theme` | `color_theme = "pshell"` in `btop.conf`, or pick it in Esc → Options |
| `zed` | `~/.config/zed/themes/pshell.json` | `"theme": "pshell"` in Zed's `settings.json` |
| `qtct` | `~/.config/qt6ct/colors/pshell.conf` | pick `pshell` as the colour scheme in qt6ct (needs `QT_QPA_PLATFORMTHEME=qt6ct` for Qt apps outside the shell) |
| `swayosd` | `~/.config/swayosd/style.css` | nothing — that is the path swayosd reads, so pshell owns the file outright; restart `swayosd-server` after a theme change, it reads the stylesheet at start |
| `walker` | `~/.config/walker/themes/pshell/style.css` | `theme = "pshell"` in `~/.config/walker/config.toml` — walker re-reads the sheet every time it opens, so later theme changes land on the next launch; but it only *finds* the theme at startup, so restart `walker --gapplication-service` once after the first render |
| `walker-keybind` | `~/.config/walker/themes/pshell/keybind.xml` | nothing beyond the row above — it lands in the same theme directory. The only template with no colours in it: it puts each keybind hint's chip and its key on one line, which is a box orientation and so out of CSS's reach. walker resolves a theme's files one at a time, so overriding this one leaves its other fourteen layouts alone |
| `hyprland` | `~/.config/hypr/pshell-colors.lua` | `pcall(require, "pshell-colors")` at the end of `~/.config/hypr/hyprland.lua` — window borders and group bars. `pcall` so Hyprland starts cleanly before the first render. Hyprland only watches files it has loaded, so `hyprctl reload` once after that first render; from then on it recolours on every theme change by itself. Lua configs only: there is no hyprlang version |

GTK3 and GTK4 get the same colours from one shared template; only the
directory each toolkit reads differs. Missing output directories are created;
an app you don't have installed just gains an unused file, which is why none
of this needs configuring per app.

To keep pshell away from one of these — you have opinions about your kitty
colours — list the names to skip:

```json
{ "disabledTemplates": ["kitty"] }
```

### Your own templates

Drop template files in `~/.config/pshell/templates/` and declare them in
`~/.config/pshell/templates.json`; they render after the built-ins from the
same matugen run. `input` is relative to the templates directory, `output` is
absolute or `~/`-prefixed, and `postHook` is an optional command run after
rendering:

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

Templates use matugen's own syntax — `{{colors.primary.default.hex}}`, and
`{{colors.ansi_0.default.hex}}` through `ansi_15` for the blended terminal
set. The file is watched: saving it re-renders everything. A malformed entry
is skipped with a warning naming it and never stops the built-ins from
rendering.

### Scheme, mode and the rest

`mode` takes `dark` or `light`. Leave it out and pshell follows the desktop
instead, reading the GTK `color-scheme` setting and re-deriving the palette
whenever it changes — so the control centre's Dark Mode tile, GNOME settings or
any script that writes that key restyles the shell as well as your apps.
Setting `mode` pins it and the desktop is ignored. Needs `gsettings`; without
it, or with a scheme of `default`, pshell stays dark.

`matugenScheme` picks the palette algorithm,
defaulting to `scheme-tonal-spot`. `matugenPrefer` decides which source colour
wins when an image has several candidates, defaulting to `saturation`; matugen
refuses to guess without it when there is no terminal to ask.

All of it is drivable from a keybind or a script through the `pshell.theme`
IPC target: `pshell theme setScheme scheme-vibrant`, `setPrefer`, `setMode
light|dark|auto` (`auto` hands the choice back to the desktop), `reload` to
re-run matugen by hand, and `current` to see what is in effect. The set*
commands write `config.json`, so they are the same change as editing the file
— and they refuse a scheme or prefer matugen would reject.

Or pick all of it visually: the settings app's Theme page has the same
scheme, prefer and mode as dropdowns, with a live swatch row showing what the
palette resolves to. It goes through the same setters, so it can hold no
value the command line would refuse.

Needs `matugen` installed. Without it the configured colours are used and a
warning is logged.

## Layout

```
shell.qml            the bar window, and the contract widgets read
Services/            singletons: config, theme, icons, audio, brightness
Components/          the shared chrome: sections, buttons, popouts, sliders
Widgets/<Name>/      one directory per widget, holding its panels too
Commons/  Ui/        the Omarchy compatibility modules
assets/              fonts pshell ships rather than asks fontconfig for
```

Quickshell exposes every directory as a module, so `Widgets/Network/` is
`qs.Widgets.Network` and a file reaches its neighbours by importing it. No
`qmldir` is needed for that; the two that exist are there to pin the names
Omarchy widgets import.

A widget owns the panels only it uses, so `Widgets/Network/` holds the list of
networks and the password prompt alongside the widget itself. The control
centre is the exception that proves the layout works: it imports
`qs.Widgets.Network` and `qs.Widgets.Bluetooth` because it genuinely reuses
their lists rather than keeping its own copies.

This is the shape Omarchy's own shell uses, which is not a coincidence either.

## Widgets

Nineteen are built in. These hold something a polled command cannot: a live
connection to a Hyprland socket, DBus or UPower, or state that has to outlive a
single run.

| type | What it does |
|---|---|
| `workspaces` | Hyprland workspaces. Click one to switch. |
| `clock` | `format` takes a Qt date format string. |
| `calendar` | The same clock, but clicking it opens the time and a full month. Page with the arrows or the scroll wheel, click the month name to come back to today. `timeFormat`, `dateFormat`, `firstDayOfWeek`. |
| `activeWindow` | The focused window's icon, application name and title. `maxWidth` caps the title in pixels, default 400. `showIcon`, `showAppName`. Hides itself when nothing is focused. |
| `microphone` | Mute state for the default input. Left click mutes, scroll changes the level, right click runs `onRightClick`. `showVolume` puts the percentage in the bar. |
| `privacy` | A red dot while something is using the microphone or the camera. Click it to see what. Hidden when nothing is. `showCamera`, `interval`. |
| `idleInhibitor` | Keeps the screen awake while it is on. Off after every restart. |
| `nightlight` | Warms the screen through hyprsunset. Click to turn it on or off. Off after every restart unless a schedule, or a hyprsunset already warming the screen, says otherwise. The temperature and schedule are configured under `nightlight` rather than on the widget. Hides itself where `hyprsunset` is not installed. See [Nightlight](#nightlight). |
| `updates` | How many package updates are pending, from cachy-update or arch-update, and only while there are some. Click to run the updater in a terminal, right click to check again now. The tooltip splits the count into repo, AUR and Flatpak. Hides itself where neither tool is installed. See [System updates](#system-updates). |
| `tailscale` | Tailnet state and the machines on it. Left click opens the panel to connect, disconnect and pick an exit node. `interval`, `showName`, `maxNodes`. |
| `tray` | System tray. Left click activates, middle click is the secondary action, scroll passes through, right click opens the menu. `hide` takes a comma-separated list of ids to leave out, `iconScale`, `iconSize` and `spacing` tune the layout. |
| `battery` | Charge and time remaining, plus a power profile picker. Left click opens the panel, right click toggles the percentage label. `lowThreshold` sets when it turns red, default 20. |
| `network` | Wi-Fi signal or wired. Left click opens the panel to scan, connect and disconnect, right click toggles the radio. Right click a network in the list to forget it. `showName` puts the SSID in the bar, `maxNetworks` caps the list. |
| `bluetooth` | Adapter state and connected devices, with battery level where the device reports it. Left click opens the panel to pair, connect and disconnect, right click toggles the radio. `showCount`, `maxDevices`. |
| `aiUsage` | How much of your coding agents' allowances is gone. The bar wears the tightest window across every provider; clicking it opens a tab per provider, with that provider's windows, seven days of tokens and a model breakdown. `barSource`, `warnThreshold`, `refreshIntervalSec`, `defaultTab`, `hideWhenIdle`. Hides itself where `pshell-agents` is not installed. |
| `weather` | The condition and the temperature where you are. Click it for feels-like, humidity, wind, the next hours and three days of high and low. `showLabel` puts the condition in the bar too. `panelWidth` sizes the panel. Everything else is configured under `weather` rather than on the widget, since one shell fetches once however many bars are on it. |
| `controlCenter` | Everything in one panel: session header, volume, brightness and keyboard backlight sliders, and tiles for Wi-Fi, Bluetooth, audio output, microphone, night mode and dark mode. Right click mutes, scroll changes volume. |
| `power` | Lock, suspend, log out, restart, power off. The three that end something ask first and are drawn in the urgent colour. `panelWidth` sizes the panel. The commands themselves are configured under `power` rather than on the widget, and every one of them answers on IPC with no widget in the bar. |
| `keybinds` | Your Hyprland keybinds, read from `hyprctl binds -j` when the panel opens, grouped by modifier with a filter field. Says how many binds carry no description and what to do about it. `panelWidth`, `listHeight`. The panel is drawn here; `pshell.keybinds` is owned by a service, so the command answers on any bar. |

Everything else is a program. Leave out `type` and give it an `exec`.

| Key | What it does |
|---|---|
| `exec` | The command. Runs through `sh -c`. |
| `interval` | Seconds between runs. Leave it out or set `0` to stream instead. |
| `onClick` | Command to run on left click. |

### Polling

Run the command every N seconds and draw what it prints.

```json
{ "exec": "date +%H:%M", "interval": 60 }
```

### Streaming

Set `interval` to 0 and pshell keeps the process running. Every line it prints
is one update. This is the better option for anything that reacts to events.
Updates show up right away, and nothing runs in between.

```json
{ "exec": "my-mpris-watcher" }
```

## What your widget prints

If it prints plain text, that text is the label.

```
cpu 42%
```

If you want a tooltip or a state, print JSON instead.

```json
{"text": "cpu 42%", "tooltip": "load 1.2", "class": "urgent"}
```

A `class` of `urgent` or `critical` turns the text red.

This is the same format Waybar uses, so most Waybar custom modules work here
without changes.

## QML widgets

A stdout script cannot hold live state, so anything that needs a system
connection is a QML file instead. Put it in its own directory under
`~/.config/pshell/widgets/` with a `manifest.json`:

```
~/.config/pshell/widgets/gpu/
  manifest.json
  Widget.qml
```

```json
{
  "schemaVersion": 1,
  "id": "me.gpu",
  "name": "GPU",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": { "defaultSection": "right", "defaults": { "unit": "C" } }
}
```

Reference it from `config.json` by id, and anything else on the entry becomes
its settings:

```json
{ "id": "me.gpu", "unit": "F" }
```

The widget extends `BarWidget` and reads what the bar injects:

```qml
import QtQuick
import qs.Ui

BarWidget {
  id: root
  implicitWidth: label.implicitWidth + 12
  implicitHeight: barSize

  Text {
    id: label
    anchors.centerIn: parent
    text: "gpu " + root.setting("unit", "C")
    color: root.bar.foreground
    font.family: root.bar.fontFamily
  }
}
```

## Omarchy widgets

That manifest format is Omarchy's, and it is not a coincidence. pshell ships
`Commons` and `Ui` modules using the same type and token names, so an Omarchy
bar widget resolves `import qs.Commons` and `import qs.Ui` against pshell
instead. Clone one in and it runs:

```sh
git clone https://github.com/ragnacron/omarchy-workspaces-per-monitor \
  ~/.config/pshell/widgets/omarchy-workspaces-per-monitor
```

Then add `{ "id": "ragnacron.workspaces-per-monitor" }` to a section.

Widgets that open a panel work too. Omarchy's whole `Ui` kit is vendored here
rather than reimplemented: `Panel`, `KeyboardPanel`, `Button`, `TextField`,
`Dropdown` and the rest, unmodified, so a widget written against them behaves
the same. Copying is deliberate. A reimplementation drifts, and every drift is
a widget that works there and not here.

What is pshell's own is the bridge underneath. `Color`, `Style` and `Util`
implement the same interface Omarchy's do, but read `config.json` and the
matugen palette instead of Omarchy's theme files, so a widget written for one
shell is themed by the other. Omarchy names the readable colour `text` and
pshell named it `foreground`; both resolve.

On Qt 6.12 and later, `QtQuick` has a `Color` singleton of its own, and in a
file with a bare `import QtQuick` it hides the palette: `Color.popups` comes
back undefined. New QML should do what Omarchy now does, and write
`Commons.Color` after `import qs.Commons as Commons`. Widgets that still say
`Color` keep working, because on those Qt versions pshell loads every widget
from a copy under `~/.cache/pshell/widgets/` with `import QtQuick 6.11` in
place of the bare import. Omarchy's shell makes the same change as it loads a
plugin. Your own files are never edited, and as before, an edit to a widget
shows up the next time the shell starts or reloads.

See [NOTICE.md](NOTICE.md) for what came from where.

## Calendar

`clock` prints the time and nothing else. `calendar` looks the same in the bar
and opens a panel: the time large at the top, the date under it, then the month.

The arrows either side of the month name page through it, and so does the scroll
wheel over the days. Once you have paged away, clicking the month name comes
back to today, and so does closing and reopening the panel, so it never comes up
showing last March.

```json
{
  "type": "calendar",
  "format": "ddd dd MMM  HH:mm",
  "timeFormat": "HH:mm",
  "dateFormat": "dddd, d MMMM yyyy",
  "firstDayOfWeek": "monday"
}
```

`format` is the bar label, the other two are the panel. All three take a Qt date
format string. `firstDayOfWeek` takes `monday` or `sunday`, and follows your
locale if you leave it out.

The grid is always six rows. A month that spills into a seventh week would
otherwise make the panel taller than the one before it, and a panel that changes
height as you page through it is worse than one mostly empty row.

## Active window

The window you are looking at, as an icon, an application name and a title.

```json
{ "type": "activeWindow", "maxWidth": 400 }
```

The title is whatever the window says it is, and a browser puts a whole page
title in there, so `maxWidth` caps it in pixels and the rest is elided. Without
a ceiling one tab pushes every other widget off the bar.

The name comes from the application's `.desktop` file. Where there is not one,
the last segment of a reverse-DNS app id is used instead, so `dev.zed.Zed` still
reads as `Zed`. Icons are drawn in their own colours rather than tinted to the
foreground, since an application logo is artwork and not a symbol.

Nothing focused hides the widget rather than leaving a gap.

Unlike `workspaces` this one is not tied to Hyprland. It reads the wlr
foreign-toplevel protocol, which any wlroots compositor speaks.

## Privacy, microphone and staying awake

Three small widgets that each answer one question.

`microphone` is the mute state of the default input, and nothing else. Picking
an input device already lives in the control centre, and a second copy of that
list is a second thing to keep right. Muted draws in the urgent colour rather
than dimmed, because a hot microphone you believe is off is the expensive
mistake, not the other way round.

`privacy` shows a red dot while something is recording, and disappears when
nothing is. The two halves are not found the same way and it is worth knowing
which is which. A microphone capture is a real Pipewire stream, so it arrives
as an event and the dot appears the instant a program opens the mic, with the
program's own name in the panel. A camera is opened straight on `/dev/videoN`
by most programs and that emits nothing at all, so that half is a poll and can
be up to `interval` seconds late. It also only reports that the camera is
held, not by whom, because naming the wrong program is worse than naming none.
Set `showCamera` to `false` to drop the poll entirely.

`idleInhibitor` keeps the screen on. Wayland attaches an idle inhibitor to a
surface and only counts it while that surface is visible, so an inhibitor
living on the bar dies the moment a fullscreen window covers it, which is
exactly when you wanted it. So this one holds its own surface instead: a
one-pixel transparent window on the overlay layer, above fullscreen windows and
never occluded, created only while the toggle is on. It is off after every
restart, because a machine that quietly refuses to sleep because of something
you pressed last week is a bad surprise.

It needs something that reads `zwp_idle_inhibit`, which is what hypridle and
swayidle do. Nothing consumes it otherwise and the toggle will have no effect.

## Nightlight

A warmer screen in the evening, through Hyprland's
[hyprsunset](https://github.com/hyprwm/hyprsunset). It needs hyprsunset
installed, and nothing else:

```sh
sudo pacman -S hyprsunset
```

Without it the `nightlight` widget and the control centre's Night Mode tile
hide themselves, and `pshell nightlight on` says what to install and exits 1.
`off` still succeeds, since the screen is already as it should be.
Install it while the shell is running and the next `pshell nightlight` after
the first refusal works; no restart.

```json
{
  "right": [ { "type": "nightlight" } ],
  "nightlight": { "temperature": 4000, "start": "20:00", "end": "07:00" }
}
```

`temperature` is in kelvin, from 1000 (very orange) to 6000 (barely
anything), and defaults to 4000. A value outside that range is pulled to the
nearest end.

`start` and `end` are an optional schedule, 24-hour local time. The
nightlight turns on at `start` and off at `end`, through midnight if `end` is
earlier, and is otherwise left alone: turn it off at 21:00 to watch a film and
it stays off until the next `start`. Leave either out, or set them equal, for
no schedule. The clock is checked every thirty seconds, so a laptop that
slept through 20:00 catches up within half a minute of waking.

Whether it is on is not saved. It is off after every restart, and after a
reload of the shell's QML, for the idle inhibitor's reason: a screen that
comes up orange because of something you pressed last week is a bad surprise.
A schedule is how to have it come back on its own: at start the shell turns
the nightlight on if the schedule says it is night. The exception is a
hyprsunset started outside pshell that is still warming the screen when the
shell starts: pshell asks it, and shows the nightlight as on.

### Who runs hyprsunset

If a hyprsunset is already running, started by your Hyprland config or a
systemd unit, pshell uses it: `on` sets its temperature over `hyprctl
hyprsunset`, `off` sends `identity`. It is never stopped.

If nothing answers, pshell starts `hyprsunset -t <temperature>` itself, as
its own child under `setpriv --pdeathsig TERM`. Turning the nightlight off
sends `identity` and then stops it. The kernel stops it if the shell exits,
however the shell exits, so a crashed bar does not leave a stray hyprsunset
behind. hyprsunset exiting on its own turns the nightlight off and logs
why; pshell does not restart it.

If you keep hyprsunset profiles in `~/.config/hypr/hyprsunset.conf`, the
hyprsunset pshell starts may read them too and change the temperature on
their schedule rather than pshell's. Use one schedule or the other.

### Commands

```
pshell nightlight                     toggle
pshell nightlight on                  prints "on 4000K"
pshell nightlight off
pshell nightlight isOn                true or false
pshell nightlight isAvailable         whether hyprsunset is installed
pshell nightlight temperature         the configured temperature
pshell nightlight setTemperature 3500 saved to config.json
pshell nightlight status              one line, e.g.
                                      on 4000K, hyprsunset started by pshell, hyprsunset reports 4000K
```

`setTemperature` refuses a value outside 1000 to 6000 rather than guessing
what you meant by 400.

When the shell cannot do what was asked, the IPC call answers with a line
starting `error: `. `pshell` prints that to stderr and exits 1, so
`pshell nightlight on && ...` stops there. Only the targets that promise to
answer that way get this -- the nightlight and `updates` -- since for the
rest a line starting `error: ` can be ordinary output.

## System updates

How many package updates are waiting, and a click to install them. It is
built on the update tool your distribution already has rather than on a
checker of its own: [cachy-update](https://github.com/CachyOS/cachy-update)
on CachyOS, or [arch-update](https://github.com/Antiz96/arch-update), which
cachy-update is a fork of, on Arch. One of them has to be installed:

```sh
sudo pacman -S cachy-update   # CachyOS
sudo pacman -S arch-update    # Arch
```

Both come with a systemd user timer that checks for updates a couple of
minutes after you log in and once a day after that. Turn it on if it is not
already:

```sh
systemctl --user enable --now arch-update.timer
```

```json
{
  "right": [ { "type": "updates" } ]
}
```

pshell does no checking of its own. The timer's check writes what it found
to `~/.local/state/arch-update/` (`$XDG_STATE_HOME` if you set it), and the
shell watches those files, so the count changes the moment a check finishes
and the bar adds no network traffic or pacman load. Repo, AUR and Flatpak
updates are counted separately and added up; the tooltip shows the split.
Until the first check has run there is nothing to watch, and the shell looks
for the files once a minute until they appear.

The widget is hidden while nothing is pending, and where neither tool is
installed. Right click, or `pshell updates refresh`, starts the timer's
own unit, `arch-update.service`, straight away -- the same check, and the
same unit, so a refresh while the timer's check is running waits for that
one rather than starting a second, and a reload of the bar does not cut it
off. Where there is no such unit it runs `cachy-update --check` itself. Like
the timer's, the check sends cachy-update's own "N updates available"
notification when the list has changed since the last check. A refresh is
refused while the updater is running, since a check then could put back the
list the update has just cleared.

A check that cannot reach the mirrors -- offline, say -- finishes with an
empty list, which looks just like "up to date". When it was a refresh of
pshell's own that failed this way, the count stays at the check before it,
the tooltip says the last check could not reach the mirrors, and the next
change to the files takes over. A failed check started by the timer is not
caught: it reads as up to date until the next one.

The count does not dip while a check runs. The check empties each list file
before it fills it again, so pshell takes a list file only while it agrees
with `last_updates_check`, which arch-update replaces in one go once a check
has finished. Until then the bar keeps the last finished count.

Click it, or `pshell updates open`, to run the updater itself in a terminal:
it shows the Arch news, lists what will change, asks before it does anything,
and then deals with orphans, the package cache and services that need a
restart. It is not a child of the shell, so reloading or restarting the bar
does not interrupt it. It rewrites the state files as it goes, so the count
falls as it works and the widget goes away when it is done.

```json
{
  "terminal": "kitty",
  "updates": { "float": true }
}
```

`terminal` is the shell-wide setting described under [Config](#config): a
program, optionally with arguments. Those five get the window class
`pshell.updates` and the title "System update", added after your own
arguments; any other terminal is run as `<terminal> <your arguments> -e
cachy-update`. A `terminal` or `$TERMINAL` that is not installed is passed
over for the next one, and `pshell updates open` says so in its reply.

`updates.float`, on by default, floats the terminal in the middle of the
screen at 60% by 70%. On Hyprland with a Lua config, pshell adds a window
rule named `pshell-updates` for the class `pshell.updates` just before it
opens the window. Turn it off to leave the window to your own rules; the
next click switches pshell's rule off. On a hyprlang config, or another
compositor, nothing is added and the window opens wherever your compositor
puts new windows.

### Commands

```
pshell updates                 the status: same as `pshell updates status`
pshell updates status          one line, e.g.
                               4 updates (3 repo, 1 AUR), checked 2 hours ago, by cachy-update
pshell updates count           the number pending
pshell updates list            one per line: repo, aur or flatpak, a tab, and the update
pshell updates refresh         check now; answers at once, `status` says when it is done.
                               Fails while the updater is running
pshell updates open            run the updater in a terminal
pshell updates isAvailable     whether cachy-update or arch-update is installed
```

Bare `pshell updates` only reports. Starting an update means a sudo prompt
in a terminal, and that should be asked for by name.

`open` and `refresh` fail with exit 1, and say what to install, where
neither tool is installed. Install one while the shell is running and the
next try after the first refusal works; no restart.

## Tailscale

The tailnet, its machines, and what you usually want to do with them.

```json
{ "type": "tailscale", "interval": 10, "showName": true, "maxNodes": 8 }
```

The panel is a header saying whether you are connected and as whom, a connect
or disconnect button, an exit node picker, a search box, three filters and the
machines themselves. Every machine shows whether it is reachable, its address
with a button to copy it, its operating system and the DERP relay its traffic
is bouncing through. The relay only means anything when there is no direct
path, which is exactly when you are wondering why a machine feels slow.

This machine is in the list like any other, marked `This device`, rather than
being something the header mentions and the list leaves out. The counts on the
filters include it, so `All (3)` on a tailnet of three is three.

`My Online` is by owner, not by machine, because a tailnet can be shared. Two
accounts can both have a laptop called `dev`, and only one of them is yours.

The exit node list only offers machines that advertise themselves as one, and
says so plainly when none do. An empty dropdown reads as a bug when the truth
is that nobody is offering.

`tailscale status --json` is polled every `interval` seconds and again when you
open the panel, with a refresh button for when you have just changed something
on another machine. DankMaterialShell asks its Go daemon for this over IPC.
There is no daemon here and the CLI already prints all of it, and since
Tailscale publishes no event stream worth holding open and its state moves on
the order of minutes, a poll is the honest shape rather than a compromise.

Actions run the CLI, and the CLI is where they fail: `up` may want a login and
some setups want elevation. Whatever it prints to stderr is shown in the panel,
because a click that silently does nothing is worse than an error.

Copying needs `wl-copy`.

## Control centre

One panel instead of four. The header shows who is logged in and how long the
machine has been up, with lock, power and logout buttons. Below that are
volume, brightness and keyboard backlight sliders, then a grid of tiles.

Power off and log out ask before they fire; lock does not. What those three
buttons run comes from the same place as the session menu below, so the two
surfaces cannot disagree about what "log out" means. The `lock`, `power` and
`logout` keys on this widget's own entry still win where they are set.

Each tile has two targets, which is worth knowing before you use it. Clicking
the icon square toggles that thing on or off. Clicking anywhere else opens its
list: networks to join, devices to pair, or output and input devices to switch
between. Splitting it that way means a mis-click never turns your Wi-Fi off when
you meant to pick a network.

```json
{
  "type": "controlCenter",
  "name": "Prajwal",
  "avatar": "/var/lib/AccountsService/icons/prajwal",
  "lock": "loginctl lock-session",
  "power": "systemctl poweroff",
  "logout": "loginctl terminate-user $USER"
}
```

The audio and microphone tiles open a device picker with a header, the active
device outlined and labelled, and a list of what is currently playing or
recording. The input view carries its own microphone slider, since setting mic
level is usually why you opened it. `audioSettings` puts a gear in the header
that runs whatever you give it, for example `pavucontrol`.

Pinning a device floats it to the top of the list, which keeps a headset you
switch between from sinking under everything Pipewire enumerates. Pins persist
in `~/.config/pshell/state.json`, kept separate from `config.json` so the shell
never rewrites a file you hand-edited.

Brightness needs `brightnessctl`. The slider hides itself if there is no
backlight, so a desktop shows one slider rather than a broken one. The
keyboard backlight slider works the same way: it appears when
`brightnessctl` lists an LED whose name ends in `kbd_backlight` — the
vendor prefix (`asus::`, `tpacpi::`, none) does not matter — and hides
otherwise. Keyboard backlights are usually a few coarse steps rather than a
hundred, so that slider snaps to the hardware's real steps instead of
pretending the range is continuous.

Both backlights answer on the `pshell.brightness` IPC target, so a keybind
reaches them without the panel:

    pshell brightness up               screen, five points per step
    pshell brightness down
    pshell brightness set 40
    pshell brightness get
    pshell brightness keyboardUp       keyboard, always at least one step
    pshell brightness keyboardDown
    pshell brightness keyboardSet 50
    pshell brightness keyboardGet

The volume, mic, brightness and media *keys* themselves are not pshell's
job: pshell expects [swayosd](https://github.com/ErikReider/SwayOSD) bound
to them, and themes its OSD through the `swayosd` template above so the
popup wears the bar's colours.

Night mode is the [nightlight](#nightlight), lit while it is on with the
temperature underneath, and hidden where hyprsunset is not installed. Set
`nightMode` to a command and the tile runs that instead, for a machine that
warms its screen with gammastep or wlsunset; pshell cannot see that state, so
the tile then stays dark. `"nightMode": false` hides it. Dark mode toggles the GTK
`color-scheme` unless you override `darkModeCommand`, and pshell recolours with
it unless you have pinned `mode`.

Both tiles have no detail list, so the whole tile is the button rather than
just its icon.

## Session menu

Lock, suspend, log out, restart, power off — one panel, and five IPC calls
that skip it.

```json
{ "type": "power" }
```

Log out, restart and power off ask first, because a mis-click on any of them
costs whatever was unsaved. Lock and suspend do not: everything is still open
behind them. They are drawn in the urgent colour so the destructive half of
the menu is obvious before the dialog says it in words. Arrow keys or j/k walk
the rows, Enter picks one, Escape closes.

The commands are yours to change, under `power`:

| Key | Default |
|---|---|
| `lock` | `loginctl lock-session` |
| `logout` | `loginctl terminate-user $USER` |
| `suspend` | `systemctl suspend` |
| `reboot` | `systemctl reboot` |
| `poweroff` | `systemctl poweroff` |

Lock and log out are logind's because they act on this session; suspend,
restart and power off are systemctl's because they act on the machine. None of
them needs root — logind takes all three from a local active session.

### Commands

```
pshell power toggle       open or close the menu
pshell power lock         the five actions by name, without the menu
pshell power suspend
pshell power logout
pshell power reboot
pshell power poweroff
```

**The five actions never show a dialog**, however destructive. A keybind or a
script asking to reboot has already decided, and a confirmation nobody is
looking at would leave the machine up. The dialogs belong to the panels.

`pshell power lock` runs `loginctl lock-session`, which only locks anything if
something on your machine listens for logind's `Lock` signal and acts on it.
pshell does not — see the lockscreen section — so point hypridle's `lock_cmd`
at `pshell lock lock` first, or bind `pshell lock lock` directly.

They answer with no `power` widget in the bar at all, so a keybind does not
have to care what is on your bar today. Only `toggle` needs the widget, since
the widget is what draws the menu; without one it says so and names the five
actions instead.

## Keybind sheet

What is bound to what, read from the compositor rather than from a config
file — `hyprctl binds -j`, re-read every time the panel opens.

```json
{ "type": "keybinds" }
```

Grouped by modifier, with a filter field that matches the key combination and
the description both. `/` jumps to the filter, Escape clears it, the arrows
scroll the list.

Reading the compositor means the list of *keys* cannot go stale. What a bind
*does* is a different question, and Hyprland can only answer it when the bind
itself carries a description. A bind whose action is a Lua closure has none —
on the machine this was written on, 115 of 119 binds are like that, and they
report a dispatcher of `__lua` with a number after it. pshell never prints
that: a row it cannot describe shows the key combination and says it is not
labelled, and the panel says how many rows are in that state.

Two ways to fix it, and the first is better:

- **Describe the bind where it is bound.** Hyprland's Lua API takes it:
  `hl.bind("SUPER + D", hl.dsp.exec_cmd("pshell launcher"), { description =
  "Launcher" })`. In hyprlang, `bindd = SUPER, D, Launcher, exec, pshell
  launcher`. The description lives beside the bind, so rebinding the key
  carries it along.
- **Name it in pshell**, for binds in a file you do not own:

  ```json
  "keybinds": {
    "labels": {
      "SUPER+D": "Launcher",
      "SUPER+SHIFT+Return": "Terminal"
    }
  }
  ```

  The key is the combination exactly as the panel prints it on the row, so a
  label is copied off the screen rather than derived by hand. Matching is
  case-insensitive. Hyprland's own description always wins over a label.

### Commands

```
pshell keybinds toggle    open or close the sheet
```

The command answers on any bar — the service owns the target, so a keybind
does not have to care what is in your bar today. The *sheet* is drawn by the
widget, so without `{"type": "keybinds"}` in a section the command tells you
which entry to add rather than opening anything.

## Launcher

pshell does not have a launcher and is not going to grow one.
[walker](https://github.com/abenz1267/walker) is better at fuzzy search than
anything worth writing here, so this is the one job pshell hands to someone
else outright:

    pshell launcher       walker, however you have configured it

It runs `exec walker` rather than calling into the shell — the only command
in `bin/pshell` that does. It exists so a keybind can say `pshell launcher`
and not name a third-party binary, which is what makes walker replaceable
later without touching your Hyprland config.

You need both halves. On Arch:

```sh
sudo pacman -S walker
yay -S elephant-all-bin
elephant service enable && systemctl --user start elephant.service
```

elephant is a systemd **user** service and must run with your session's
environment; `elephant service enable` writes the unit for you but does not
start it, hence the second command. walker without elephant starts and finds
nothing. Run `walker --gapplication-service` from your compositor's startup
if you want the window to appear instantly rather than cold-starting GTK.
Without walker on your `PATH`, `pshell launcher` says so and names what to
install rather than dying at `exec`.

The launcher wears the wallpaper's colours through the `walker` template
above. Render it before setting `theme = "pshell"`: walker has no fallback
for a theme directory that is not there, and comes up with no stylesheet at
all rather than with its own. And if you run walker as a service, restart it
once after that first render — walker re-reads the stylesheet on every open,
but it looks for the theme *directory* only at startup, so a service that
came up before the directory existed stays unstyled however many times you
re-render.

`pshell launcher` runs `walker` with no arguments, so which providers it
searches is walker's default and then yours, in `providers.default` in your
own config — pshell does not name one. That keeps `=` for the calculator,
`.` for emoji, `:` for the clipboard and the rest of walker's prefixes alive
inside the bind, which naming a provider would switch off wholesale.

## Clipboard

pshell keeps its own clipboard history, modelled on Omarchy's clipboard
panel. No cliphist, and no daemon: the shell itself runs two
`wl-paste --watch` processes, one for text and one for PNG images, as its own
children, and the kernel takes them down with it however it exits.

    pshell clipboard                 # open or close the panel; bind it

Type to filter. Arrows, Page Up/Down and Home/End move. **Enter** pastes the
entry into the window you came from, **Shift+Enter** copies it without
pasting, **Ctrl+P** pins or unpins it, **Delete** forgets it,
**Shift+Delete** forgets everything but the pins after asking, and **Escape**
clears the filter, then closes. Images show as thumbnails with a larger
preview of the selected one, and files copied from a file manager show by
name.

Pinned entries stay until you forget them. They are listed first, with a pin
beside them, and searched like the rest. The cap never counts them, so no
amount of copying pushes one out, and copying a pinned entry again leaves it
pinned and where it was instead of adding it twice. Images can be pinned too,
and their file stays as long as the pin does. Delete on a pinned entry asks
before forgetting it; unpinning puts it back at the top of the rolling
history, where it ages out like any other copy. With `historySize` at 0
nothing unpinned is kept, so there unpinning forgets the entry, and the panel
asks first as Delete does.

Pasting puts the entry back on the clipboard and sends Shift+Insert, which
every app reads as paste. It sets the primary selection too, because kitty,
alacritty and ghostty paste the *primary* selection on Shift+Insert.

A bind, in Lua:

```lua
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("pshell clipboard"), { description = "Clipboard" })
```

What it does not record: anything a password manager marks as secret.
KeePassXC and friends say so on the clipboard, and those copies never reach
the history file. Nor text copies over 1 MiB, which are skipped whole rather
than kept cut short.

The history is `~/.local/state/pshell/clipboard/history.json`, newest first,
and images are kept beside it in `images/`, stored once each under their
sha256. The `clipboard` directory is made `0700` and its files `0600`, so on
a home other users can read, they still cannot read your copies. Copying
something already in the history moves it to the top instead of adding it
twice. Forgetting an entry deletes its image file. A pinned entry is saved
with `"pinned": true`; a history from before pins existed loads as it is.

Whenever the newest copy is forgotten, the clipboard itself is emptied too:
deleting it, pinned or not; unpinning it with `historySize` at 0; Shift+Delete
or `clear`, unless the newest copy is pinned and so kept; and `clearAll`,
always. The copy is still sitting there otherwise, and the shell records
whatever is on the clipboard each time it starts or reloads — a password you
just deleted would come straight back.

```jsonc
"clipboard": {
  "historySize": 500     // how many unpinned copies to keep; 0 turns recording off
}
```

Lowering `historySize` forgets the oldest copies past the new cap straight
away, or at the next start if the shell was not running. Zero stops the
watchers and forgets every copy that is not pinned. Pins stay, because each
was kept on purpose; `pshell clipboard clearAll` forgets them too.

You need `wl-clipboard` and `wtype`, plus `perl` (it decodes the UTF-16 some
apps copy) and `setpriv` from util-linux, which most installs already have.

Every part of it answers over IPC, panel or no panel:

    pshell clipboard toggle          # also open / close
    pshell clipboard count           # how many copies are kept, pins included
    pshell clipboard history 20      # the pins, then the twenty newest copies, numbered
    pshell clipboard copy 3          # put number 3 back on the clipboard
    pshell clipboard remove 3        # forget number 3, pinned or not
    pshell clipboard pin 3           # pin number 3
    pshell clipboard unpin 0         # unpin number 0 (forgets it if historySize is 0)
    pshell clipboard pinned          # just the pinned ones, same numbers
    pshell clipboard clear           # forget everything but the pins, without asking
    pshell clipboard clearAll        # forget the pins too

`history` lists the pinned entries first and then the rest, newest first, in
the panel's order, and every command takes the numbers it prints. A pinned
line's preview starts with `[pin] `. The number counts only the copies after
the pins, so `history 20` is every pin and then the twenty latest copies,
however many pins there are; the panel likewise shows every pin and fifty
others. `pinned` prints the first lines of it, so its numbers are the same.
Pinning, unpinning and forgetting move entries, so list again before using a
number twice.

`copy` only copies. From a script there is no telling which window would get
a pasted keystroke, so pasting is the panel's job.

## Notifications

pshell serves `org.freedesktop.Notifications` itself. No `mako`, no
`swaync`, no `dunst` — the toasts are pshell widgets wearing pshell's
palette, and if another daemon is running it must be stopped first, because
two servers cannot hold the DBus name at once.

Toasts stack in the corner opposite the bar, newest at the screen edge, on
the overlay layer so a fullscreen window does not hide them. At most
`maxVisible` are up at once (default 5); the rest wait behind a "+N more"
row. Hovering a toast pauses its countdown. Left click invokes the
notification's default action if it declared one and dismisses otherwise,
middle click always dismisses, actions render as buttons, and a
notification that takes an inline reply gets a text field — which only
takes the keyboard when you click into it.

Timeouts are per urgency, in seconds, and zero means never:

```jsonc
"notifications": {
  "timeout": { "low": 5, "normal": 5, "critical": 0 },
  "maxVisible": 5,
  "historyDepth": 100,
  "position": "auto",          // opposite the bar; or "top" / "bottom"
  "muted": ["some-desktop-entry"]
}
```

Critical defaults to zero on purpose: a critical notification that quietly
vanishes defeats the urgency level.

The bar widget is `{ "type": "notifications" }` — a bell with the unread
count that opens the history panel: do-not-disturb, clear-all, and every
kept notification grouped by app, with the actions still clickable while
the notification is alive. History survives restarts in
`~/.local/state/pshell/notifications.json`; do-not-disturb does not
survive them, deliberately, and while it is on notifications still land in
history — only the toast is suppressed. Muted apps behave the same way.

Everything answers on one IPC target, widget or no widget:

    pshell notifications toggle      # the history panel; bind SUPER+N to this
    pshell notifications dnd toggle  # or: dnd on / dnd off
    pshell notifications count       # unread since the panel was last open
    pshell notifications dismissAll  # close every live notification
    pshell notifications history 10  # the last ten, one per line
    pshell notifications dismiss 42  # one, by id
    pshell notifications invoke 42 default   # a notification's action, by name

## Settings

`pshell` ships a settings window. Open it from the gear in the bar
(`{ "type": "settings" }`), from the control centre, or with:

    pshell settings toggle

Five pages: **Wallpaper** — the thumbnail grid documented above —
**Theme** — scheme, prefer, mode and the live palette — **Notifications** —
toast lifetimes, stack size, position, history depth and per-app muting —
**Weather** — place, exact coordinates, units, refresh interval, how many
hours the panel shows and the current reading with a Refresh now beside it
— and **About**, the facts neofetch prints plus where pshell keeps its files.
`pshell settings open theme` lands on a named page directly.

**It writes `config.json`.** Until this existed, nothing in the shell ever
rewrote your config, and the only thing pshell saved for itself went to
`state.json`. That has changed: the settings app owns `config.json`. The
first time it saves, the file is normalised to two-space JSON. Nothing is
lost — JSON has no comments — but your key order and hand formatting will
not survive it.

## Lockscreen

A lockscreen drawn by pshell itself, on `ext-session-lock`, authenticating
against PAM. No `hyprlock`.

    pshell lock

**pshell does not decide when to lock, and will not.** Omarchy splits that
job — `hyprlock` draws and authenticates, `hypridle` owns every timer and
bridges logind's `Lock` signal to it — and pshell takes only the first half.
Screen blanking, keyboard backlight and sleep inhibition are a daemon's job.

So keep `hypridle`, and point it here:

    general {
        lock_cmd = pshell lock
        before_sleep_cmd = loginctl lock-session
        inhibit_sleep = 3
    }

That is the whole integration. Suspend, lid close and the idle timeout all
already run through `loginctl lock-session` → `hypridle` → `lock_cmd`, so
none of them need anything else. Locking twice is a no-op, which matters
because an idle timeout landing on top of a manual lock is normal.

If the machine stops locking on idle, check that `hypridle` can find the
command: it is started by your session manager, not by your login shell, and
does not necessarily have `~/.local/bin` on its `PATH`. Spell it out if not:

    lock_cmd = ~/.config/quickshell/pshell/bin/pshell lock

### Looking at it without locking yourself out

    pshell preview

Draws the lockscreen in an ordinary window with authentication stubbed —
submitting always fails, so the error state is reachable without knowing a
wrong password — and Esc closes it. It renders the same component the real
surface does, so it cannot drift from the thing it is previewing.

Use it. A native lock is the one part of a shell you cannot iterate on
safely: if the QML is broken, `ext-session-lock` does exactly what it
promises and the session stays locked and blank.

**If that happens**, the way back is a TTY:

    Ctrl+Alt+F2, log in, then:  loginctl unlock-session

The real lock has no Esc, no grace period and no timeout. That is the point
of it.

### Settings

Everything lives under `lock` in `config.json`, and every key is optional:

```json
{
  "lock": {
    "wallpaper": "~/Pictures/wall.png",
    "blur": true,
    "blurAmount": 0.75,
    "dim": 0.45,
    "showClock": true,
    "clockFormat": "HH:mm",
    "dateFormat": "dddd, d MMMM",
    "showAvatar": true,
    "showStatus": true,
    "placeholder": "Enter Password",
    "pamService": "login"
  }
}
```

| | | default |
|---|---|---|
| `wallpaper` | image behind the lock | whatever `wallpaper` is |
| `blur` | blur that image | `true` |
| `blurAmount` | how far, 0 to 1 | `0.75` |
| `dim` | scrim over the image, 0 to 1 | `0.45` |
| `showClock` | the time and date | `true` |
| `showAvatar` | your picture and name | `true` |
| `showStatus` | battery, network, layout | `true` |
| `pamService` | which `/etc/pam.d` stack to run | `login` |

The wallpaper defaults to the bar's own, which is the file matugen already
derives the palette from — so the picture and the colours on top of it come
from one source and cannot disagree. Colours are not settable here: the lock
paints itself from the `lock.*` tokens, so it restyles with everything else.

`pamService` is `login` because `/etc/pam.d/hyprlock` and
`/etc/pam.d/swaylock` are both nothing but `auth include login`. It is the
same stack they run, and it needs no file installed as root — which a shell
you clone into `~/.config` cannot ask for.

Your face comes from `/var/lib/AccountsService/icons/$USER`, then `~/.face`,
then `~/.face.icon`. With none of them, the avatar is left out.

## AI usage

How much of your coding agents' allowances you have spent, in the bar and in a
panel. The shell parses nothing itself. `cmd/pshell-agents` walks Claude Code's
session logs, Codex's rollouts and the Fireworks billing API, and writes one
JSON record per provider into `~/.local/state/pshell/agents/usage/`. pshell
reads those files, watches them, and runs that program on a timer. Without it
on your PATH the widget takes itself out of the bar rather than showing an
error.

It is the one part of pshell that is compiled. Build it with Go 1.24 or newer
and put it anywhere on your `$PATH`:

```sh
cd ~/.config/quickshell/pshell
go build -o ~/.local/bin/pshell-agents ./cmd/pshell-agents
```

It reads what it finds and skips what it does not, so nothing else is
required — but it does shell out to `sqlite3` to read
[opencode](https://github.com/sst/opencode)'s message database, which is the
only place a subscription spent entirely through opencode is recorded. Without
`sqlite3` installed the other sources still count and opencode's are missing.

```json
{
  "type": "aiUsage",
  "refreshIntervalSec": 900,
  "barSource": "max",
  "warnThreshold": 85,
  "defaultTab": "",
  "hideWhenIdle": false
}
```

Which providers exist is whatever is in that directory. Drop a fourth record in
and a fourth tab appears; nothing here carries a list of providers to keep in
step with the tool that writes them.

`barSource` decides what the bar says. `max`, the default, is the single
tightest window anywhere, wearing that provider's mark — the number that is
actually about to stop you, whoever it belongs to. A provider id pins the bar to
that one. `all` puts every provider up there, tightest first, which is the
widest option and the only one that tells you nothing new at a glance. The
number turns red past `warnThreshold`, and reads `—` for a provider that reports
no window at all. The tooltip spells out which window it is and when it comes
back.

The panel opens on a tab strip of one tab per provider, each wearing its mark
and nothing else, because a row of names is a row too wide for the gauges
underneath. Left and right walk the strip. `defaultTab` takes a provider id;
left unset the panel opens on whichever provider is closest to its limit, which
is the one the bar is already pointing at, so the click answers the question the
bar just raised.

A tab leads with its provider's name and plan, then its windows with the reset
spelled out. Providers report different numbers of them — Claude three, Codex
one, Fireworks none — so a tab lays out however many there are rather than
assuming a pair. A provider with none says so; Fireworks bills a balance and has
nothing to run out of, which is an answer rather than a gap. Then seven days of
tokens as seven columns. The columns are
scaled against the tallest day in the window rather than any absolute figure,
since the comparison anyone actually makes is against their own week. Today is
drawn in the accent colour, so a short column late in the evening reads as the
day it is rather than as the week's quietest. Below that is
where the tokens went, by model, and the day's sessions.

The panel is one width on every tab. Only the height changes, and it eases, so
moving between tabs reads as the same panel rather than one jumping out from
under the pointer.

Records are watched, so a run of the updater redraws the panel without anything
polling it. The timer defaults to fifteen minutes, and opening the panel is
worth a run on top of that. Set `hideWhenIdle` to take the widget out of the bar
until something has actually been spent.

The marks are shipped in `Widgets/AiUsage/assets/`, keyed by the provider id.
They keep their brand colour rather than being tinted to the foreground: five
identical grey shapes is not something you can read at a glance. Codex's is a
monochrome glyph and ships in both cuts, so it follows the palette the rest of
the shell is drawn in. A provider with no mark of ours falls back to a Material
Symbol, so a record we have never seen still gets a row.

## Weather

An icon and a temperature in the bar, and the detail behind them. Add the
widget to a section and put its settings under a `weather` block:

```json
{
  "right": [
    { "type": "weather", "showLabel": false }
  ],
  "weather": {
    "location": "Bengaluru",
    "units": "metric",
    "intervalMin": 15,
    "hourlyHours": 12
  }
}
```

The settings live in their own block rather than on the widget because one
shell fetches once, however many monitors it draws a bar on. Only `showLabel`
and `panelWidth` are the widget's, since they are about what that bar looks
like.

| Key | What it does |
|---|---|
| `location` | A place name. Resolved to coordinates once and remembered. |
| `latitude` / `longitude` | Exact coordinates. **These beat `location`.** |
| `units` | `metric` or `imperial`. Default `metric`. |
| `intervalMin` | Minutes between refreshes. Default 15, floored at 5. |
| `hourlyHours` | Hours in the panel's hourly row, counting the current one. Default 12, at most 24; `0` hides the row. |

Coordinates win because a coordinate is unambiguous and a name is not. There
is more than one Springfield and the geocoder hands back the biggest; if it has
handed you the wrong one, this is how you say exactly where you are. Set both
and the name is still used as the label, so the panel says "Cambridge" and the
forecast is for the Cambridge you meant.

`pshell weather setLocation Mysuru` writes the name into `config.json` and
clears any coordinates with it — leaving them would make the new name silently
do nothing.

The settings app's Weather page edits the same block, and its buttons call the
same functions the commands do, so the coordinate rule above holds whichever
way you ask.

The floor under `intervalMin` is five minutes. Open-Meteo is free and
unauthenticated, and pointing tight loops at a service like that is how it
stops being either. Fifteen is also as fine as the data gets: the forecast
model itself moves in fifteen-minute steps.

A reading older than two refresh intervals goes dim in the bar and grows a
`STALE` pill in the panel, which always says how old it is. The last good
reading is kept on disk, so a shell started with the network down shows
the last thing it knew rather than a blank — with its age on it, which is the
half that matters.

### The next hours

The panel shows the hours ahead in rows of six: the time, an icon that turns
to the moon after the location's own sunset, the temperature, and the chance
of rain when it is 20% or more. They come in the same request as everything
else, so the row costs nothing extra, and it moves on at the top of each hour
without waiting for a fetch.

It starts at the hour it is now *where the forecast is for*, not where your
machine is: a laptop in New York showing Tokyo starts at Tokyo's hour. The
times are 12-hour if your `clock` widget's `format` (or else the `calendar`'s
`timeFormat`) has an AM/PM marker in it, and 24-hour otherwise.

One thing to know around a clock change. Open-Meteo writes every hour of a
reply with the offset that was in force when it answered, so in the day
before the clocks go forward or back, the hours past the change are labelled
one hour off — 02:00 appears on the night it does not exist. Which hour is
"now" is never off, because that is worked out from the instant and not the
label, and the next fetch after the change labels everything right.

### What it sends, and to whom

This widget makes a network request from your machine to a third party, so it
should say so here rather than leave you to find it in a packet capture.

It talks to [Open-Meteo](https://open-meteo.com), which needs no API key and no
account. Two endpoints:

- `geocoding-api.open-meteo.com` — once per `location` you set, and never
  again while it stays the same. It receives the place name you typed.
- `api.open-meteo.com` — every `intervalMin` minutes while the shell runs. It
  receives your coordinates, rounded to whatever precision the geocoder gave
  or you wrote, and nothing else. No identifier, no account, no cookie.

Set `latitude` and `longitude` yourself and the geocoder is never contacted at
all. Round them off if you would rather not hand over your street.

Nothing repeats without the widget. A bar with no `weather` in it never starts
the refresh timer, so it makes no requests on its own — but the commands below
still work, and `pshell weather refresh` fetches once when you ask. Only
`toggle` needs the widget, since the widget is what draws the panel; without
one it says so rather than pretending.

### Commands

```
pshell weather refresh                fetch now
pshell weather current                one line: temperature, condition, place, age
pshell weather hourly                 up to the next 24 hours, one line each
pshell weather toggle                 open or close the panel
pshell weather setLocation Mysuru     re-resolve and refetch
pshell weather setCoordinates 12.97 77.59   pin the exact spot
pshell weather clearCoordinates       back to deciding by name
```

`hourly` prints up to a day whatever `hourlyHours` says, since that setting is
about room in the panel. Fewer when the last reading is old enough that the
forecast runs out first, and none, with `error: no hourly forecast yet` and a
non-zero exit, when there is no reading or no hour left in it.

Each line is the hour as `HH:MM`, the temperature, the chance of rain and the
condition, two spaces apart, with the condition last because it is the one
with spaces in it:

```
21:00  24°C  40%  Light rain
22:00  23°C  10%  Overcast
```

`setCoordinates` takes both halves in one call: a latitude on its own is not a
place, so it would land in `config.json` and change nothing on screen.

The last reading is kept in `~/.local/state/pshell/weather.json`; the resolved
coordinates go in `state.json` beside the rest of what the shell remembers.
Delete either and it is rebuilt on the next fetch.

## Icons

Two sets, addressed two ways.

Most widgets use icons from your icon theme by name, so they follow whatever
you have set rather than shipping their own artwork. Only standard freedesktop
names are used, which every mainstream theme provides. `Services/Icons.qml`
resolves a name to a file and `Ui/BarIcon.qml` draws it, recoloured to the
foreground.

The control centre uses [Material
Symbols](https://fonts.google.com/icons) Rounded instead — the same set, and
the same choice of icon for each state, that
[DMS](https://github.com/AvengeMedia/DankMaterialShell) draws with. The font is
shipped in `assets/`, so that half of the shell looks right on a machine with
no icon theme installed at all. `Services/Glyphs.qml` names a glyph and
`Ui/MaterialIcon.qml` draws it:

```qml
MaterialIcon {
    name: Glyphs.battery(45, false)   // "battery_3_bar"
    filled: true
    size: 18
}
```

`Ui/BarIconButton.qml` takes either kind: `iconSource`/`iconSources` for themed
files, `iconName`/`iconNames` for symbols.

Qt needs a platform theme to know which icon theme is in use. Without one it
finds almost nothing, so `shell.qml` sets `QT_QPA_PLATFORMTHEME=gtk3`, which
reads the GTK setting. If your themed icons are missing, that is the first
thing to check; Material Symbols are unaffected, because they never leave the
repository.

## A widget in Go

Print and exit.

```go
package main

import "fmt"

func main() {
	fmt.Println(`{"text":"gpu 61C","tooltip":"NVIDIA"}`)
}
```

Build it, put it on your `$PATH`, and point `exec` at it. For streaming, loop
and keep printing lines.

## What I took from where

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (MIT) is
what I used before this. It is around 500 QML files on top of a Go daemon. Its
AxisContext is the simplest way I have seen to support all four screen edges
without writing every widget twice. One object holds the edge name and a flag
for whether the bar is vertical, and each widget reads it to pick a row or a
column. pshell copies that idea.

[Omarchy](https://github.com/basecamp/omarchy) 4 (MIT) replaced Waybar, Walker,
Mako, SwayOSD, hyprlock, hypridle and swaybg with one Quickshell process. Its
bar hides by moving the window just past the screen edge instead of closing it.
The comment in their Bar.qml explains why. Closing the window frees the layer
surface and everything drawn in it, so showing the bar again has to rebuild all
of that. They measured about 150ms to rebuild against 20ms to close. That was
the most useful thing I read in either project. The Waybar JSON format also
comes from them.

Both are much bigger projects than this one, and both are worth reading if you
are curious about Quickshell.

## Why there are two kinds of widget

DankMaterialShell ships a Go daemon that every widget talks to. I did not want
to maintain a daemon, so most things here are a script instead. A clock, a load
average, a disk check: none of those need anything more than a command and a
number.

That falls apart once a widget needs a live connection. A system tray has to
speak DBus, and volume has to hold a Pipewire handle. Polling a script cannot
do either, so those are QML.

Rather than invent a format for the QML half, I used Omarchy's, which means
their widgets work here too. Reusing a format costs me nothing and gets pshell a
widget ecosystem it did not have to grow.

The script half has a real cost. A polled widget runs on a timer whether
anything changed or not, and each run starts a new process. Twenty widgets on a
one second interval will show up in your process list. That is why streaming is
there, and I use it more often than polling.

## License

MIT.

Parts of this are Omarchy's, MIT licensed and vendored unmodified. See
[NOTICE.md](NOTICE.md).
