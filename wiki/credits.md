# Credits

pshell borrows ideas and code from other projects. This page says what came from where, and why pshell has two kinds of widget. [NOTICE.md](../NOTICE.md) has the licence details for the code that is copied in.

## What I took from where

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (MIT) is what I used before this. It is around 500 QML files on top of a Go daemon. Its AxisContext is the simplest way I have seen to support all four screen edges without writing every widget twice. One object holds the edge name and whether the bar is vertical, and each widget reads it to pick a row or a column. pshell copies that idea.

Several layouts come from DMS too: the lockscreen's arrangement, the system monitor's pills, the wallpaper page's pages that slide sideways with arrow keys that walk off one page onto the next, and the choice of Material Symbols for icons. pshell draws them in its own flat style.

[Omarchy](https://github.com/basecamp/omarchy) 4 (MIT) replaced Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle and swaybg with one Quickshell process. Its bar hides by moving the window just past the screen edge instead of closing it. The comment in their `Bar.qml` explains why: closing the window frees everything drawn in it, so showing the bar again has to rebuild all of it. They measured about 150 ms to rebuild against 20 ms to close. pshell chose differently: hiding the bar unmaps its window, so the compositor also gives back the space the bar reserved and windows grow into it.

From Omarchy, pshell also takes:

- the widget manifest format, so Omarchy widgets run here;
- the `Ui` kit, copied in unchanged;
- the style token names;
- the clipboard panel's design;
- the way the lockscreen and idle daemon split their jobs.

The script widget output format is Waybar's.

The fullscreen wallpaper carousel is modelled on motor-dev's wallpaperCarousel plugin for DMS and Noctalia. The volume tone, and its timing, come from [omarchy-volume-beep](https://github.com/GruperTal/omarchy-volume-beep), a prototype for an [Omarchy request](https://github.com/omacom/omarchy/discussions/15016).

Both DMS and Omarchy are much bigger projects than this one, and both are worth reading if you are curious about Quickshell.

## Why there are two kinds of widget

DankMaterialShell ships a Go daemon that every widget talks to. I did not want to maintain a daemon, so most things here are a script instead. A clock, a load average, a disk check: none of those need more than a command and a number.

That stops working once a widget needs a live connection. A system tray has to talk DBus, and volume has to hold a Pipewire handle. A polled script cannot do either, so those are QML.

Rather than invent a format for the QML half, I used Omarchy's, which means their widgets work here too. Reusing a format costs me nothing, and pshell gets a set of widgets it did not have to write.

The script half has a real cost. A polled widget runs on a timer whether anything changed or not, and each run starts a new process. Twenty widgets on a one second interval will show up in your process list. That is why streaming is there, and I use it more often than polling.
