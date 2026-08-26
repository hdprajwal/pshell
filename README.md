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

### The `pshell` command

Every door into the shell is an IPC call, and typing the path each time gets
old. `bin/pshell` is a one-line wrapper around them:

```
pshell lock                    lock the screen
pshell unlock                  unlock it again
pshell preview                 draw the lockscreen without locking
pshell run                     start the shell
pshell settings toggle         any IPC target, by name
pshell ipc show                straight through to qs ipc
```

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

Fourteen are built in. These hold something a polled command cannot: a live
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
| `tailscale` | Tailnet state and the machines on it. Left click opens the panel to connect, disconnect and pick an exit node. `interval`, `showName`, `maxNodes`. |
| `tray` | System tray. Left click activates, middle click is the secondary action, scroll passes through, right click opens the menu. `hide` takes a comma-separated list of ids to leave out, `iconScale`, `iconSize` and `spacing` tune the layout. |
| `battery` | Charge and time remaining, plus a power profile picker. Left click opens the panel, right click toggles the percentage label. `lowThreshold` sets when it turns red, default 20. |
| `network` | Wi-Fi signal or wired. Left click opens the panel to scan, connect and disconnect, right click toggles the radio. Right click a network in the list to forget it. `showName` puts the SSID in the bar, `maxNetworks` caps the list. |
| `bluetooth` | Adapter state and connected devices, with battery level where the device reports it. Left click opens the panel to pair, connect and disconnect, right click toggles the radio. `showCount`, `maxDevices`. |
| `aiUsage` | How much of your coding agents' allowances is gone. The bar wears the tightest window across every provider; clicking it opens a tab per provider, with that provider's windows, seven days of tokens and a model breakdown. `barSource`, `warnThreshold`, `refreshIntervalSec`, `defaultTab`, `hideWhenIdle`. Hides itself where Omarchy's agent tooling is not installed. |
| `controlCenter` | Everything in one panel: session header, volume and brightness sliders, and tiles for Wi-Fi, Bluetooth, audio output and microphone. Right click mutes, scroll changes volume. |

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
machine has been up, with lock, power and logout buttons. Below that are volume
and brightness sliders, then a grid of tiles.

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
  "nightMode": "hyprsunset -t 4000",
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
backlight, so a desktop shows one slider rather than a broken one.

Night mode has no standard tool, so it is whatever command you give it and the
tile is hidden until you set `nightMode`. Dark mode toggles the GTK
`color-scheme` unless you override `darkModeCommand`, and pshell recolours with
it unless you have pinned `mode`.

Both tiles have no detail list, so the whole tile is the button rather than
just its icon.

## Settings

`pshell` ships a settings window. Open it from the gear in the bar
(`{ "type": "settings" }`), from the control centre, or with:

    pshell settings toggle

Three pages: **Wallpaper** — the thumbnail grid documented above —
**Theme** — scheme, prefer, mode and the live palette — and **About**, the
facts neofetch prints plus where pshell keeps its files. `pshell settings
open theme` lands on a named page directly.

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
panel. It parses nothing itself. Omarchy's `omarchy-agent-usage-update` already
walks Claude Code's session logs, Codex's rollouts and the Fireworks billing
API, and writes one JSON record per provider into
`~/.local/state/omarchy/agents/usage/`. pshell reads those files, watches them,
and runs that updater on a timer. Without it on your PATH the widget takes
itself out of the bar rather than showing an error.

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
