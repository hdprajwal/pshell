# Built-in widgets

pshell has 23 built-in widgets. Add one to a section of `config.json` by its `type`:

```json
{ "right": [ { "type": "battery", "lowThreshold": 15 } ] }
```

Any other key on the entry is a setting for that widget. Every setting is optional.

The built-in widgets are the ones a polled command cannot do well: they hold a live connection to Hyprland, DBus, Pipewire or UPower, or they keep state between runs. For anything simpler, write a [script widget](script-widgets.md).

## All widgets

| type | What it shows | Settings |
|---|---|---|
| [`workspaces`](#workspaces) | Hyprland workspaces | none |
| [`clock`](#clock) | The time | `format` |
| [`calendar`](#calendar) | The time, with a month view on click | `format`, `timeFormat`, `dateFormat`, `firstDayOfWeek` |
| [`activeWindow`](#activewindow) | The focused window's icon, app name and title | `maxWidth`, `showIcon`, `showAppName` |
| [`microphone`](#microphone) | Whether the microphone is muted | `showVolume`, `onRightClick` |
| [`privacy`](#privacy) | A red dot while the mic or camera is in use | `showCamera`, `interval` |
| [`idleInhibitor`](#idleinhibitor) | Keeps the screen awake while on | none |
| [`nightlight`](#nightlight) | Warms the screen | none |
| [`updates`](#updates) | Pending package updates | none |
| [`systemMonitor`](#systemmonitor) | CPU, memory, temperature, disk, network | `metrics`, `diskPath`, `panelWidth` |
| [`capsLock`](#capslock) | A light while caps lock is on | none |
| [`tailscale`](#tailscale) | Tailnet state and machines | `interval`, `showName`, `maxNodes` |
| [`tray`](#tray) | System tray | `hide`, `iconSize`, `iconScale`, `spacing` |
| [`battery`](#battery) | Charge, time left, power profile | `lowThreshold`, `showPercent`, `panelWidth` |
| [`network`](#network) | Wi-Fi or wired | `showName`, `maxNetworks` |
| [`bluetooth`](#bluetooth) | Bluetooth devices | `showCount`, `maxDevices` |
| [`aiUsage`](#aiusage) | How much of your coding agents' limits is used | see [AI usage](ai-usage.md) |
| [`weather`](#weather) | Temperature and conditions | `showLabel`, `panelWidth` |
| [`controlCenter`](#controlcenter) | Sliders and quick toggles in one panel | see [Control centre](control-centre.md) |
| [`notifications`](#notifications) | A bell with the unread count | `panelWidth` |
| [`power`](#power) | The power menu | `panelWidth` |
| [`keybinds`](#keybinds) | A sheet of your Hyprland keybinds | `panelWidth`, `listHeight` |
| [`settings`](#settings) | A gear that opens the settings window | none |

Widths and heights are in pixels.

## Indicators

`privacy`, `idleInhibitor`, `nightlight` and `capsLock` are indicators. They hide when they have nothing to show, and the bar closes up the gap. To turn one back on, hover the section it is in: the hidden indicators show up dimmed, and you can click them.

## workspaces

Hyprland workspaces. Click one to switch to it. Workspaces 1 to 5 are always shown, so empty ones still have somewhere to click. Any other workspace in use is added after them.

## clock

The time, with no panel.

| Setting | What it does | Default |
|---|---|---|
| `format` | A [Qt date format](https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method) string | `ddd dd MMM  HH:mm` |

## calendar

Looks the same as `clock` in the bar. Click it to open a panel with the time large at the top, the date under it, then the month.

```json
{
  "type": "calendar",
  "format": "ddd dd MMM  HH:mm",
  "timeFormat": "HH:mm",
  "dateFormat": "dddd, d MMMM yyyy",
  "firstDayOfWeek": "monday"
}
```

| Setting | What it does | Default |
|---|---|---|
| `format` | The label in the bar | `ddd dd MMM  HH:mm` |
| `timeFormat` | The time in the panel | `HH:mm` |
| `dateFormat` | The date in the panel | `dddd, d MMMM yyyy` |
| `firstDayOfWeek` | `monday` or `sunday` | your locale's |

The arrows beside the month name change the month, and so does the scroll wheel over the days. Click the month name to come back to today. Closing and opening the panel also comes back to today.

The grid is always six rows, so the panel does not change height as you page through months.

## activeWindow

The window you are looking at: its icon, its app name and its title.

```json
{ "type": "activeWindow", "maxWidth": 400 }
```

| Setting | What it does | Default |
|---|---|---|
| `maxWidth` | Longest the title can be, in pixels. The rest is cut off. | `400` |
| `showIcon` | Show the app icon | `true` |
| `showAppName` | Show the app name | `true` |

A browser puts the whole page title in the window title, so `maxWidth` stops one tab from pushing the other widgets off the bar.

The app name comes from the app's `.desktop` file. Without one, pshell uses the last part of the app id, so `dev.zed.Zed` shows as `Zed`. Icons keep their own colours.

When nothing is focused, the widget hides.

This widget is not tied to Hyprland. It uses the wlr foreign-toplevel protocol, which any wlroots compositor supports.

## microphone

The mute state of the default input.

| Setting | What it does | Default |
|---|---|---|
| `showVolume` | Show the mic level as a percentage | `false` |
| `onRightClick` | A command to run on right click | none |

Left click mutes and unmutes. Scroll changes the level. To pick a different input device, use the [control centre](control-centre.md#audio-devices).

When the mic is muted, the icon uses the urgent colour rather than a dimmed one.

## privacy

A red dot while a program is using the microphone or the camera. Click it to see which. It hides when nothing is recording.

| Setting | What it does | Default |
|---|---|---|
| `showCamera` | Watch the camera too | `true` |
| `interval` | Seconds between camera checks | `2` |

The two halves work differently:

- **Microphone.** A recording is a Pipewire stream, so pshell hears about it at once and shows the program's name.
- **Camera.** Most programs open `/dev/videoN` directly, which sends no event. pshell checks every `interval` seconds, so the dot can be that late. It can tell the camera is in use, but not by which program.

Set `showCamera` to `false` to stop checking the camera.

## idleInhibitor

Keeps the screen awake while it is on. Click to switch. It is off after every restart.

The same switch is on the command line as `pshell idle`. See [Session](session.md#idle-inhibitor) for how it works and what it needs.

## nightlight

Warms the screen through hyprsunset. Click to switch it on or off. It hides when hyprsunset is not installed.

The temperature and schedule are set under `nightlight` in `config.json`, not on the widget. See [Session](session.md#nightlight).

## updates

How many package updates are waiting, from cachy-update or arch-update. It only shows while there are some.

- Left click runs the updater in a terminal.
- Right click checks again now.
- The tooltip splits the count into repo, AUR and Flatpak.

It hides when neither tool is installed. See [Session](session.md#system-updates).

## systemMonitor

CPU, memory and CPU temperature as small icon-and-number pills, read from `/proc` and `/sys`. Click for a panel with per-thread load, memory and swap, the temperature sensor, disk use and network speed.

```json
{ "type": "systemMonitor", "metrics": ["cpu", "ram", "temp"] }
```

| Setting | What it does | Default |
|---|---|---|
| `metrics` | Which pills to show, from `cpu`, `ram`, `temp`, `disk` and `net`. A list, or a comma-separated string. | `cpu`, `ram`, `temp` |
| `diskPath` | The filesystem the `disk` pill measures | `/` |
| `panelWidth` | Width of the panel | `300` |

The pills are always shown in the order cpu, ram, temp, disk, net. It reads every two seconds, and only while it is on screen, the panel is open, or a script asked in the last minute.

Scripts can read the same numbers with `pshell sysmon status`, `json`, `cpu`, `memory` and `temperature`, with or without the widget. See [Commands](commands.md#sysmon).

## capsLock

A caps lock light that only shows while caps lock is on. It reads the keyboard LEDs in `/sys/class/leds`, so a keyboard without a caps lock light cannot show it.

`pshell capslock status` prints `on`, `off` or `unavailable`. The lockscreen also warns when caps lock is on.

## tailscale

Your tailnet and the machines on it.

```json
{ "type": "tailscale", "interval": 10, "showName": true, "maxNodes": 8 }
```

| Setting | What it does | Default |
|---|---|---|
| `interval` | Seconds between checks | `10` |
| `showName` | Show this machine's name in the bar while connected | `false` |
| `maxNodes` | Most machines to list | `8` |

Click to open the panel. It has:

- whether you are connected, and as whom;
- a connect or disconnect button;
- an exit node picker;
- a search box and three filters;
- the machines.

Each machine shows whether it is reachable, its address with a copy button, its operating system, and the DERP relay its traffic goes through. The relay only matters when there is no direct path, which is usually when a machine feels slow.

This machine is in the list, marked `This device`, and the filter counts include it. `My Online` filters by owner, not by machine, because a tailnet can be shared and two people can both have a laptop called `dev`.

The exit node list only offers machines that advertise themselves as one. When none do, it says so.

pshell runs `tailscale status --json` every `interval` seconds and again when you open the panel. There is also a refresh button. Actions run the `tailscale` CLI. If the CLI fails, for example because `up` wants a login, its error is shown in the panel.

Copying an address needs `wl-copy`.

## tray

The system tray.

| Setting | What it does | Default |
|---|---|---|
| `hide` | Comma-separated list of tray item ids to leave out | none |
| `iconSize` | Exact icon size in pixels | `barIconSize` |
| `iconScale` | Icon size as a fraction of the bar height | none |
| `spacing` | Space between icons | `6` |

- Left click activates the item.
- Middle click runs its secondary action.
- Right click opens its menu.
- Scroll is passed through to the item.

## battery

Charge and time remaining, with a power profile picker in the panel.

| Setting | What it does | Default |
|---|---|---|
| `lowThreshold` | Percent at which it turns red, when not charging | `20` |
| `showPercent` | Show the percentage in the bar | `true` |
| `panelWidth` | Width of the panel | `360` |

Left click opens the panel. Right click shows or hides the percentage until the next restart.

## network

Wi-Fi signal, or wired.

| Setting | What it does | Default |
|---|---|---|
| `showName` | Show the Wi-Fi name in the bar | `false` |
| `maxNetworks` | Most networks to list | `8` |

Left click opens the panel, where you can scan, connect and disconnect. Right click a network in the list to forget it. Right click the bar icon to turn Wi-Fi on or off.

## bluetooth

The adapter, and connected devices with their battery level where the device reports it.

| Setting | What it does | Default |
|---|---|---|
| `showCount` | Show how many devices are connected | `false` |
| `maxDevices` | Most devices to list | `8` |

Left click opens the panel to pair, connect and disconnect. Right click a device in the list to forget it. Right click the bar icon to turn Bluetooth on or off.

## aiUsage

How much of your coding agents' usage limits you have spent. It needs a small helper program. See [AI usage](ai-usage.md).

## weather

An icon and the temperature. Click for more.

| Setting | What it does | Default |
|---|---|---|
| `showLabel` | Show the condition in the bar too | `false` |
| `panelWidth` | Width of the panel | `300` |

The place, units and refresh interval are set under `weather` in `config.json`. See [Weather](weather.md).

## controlCenter

Volume, brightness, Wi-Fi, Bluetooth, audio devices, night mode and dark mode in one panel. Right click mutes, scroll changes the volume. See [Control centre](control-centre.md).

## notifications

A bell with the number of unread notifications. Left click opens the history panel. Right click turns do not disturb on or off.

| Setting | What it does | Default |
|---|---|---|
| `panelWidth` | Width of the panel | `400` |

See [Notifications](notifications.md).

## power

Lock, suspend, log out, restart and power off.

| Setting | What it does | Default |
|---|---|---|
| `panelWidth` | Width of the panel | `220` |

The commands it runs are set under `power` in `config.json`. See [Session](session.md#power-menu).

## keybinds

Your Hyprland keybinds, grouped by modifier, with a filter.

| Setting | What it does | Default |
|---|---|---|
| `panelWidth` | Width of the panel | `520` |
| `listHeight` | Height of the list | `420` |

See [Session](session.md#keybind-sheet).

## settings

A gear that opens the settings window. It lights up while the window is open. You can also open the window from the control centre or with `pshell settings toggle`.

The settings window has five pages:

| Page | What it covers |
|---|---|
| Wallpaper | A thumbnail grid of your wallpapers. See [Wallpaper](wallpaper.md). |
| Theme | Scheme, prefer, mode, and the palette in use. See [Theming](theming.md). |
| Notifications | Toast lifetimes, stack size, position, history depth, muted apps, and the volume tone. See [Notifications](notifications.md). |
| Weather | Place, coordinates, units, refresh interval, hours shown, and the current reading. See [Weather](weather.md). |
| About | System facts like neofetch prints, and where pshell keeps its files. |

`pshell settings open theme` opens straight onto a page. The settings window saves to `config.json`; see [Configuration](configuration.md#the-settings-app-writes-this-file).
