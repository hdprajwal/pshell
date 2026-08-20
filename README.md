# qsbar

My own Wayland status bar, built on Quickshell. Inspired by Omarchy and
DankMaterialShell.

A widget is either a program that prints a line to stdout, or a QML file. It
also runs bar widgets built for Omarchy, unmodified.

About 300 lines of QML.

## Install

```sh
git clone https://github.com/hdprajwal/qsbar ~/.config/quickshell/qsbar
mkdir -p ~/.config/qsbar
cp ~/.config/quickshell/qsbar/config.example.json ~/.config/qsbar/config.json
qs -p ~/.config/quickshell/qsbar
```

You need `quickshell` installed.

To start it with Hyprland, add this to `~/.config/hypr/hyprland.conf`:

```
exec-once = qs -p ~/.config/quickshell/qsbar
```

## Config

Everything is in `~/.config/qsbar/config.json`. Save the file and the bar
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
    { "exec": "qsbar-battery", "interval": 30, "onClick": "gnome-power-statistics" }
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

## Colours from the wallpaper

Set `theme` to `wallpaper` and point `wallpaper` at an image. qsbar runs
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

qsbar reads matugen's JSON straight off stdout rather than using its template
and config files, so nothing is generated on disk and there is no second file to
keep in sync. It maps `surface` to the background, `on_surface` to text,
`primary` to the accent, `error` to urgent and `outline` to dimmed text.

Because `config.json` reloads on save, a script that changes your wallpaper can
rewrite the `wallpaper` field and the bar recolours itself. There is nothing to
restart and no daemon watching anything.

`mode` takes `dark` or `light`. `matugenScheme` picks the palette algorithm,
defaulting to `scheme-tonal-spot`. `matugenPrefer` decides which source colour
wins when an image has several candidates, defaulting to `saturation`; matugen
refuses to guess without it when there is no terminal to ask.

Needs `matugen` installed. Without it the configured colours are used and a
warning is logged.

## Layout

```
shell.qml            the bar window, and the contract widgets read
Services/            singletons: config, theme, icons, audio, brightness
Components/          the shared chrome: sections, buttons, popouts, sliders
Widgets/<Name>/      one directory per widget, holding its panels too
Commons/  Ui/        the Omarchy compatibility modules
assets/              fonts qsbar ships rather than asks fontconfig for
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

Thirteen are built in. These hold something a polled command cannot: a live
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

Set `interval` to 0 and qsbar keeps the process running. Every line it prints
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
`~/.config/qsbar/widgets/` with a `manifest.json`:

```
~/.config/qsbar/widgets/gpu/
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

That manifest format is Omarchy's, and it is not a coincidence. qsbar ships
`Commons` and `Ui` modules using the same type and token names, so an Omarchy
bar widget resolves `import qs.Commons` and `import qs.Ui` against qsbar
instead. Clone one in and it runs:

```sh
git clone https://github.com/ragnacron/omarchy-workspaces-per-monitor \
  ~/.config/qsbar/widgets/omarchy-workspaces-per-monitor
```

Then add `{ "id": "ragnacron.workspaces-per-monitor" }` to a section.

Widgets that open a panel work too. Omarchy's whole `Ui` kit is vendored here
rather than reimplemented: `Panel`, `KeyboardPanel`, `Button`, `TextField`,
`Dropdown` and the rest, unmodified, so a widget written against them behaves
the same. Copying is deliberate. A reimplementation drifts, and every drift is
a widget that works there and not here.

What is qsbar's own is the bridge underneath. `Color`, `Style` and `Util`
implement the same interface Omarchy's do, but read `config.json` and the
matugen palette instead of Omarchy's theme files, so a widget written for one
shell is themed by the other. Omarchy names the readable colour `text` and
qsbar named it `foreground`; both resolve.

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
in `~/.config/qsbar/state.json`, kept separate from `config.json` so the shell
never rewrites a file you hand-edited.

Brightness needs `brightnessctl`. The slider hides itself if there is no
backlight, so a desktop shows one slider rather than a broken one.

Night mode has no standard tool, so it is whatever command you give it and the
tile is hidden until you set `nightMode`. Dark mode toggles the GTK
`color-scheme` unless you override `darkModeCommand`.

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
column. qsbar copies that idea.

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
their widgets work here too. Reusing a format costs me nothing and gets qsbar a
widget ecosystem it did not have to grow.

The script half has a real cost. A polled widget runs on a timer whether
anything changed or not, and each run starts a new process. Twenty widgets on a
one second interval will show up in your process list. That is why streaming is
there, and I use it more often than polling.

## License

MIT.

Parts of this are Omarchy's, MIT licensed and vendored unmodified. See
[NOTICE.md](NOTICE.md).
