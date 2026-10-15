# Commands

Everything pshell can do from a keybind or a script goes through the `pshell` command. This page lists every command, grouped by target. See [Getting started](getting-started.md#the-pshell-command) for how to install the command itself.

Most commands are one rewrite: `pshell <target> <method>` becomes `qs -p <checkout> ipc call pshell.<target> <method>`. To see what your running shell has, ask it:

```sh
pshell ipc show
```

## Short forms

A few commands have a bare form, so a keybind can stay short.

| Command | What it does |
|---|---|
| `pshell lock` | Lock the screen. Same as `pshell lock lock`. |
| `pshell unlock` | Unlock it again. Works from a TTY. |
| `pshell preview` | Draw the lockscreen in a window, without locking. |
| `pshell run [qs options]` | Start the shell. |
| `pshell ipc <arguments>` | Pass straight through to `qs ipc`. |
| `pshell launcher` | Open the app launcher. This runs [walker](https://github.com/abenz1267/walker); it is not an IPC call. See [Session](session.md#launcher). |
| `pshell clipboard` | Open or close the clipboard history. Same as `pshell clipboard toggle`. |
| `pshell nightlight` | Turn the nightlight on or off. Same as `pshell nightlight toggle`. |
| `pshell updates` | Print the update status. Same as `pshell updates status`. |
| `pshell audio tone` | Print the volume tone status. Same as `pshell audio tone status`. |
| `pshell help` | Print the usage text. |

## Errors and exit codes

- If the shell is not running, `pshell` says so and exits 1.
- If the target does not exist, `pshell` says so and exits 1. A target that belongs to a widget only exists while that widget is on your bar.
- The `nightlight`, `updates`, `weather` and `audio` targets answer with a line starting `error: ` when they cannot do what you asked. `pshell` prints that to stderr and exits 1, so `pshell nightlight on && ...` stops there. Other targets do not do this, because for them a line starting `error: ` can be normal output.

## A note on `show`

Several targets have a `show` method. It cannot be called from the command line: `qs ipc call <target> show` clashes with the `qs ipc show` subcommand, so it prints that target's list of methods and exits 0 without doing anything. Use `open` or `toggle`.

## audio

The default output and input. Volume is in percent.

| Command | What it does |
|---|---|
| `pshell audio volumeUp` | Raise the volume by 5 points. |
| `pshell audio volumeDown` | Lower the volume by 5 points. |
| `pshell audio setVolume 40` | Set the volume to 40%. |
| `pshell audio mute` | Mute the output. |
| `pshell audio unmute` | Unmute the output. |
| `pshell audio toggleMute` | Mute or unmute the output. |
| `pshell audio micToggleMute` | Mute or unmute the microphone. |
| `pshell audio micSetVolume 60` | Set the microphone to 60%. |
| `pshell audio tone on` | The tone after a volume change. Takes `on`, `off`, `toggle`, `test` or `status`. `on` and `off` are saved to `config.json`. See [Session](session.md#volume-tone). |
| `pshell audio status` | One line, for example `volume 40% sink "Speakers" mic 60% muted source "Mic"`. |

## bar

| Command | What it does |
|---|---|
| `pshell bar toggle` | Hide or show the bar. Prints `true` if the bar is now showing. |
| `pshell bar show` | Show the bar. Not callable from the command line, see [the note above](#a-note-on-show). |
| `pshell bar hide` | Hide the bar. |
| `pshell bar isVisible` | `true` or `false`. |

Hiding the bar is not saved. It comes back on the next start.

## brightness

The screen backlight and the keyboard backlight. Needs `brightnessctl`. See [Control centre](control-centre.md#brightness-and-keyboard-backlight).

This target only exists while the `controlCenter` widget is in your bar, because nothing else loads it. Without the control centre, `pshell brightness` says the target does not exist and exits 1.

| Command | What it does |
|---|---|
| `pshell brightness up` | Screen brighter by 5 points. |
| `pshell brightness down` | Screen dimmer by 5 points. It stops at 1%, never off. |
| `pshell brightness set 40` | Screen to 40%. |
| `pshell brightness get` | The screen brightness in percent. |
| `pshell brightness keyboardUp` | Keyboard backlight up, always at least one hardware step. |
| `pshell brightness keyboardDown` | Keyboard backlight down, always at least one hardware step. |
| `pshell brightness keyboardSet 50` | Keyboard backlight to 50%. |
| `pshell brightness keyboardGet` | The keyboard backlight in percent. |

## capslock

| Command | What it does |
|---|---|
| `pshell capslock status` | `on`, `off`, or `unavailable` when there is no caps lock light to read. |

## clipboard

The clipboard history. Numbers come from `history` and change when you pin, unpin or remove, so list again before using a number twice. See [Clipboard](clipboard.md).

| Command | What it does |
|---|---|
| `pshell clipboard toggle` | Open or close the panel. |
| `pshell clipboard open` | Open the panel. |
| `pshell clipboard close` | Close the panel. |
| `pshell clipboard count` | How many copies are kept, pins included. |
| `pshell clipboard history 20` | Every pin, then the 20 newest copies, numbered. `0` lists everything. |
| `pshell clipboard pinned` | Only the pinned entries, with the same numbers `history` uses. |
| `pshell clipboard copy 3` | Put number 3 back on the clipboard. It does not paste. |
| `pshell clipboard remove 3` | Forget number 3, pinned or not. |
| `pshell clipboard pin 3` | Pin number 3. |
| `pshell clipboard unpin 0` | Unpin number 0. If `historySize` is 0, this forgets it. |
| `pshell clipboard clear` | Forget everything except the pins. Does not ask. |
| `pshell clipboard clearAll` | Forget everything, pins too. |

## idle

Keeps the screen awake. See [Session](session.md#idle-inhibitor).

| Command | What it does |
|---|---|
| `pshell idle on` | Keep the screen awake. |
| `pshell idle off` | Let it sleep again. |
| `pshell idle toggle` | Switch between the two. |
| `pshell idle isInhibited` | `true` or `false`. |

## keybinds

The keybind sheet. The sheet is drawn by the `keybinds` widget, so without it in your bar these commands do nothing. It prints nothing and exits 0; the reason only shows up as a warning in the shell's log. See [Session](session.md#keybind-sheet).

| Command | What it does |
|---|---|
| `pshell keybinds toggle` | Open or close the sheet. |
| `pshell keybinds open` | Open the sheet. |
| `pshell keybinds close` | Close the sheet. |

## lock

See [Lockscreen](lockscreen.md).

| Command | What it does |
|---|---|
| `pshell lock lock` | Lock the screen. Calling it twice is safe. |
| `pshell lock unlock` | Unlock. Works from a TTY, for when the lockscreen will not take your password. |
| `pshell lock preview` | Draw the lockscreen in a normal window. Every password fails, and Escape closes it. |
| `pshell lock isLocked` | `true` or `false`. |

## nightlight

Needs `hyprsunset`. See [Session](session.md#nightlight).

| Command | What it does |
|---|---|
| `pshell nightlight toggle` | Turn it on or off. |
| `pshell nightlight on` | Turn it on. Prints, for example, `on 4000K`. |
| `pshell nightlight off` | Turn it off. |
| `pshell nightlight isOn` | `true` or `false`. |
| `pshell nightlight isAvailable` | Whether hyprsunset is installed. |
| `pshell nightlight temperature` | The configured temperature in kelvin. |
| `pshell nightlight setTemperature 3500` | Set the temperature, saved to `config.json`. Refuses values outside 1000 to 6000. |
| `pshell nightlight status` | One line, for example `on 4000K, hyprsunset started by pshell, hyprsunset reports 4000K`. |

## notifications

See [Notifications](notifications.md). `toggle`, `open` and `close` need the bell (the `notifications` widget) in your bar, since the bell draws the panel. Without it they do nothing. The rest work on any bar.

| Command | What it does |
|---|---|
| `pshell notifications toggle` | Open or close the history panel. |
| `pshell notifications open` | Open the history panel. |
| `pshell notifications close` | Close the history panel. |
| `pshell notifications dnd toggle` | Do not disturb. Takes `on`, `off` or `toggle`. |
| `pshell notifications count` | Unread since the panel was last open. |
| `pshell notifications history 10` | The last 10, one per line. `0` prints all of them. |
| `pshell notifications dismiss 42` | Close one notification, by id. |
| `pshell notifications dismissAll` | Close every notification on screen. |
| `pshell notifications invoke 42 default` | Run a notification's action, by id and action name. |

## power

The session menu and its five actions. The five actions never ask first, and work on any bar. `toggle`, `open` and `close` need the `power` widget, since the widget draws the menu. Without it they do nothing. It prints nothing and exits 0; the reason only shows up as a warning in the shell's log. See [Session](session.md#power-menu).

| Command | What it does |
|---|---|
| `pshell power toggle` | Open or close the menu. Needs the `power` widget in your bar. |
| `pshell power open` | Open the menu. |
| `pshell power close` | Close the menu. |
| `pshell power lock` | Run the lock command. |
| `pshell power suspend` | Suspend. |
| `pshell power logout` | Log out. |
| `pshell power reboot` | Restart. |
| `pshell power poweroff` | Power off. |

## settings

The settings window. Pages are `wallpaper`, `theme`, `notifications`, `weather` and `about`.

| Command | What it does |
|---|---|
| `pshell settings toggle` | Open or close the window. |
| `pshell settings open theme` | Open the window on a named page. |
| `pshell settings show` | Open the window. Not callable from the command line, see [the note above](#a-note-on-show). |
| `pshell settings close` | Close the window. |

## sysmon

The system monitor. These work without the widget in your bar, except `toggle`, `open` and `close`, which need the `systemMonitor` widget to draw the panel. See [Widgets](widgets.md#systemmonitor).

| Command | What it does |
|---|---|
| `pshell sysmon status` | One line: cpu, ram, temp, disk, net. |
| `pshell sysmon json` | Everything the panel shows, as JSON. Bytes and percents, not formatted. |
| `pshell sysmon cpu` | CPU use in whole percent, or `-1` if there is no reading. |
| `pshell sysmon memory` | Memory use in whole percent, or `-1`. |
| `pshell sysmon temperature` | CPU temperature in whole degrees, or `-1`. |
| `pshell sysmon toggle` | Open or close the panel. |
| `pshell sysmon open` | Open the panel. |
| `pshell sysmon close` | Close the panel. |

## theme

Colours from the wallpaper. The `set` commands write `config.json`. A value matugen would reject is ignored and nothing is written. It prints nothing and exits 0; the reason only shows up as a warning in the shell's log. See [Theming](theming.md).

| Command | What it does |
|---|---|
| `pshell theme reload` | Run matugen again now. |
| `pshell theme setScheme scheme-vibrant` | Pick the palette algorithm. |
| `pshell theme setPrefer saturation` | Pick which colour wins when an image has several. |
| `pshell theme setMode light` | `light`, `dark`, or `auto` to follow the desktop. |
| `pshell theme current` | One line: scheme, prefer, mode and wallpaper. |

## updates

Needs cachy-update or arch-update. See [Session](session.md#system-updates).

| Command | What it does |
|---|---|
| `pshell updates status` | One line, for example `4 updates (3 repo, 1 AUR), checked 2 hours ago, by cachy-update`. |
| `pshell updates count` | The number pending. |
| `pshell updates list` | One per line: `repo`, `aur` or `flatpak`, a tab, then the update. |
| `pshell updates refresh` | Check now. Answers at once; `status` says when the check is done. Fails while the updater is running. |
| `pshell updates open` | Run the updater in a terminal. |
| `pshell updates isAvailable` | Whether cachy-update or arch-update is installed. |

## wallpaper

See [Wallpaper](wallpaper.md).

| Command | What it does |
|---|---|
| `pshell wallpaper set ~/wallpapers/foo.png` | Set the wallpaper. |
| `pshell wallpaper next` | The next image in the directory. Wraps around. |
| `pshell wallpaper previous` | The previous image. |
| `pshell wallpaper random` | A random image, never the one already up. |
| `pshell wallpaper current` | The path of the current wallpaper. |
| `pshell wallpaper list` | Every image in the directory, one path per line. |
| `pshell wallpaper rescan` | Look at the directory again, after adding files. |
| `pshell wallpaper carousel` | Open or close the fullscreen picker. Prints `opened` or `closed`. |
| `pshell wallpaper carouselOpen` | Open the fullscreen picker. |
| `pshell wallpaper carouselClose` | Close the fullscreen picker. |

## weather

These work without the widget in your bar, except `toggle`, `open` and `close`. See [Weather](weather.md).

| Command | What it does |
|---|---|
| `pshell weather refresh` | Fetch now. |
| `pshell weather current` | One line: temperature, condition, place, age. |
| `pshell weather hourly` | Up to the next 24 hours, one line each. |
| `pshell weather setLocation Berlin` | Set the place by name. Clears any coordinates. |
| `pshell weather setCoordinates 52.52 13.40` | Set the exact latitude and longitude. |
| `pshell weather clearCoordinates` | Go back to using the place name. |
| `pshell weather toggle` | Open or close the panel. |
| `pshell weather open` | Open the panel. |
| `pshell weather close` | Close the panel. |

## aiusage

The `aiUsage` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell aiusage toggle` | Open or close the AI usage panel. |
| `pshell aiusage open` | Open it. |
| `pshell aiusage close` | Close it. |
| `pshell aiusage show` | Open it. Not callable from the command line. |
| `pshell aiusage hide` | Close it. |

## battery

The `battery` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell battery toggle` | Open or close the battery panel. |
| `pshell battery open` | Open it. |
| `pshell battery close` | Close it. |
| `pshell battery show` | Open it. Not callable from the command line. |
| `pshell battery hide` | Close it. |

## bluetooth

The `bluetooth` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell bluetooth toggle` | Open or close the Bluetooth panel. |
| `pshell bluetooth open` | Open it. |
| `pshell bluetooth close` | Close it. |
| `pshell bluetooth show` | Open it. Not callable from the command line. |
| `pshell bluetooth hide` | Close it. |

## calendar

The `calendar` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell calendar toggle` | Open or close the calendar. |
| `pshell calendar open` | Open it. |
| `pshell calendar close` | Close it. |
| `pshell calendar show` | Open it. Not callable from the command line. |
| `pshell calendar hide` | Close it. |

## controlcenter

The `controlCenter` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell controlcenter toggle` | Open or close the control centre. |
| `pshell controlcenter open` | Open it. |
| `pshell controlcenter close` | Close it. |
| `pshell controlcenter show` | Open it. Not callable from the command line. |
| `pshell controlcenter hide` | Close it. |

## network

The `network` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell network toggle` | Open or close the network panel. |
| `pshell network open` | Open it. |
| `pshell network close` | Close it. |
| `pshell network show` | Open it. Not callable from the command line. |
| `pshell network hide` | Close it. |

## tailscale

The `tailscale` widget's panel. This target only exists while that widget is in your bar.

| Command | What it does |
|---|---|
| `pshell tailscale toggle` | Open or close the Tailscale panel. |
| `pshell tailscale open` | Open it. |
| `pshell tailscale close` | Close it. |
| `pshell tailscale show` | Open it. Not callable from the command line. |
| `pshell tailscale hide` | Close it. |
