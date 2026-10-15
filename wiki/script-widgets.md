# Script widgets

A script widget is any program that prints a line. pshell runs it and shows what it prints in the bar. This is the simplest way to add something to the bar, and it works in any language.

To add one, leave out `type` and give the entry an `exec`:

```json
{ "exec": "date +%H:%M", "interval": 60 }
```

| Key | What it does |
|---|---|
| `exec` | The command. It runs through `sh -c`, so pipes and quotes work. |
| `interval` | Seconds between runs. Leave it out, or set `0`, to stream instead. |
| `onClick` | A command to run on left click. |

## Polling

With an `interval`, pshell runs the command every N seconds and shows what it printed.

```json
{ "exec": "free -h | awk '/^Mem:/ {print \"mem \" $3}'", "interval": 5 }
```

## Streaming

With no `interval`, or `0`, pshell starts the command once and keeps it running. Every line it prints is one update.

```json
{ "exec": "my-mpris-watcher" }
```

Streaming is the better choice for anything that reacts to events. Updates show up right away, and nothing runs in between.

Polling has a cost. Each run starts a new process, whether anything changed or not. Twenty widgets on a one second interval will show up in your process list. If a widget can wait for events instead, make it stream.

## What your widget prints

Plain text is the label:

```text
cpu 42%
```

For a tooltip or a state, print JSON on one line instead:

```json
{"text": "cpu 42%", "tooltip": "load 1.2", "class": "urgent"}
```

| Field | What it does |
|---|---|
| `text` | The label |
| `tooltip` | Shown when you hover |
| `class` | `urgent` or `critical` turns the widget red |

This is the same format Waybar uses, so most Waybar custom modules work here without changes.

If the program prints nothing, or an empty line, the widget hides and the bar closes up the gap.

## A widget in Go

Print and exit:

```go
package main

import "fmt"

func main() {
	fmt.Println(`{"text":"gpu 61C","tooltip":"NVIDIA"}`)
}
```

Build it, put it on your `PATH`, and point `exec` at it with an `interval`. For streaming, loop and keep printing lines, and leave `interval` out.

## When to use something else

A script cannot hold a live connection. A system tray has to talk DBus, and a volume widget has to hold a Pipewire handle. For things like that, write a [QML widget](qml-widgets.md). [Credits](credits.md#why-there-are-two-kinds-of-widget) explains why pshell has both.
