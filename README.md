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

## Widgets

Seven are built in. These hold a live connection to something, a Hyprland socket,
DBus, UPower, so none of them work as a polled command.

| type | What it does |
|---|---|
| `workspaces` | Hyprland workspaces. Click one to switch. |
| `clock` | `format` takes a Qt date format string. |
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

This covers widgets that draw in the bar. `BarWidget`, `WidgetButton`,
`BarIconButton`, `BarIndicator`, and the `Color`, `Style`, `Border` and `Util`
singletons are implemented. Widgets that open a popup panel import roughly ten
more types from Omarchy's UI kit, and those do not load here. Reimplementing
all of it would mean rebuilding their shell, which is not what this is for.

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

Widgets use icons from your icon theme by name, so they follow whatever you
have set rather than shipping their own artwork. Only standard freedesktop
names are used, which every mainstream theme provides.

Qt needs a platform theme to know which icon theme is in use. Without one it
finds almost nothing, so `shell.qml` sets `QT_QPA_PLATFORMTHEME=gtk3`, which
reads the GTK setting. If your icons are missing, that is the first thing to
check.

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
