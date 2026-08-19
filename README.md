# qsbar

My own Wayland status bar, built on Quickshell. Inspired by Omarchy and
DankMaterialShell.

A widget is any program that prints a line to stdout. qsbar runs it and draws
what it prints.

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

## Widgets

Two are built in. Workspaces reads Hyprland's socket, and the clock needs to
tick every minute. A separate program cannot do either of those cheaply.

| type | What it does |
|---|---|
| `workspaces` | Hyprland workspaces. Click one to switch. |
| `clock` | `format` takes a Qt date format string. |

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

## Why the widgets are programs

DankMaterialShell ships a Go daemon. Omarchy ships a plugin system with
manifests, entry points, a registry and a rescan command. Both are reasonable
choices for projects that size. For something I maintain alone, I wanted adding
a widget to not involve touching QML at all, so a widget became a program.

There is a real cost to this. A polled widget runs on a timer whether anything
changed or not, and each run starts a new process. Twenty widgets on a one
second interval will show up in your process list. That is why streaming is
there, and I use it more often than polling.

## License

MIT.
