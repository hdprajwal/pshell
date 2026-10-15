# Session

The smaller things that are about your session as a whole: the power menu, the keybind sheet, keeping the screen awake, the nightlight, system updates, the volume tone and the app launcher.

## Power menu

Lock, suspend, log out, restart and power off, in one panel. Add it to your bar:

```json
{ "type": "power" }
```

Log out, restart and power off ask first, because a wrong click on any of them loses whatever was unsaved. Lock and suspend do not ask, since everything is still open behind them. The three that ask are drawn in the urgent colour, so you can see which half is risky before the dialog says so.

Arrow keys or j and k move between rows, Enter picks one, and Escape closes.

### The commands it runs

You can change any of them under `power` in `config.json`:

```json
{
  "power": {
    "lock": "loginctl lock-session",
    "logout": "loginctl terminate-user $USER"
  }
}
```

| Key | Default |
|---|---|
| `lock` | `loginctl lock-session` |
| `logout` | `loginctl terminate-user $USER` |
| `suspend` | `systemctl suspend` |
| `reboot` | `systemctl reboot` |
| `poweroff` | `systemctl poweroff` |

None of them need root. The control centre's lock, power off and log out buttons use the same commands.

`loginctl lock-session` only locks the screen if something listens for logind's lock signal, such as hypridle. pshell does not. See [Lockscreen](lockscreen.md#locking-on-idle-and-before-sleep).

### Commands

```sh
pshell power toggle       # open or close the menu
pshell power lock         # the five actions by name, without the menu
pshell power suspend
pshell power logout
pshell power reboot
pshell power poweroff
```

**The five actions never ask first**, even the ones that cannot be undone. A keybind or a script that asks to reboot has already decided, and a dialog nobody is looking at would just leave the machine running. The dialogs belong to the panels.

The five actions work with no `power` widget in your bar. Only `toggle`, `open` and `close` need the widget, since the widget draws the menu. Without it, `toggle` does nothing. It prints nothing and exits 0; the shell's log has a warning that names the five actions instead.

## Keybind sheet

A list of what is bound to what, read from Hyprland with `hyprctl binds -j` each time it opens. Add it to your bar:

```json
{ "type": "keybinds" }
```

```sh
pshell keybinds toggle
```

Binds are grouped by modifier. The filter at the top matches both the key combination and the description. `/` jumps to the filter, Escape clears it, and the arrow keys scroll the list.

Because it reads Hyprland directly, the list of keys is always current. But Hyprland can only say what a bind does when the bind has a description. A bind whose action is a Lua function has none. pshell never shows the internal name Hyprland gives these. A row with no description shows the key combination and says it has no label, and the panel tells you how many rows are like that.

There are two ways to fix it.

**Describe the bind where you bind it.** This is the better way, since the description moves with the bind. Use `bindd` in `hyprland.conf`, or `description` in a Lua config. See [Keybinds](keybinds.md#give-your-binds-a-description) for both.

**Name it in pshell**, for binds in a file you do not own:

```json
{
  "keybinds": {
    "labels": {
      "SUPER+D": "Launcher",
      "SUPER+SHIFT+Return": "Terminal"
    }
  }
}
```

The key is the combination exactly as the sheet prints it, so you can copy it off the screen. Case does not matter. A description from Hyprland always wins over a label.

The sheet is drawn by the widget, so without `{ "type": "keybinds" }` in a section, `pshell keybinds toggle` does nothing. It prints nothing and exits 0; the reason only shows up as a warning in the shell's log.

## Idle inhibitor

Keeps the screen awake while it is on, for example while you watch a video.

```sh
pshell idle toggle        # also: on, off, isInhibited
```

Or add `{ "type": "idleInhibitor" }` to your bar and click it.

It is off after every restart. A machine that will not sleep because of something you pressed last week is a bad surprise.

On Wayland, an idle inhibitor only counts while the window that holds it is visible. One held by the bar would stop working as soon as a fullscreen window covered the bar, which is exactly when you want it. So pshell holds it on its own tiny transparent window, on the layer above fullscreen windows, which only exists while the inhibitor is on.

It needs something that respects idle inhibitors, such as hypridle or swayidle. Without one, the switch does nothing.

## Nightlight

A warmer screen in the evening, using Hyprland's [hyprsunset](https://github.com/hyprwm/hyprsunset). Install it:

```sh
sudo pacman -S hyprsunset
```

Without hyprsunset, the `nightlight` widget and the control centre's night mode tile hide, and `pshell nightlight on` says what to install and exits 1. `off` still works, since the screen is already as it should be. If you install hyprsunset while the shell is running, it works on the next try. No restart needed.

```json
{
  "right": [ { "type": "nightlight" } ],
  "nightlight": { "temperature": 4000, "start": "20:00", "end": "07:00" }
}
```

| Key | What it does | Default |
|---|---|---|
| `temperature` | Colour temperature in kelvin, from 1000 (very orange) to 6000 (barely any change). Values outside are moved to the nearest end. | `4000` |
| `start` | Time to turn on, as `HH:MM` in 24-hour local time | none |
| `end` | Time to turn off | none |

### Schedule

With `start` and `end` set, the nightlight turns on at `start` and off at `end`, going past midnight if `end` is earlier. In between, it is left alone: if you turn it off at 21:00 to watch a film, it stays off until the next `start`. Leave either out, or set them the same, for no schedule.

The clock is checked every thirty seconds, so a laptop that slept through 20:00 catches up within half a minute of waking.

Whether it is on is not saved. It is off after every restart. A schedule is how to have it come back on by itself: when the shell starts, it turns the nightlight on if the schedule says it is night. The one exception is a hyprsunset started outside pshell that is already warming the screen. pshell asks it, and shows the nightlight as on.

### Who runs hyprsunset

If hyprsunset is already running, from your Hyprland config or a systemd unit, pshell uses it. `on` sets its temperature through `hyprctl hyprsunset`, and `off` sends `identity`. pshell never stops it.

If none is running, pshell starts `hyprsunset -t <temperature>` itself. Turning the nightlight off sends `identity` and then stops it. It is tied to the shell, so if the shell exits, even by crashing, hyprsunset stops too. If hyprsunset exits on its own, pshell turns the nightlight off and logs why. It does not restart it.

If you keep hyprsunset profiles in `~/.config/hypr/hyprsunset.conf`, the hyprsunset pshell starts may read them too, and change the temperature on their schedule instead of pshell's. Use one schedule or the other.

### Commands

```sh
pshell nightlight                       # toggle
pshell nightlight on                    # prints "on 4000K"
pshell nightlight off
pshell nightlight isOn                  # true or false
pshell nightlight isAvailable           # whether hyprsunset is installed
pshell nightlight temperature           # the configured temperature
pshell nightlight setTemperature 3500   # saved to config.json
pshell nightlight status                # one line, e.g. on 4000K, hyprsunset started by pshell, hyprsunset reports 4000K
```

`setTemperature` refuses a value outside 1000 to 6000 rather than guessing what you meant.

## System updates

How many package updates are waiting, and a click to install them. pshell uses the update tool your distribution already has: [cachy-update](https://github.com/CachyOS/cachy-update) on CachyOS, or [arch-update](https://github.com/Antiz96/arch-update) on Arch. You need one of them:

```sh
sudo pacman -S cachy-update   # CachyOS
sudo pacman -S arch-update    # Arch
```

Both come with a systemd timer that checks a couple of minutes after you log in, and once a day after that. Turn it on if it is not on already:

```sh
systemctl --user enable --now arch-update.timer
```

Then add the widget:

```json
{ "right": [ { "type": "updates" } ] }
```

### How it counts

pshell does no checking of its own. The timer's check writes what it found to `~/.local/state/arch-update/` (or under `$XDG_STATE_HOME`), and pshell watches those files. So the count changes as soon as a check finishes, and the bar adds no network traffic or pacman load. Repo, AUR and Flatpak updates are counted separately and added up; the tooltip shows the split. Until the first check has run there is nothing to watch, so pshell looks for the files once a minute until they appear.

The widget hides while nothing is pending, and when neither tool is installed.

The count does not drop to zero while a check is running. pshell keeps the last finished count until the new check is done.

### Checking now

Right click the widget, or run `pshell updates refresh`. This starts the timer's own `arch-update.service`, so a refresh during the timer's check waits for that one instead of starting a second. Where there is no such service, it runs `<tool> --check` itself, with whichever of cachy-update or arch-update is installed. Like the timer, the check sends a desktop notification when the list has changed.

A refresh is refused while the updater is running, because a check then could bring back the list the update has just cleared.

A check that cannot reach the mirrors, for example when you are offline, ends with an empty list, which looks the same as "up to date". When this happens to a refresh pshell started, the count stays at the last good check and the tooltip says the last check could not reach the mirrors. A failed check started by the timer is not caught, and reads as up to date until the next one.

### Installing

Left click the widget, or run `pshell updates open`, to run the updater in a terminal. It shows the Arch news, lists what will change, asks before doing anything, and then deals with orphans, the package cache and services that need a restart. It is not a child of the shell, so restarting the bar does not interrupt it. The count falls as it works, and the widget goes away when it is done.

```json
{
  "terminal": "kitty",
  "updates": { "float": true }
}
```

`terminal` is the shell-wide setting described in [Configuration](configuration.md#terminal). For ghostty, kitty, alacritty, foot and wezterm, pshell sets the window class to `pshell.updates` and the title to "System update". Any other terminal is run as `<terminal> <your arguments> -e <tool>`, where `<tool>` is cachy-update or arch-update.

| Key | What it does | Default |
|---|---|---|
| `updates.float` | Float the updater in the middle of the screen, at 60% by 70% | `true` |

With a Lua Hyprland config, pshell adds a window rule called `pshell-updates` for the class `pshell.updates` just before it opens the window. Set `float` to `false` to leave the window to your own rules. With a hyprlang config, or another compositor, nothing is added, and the window opens wherever your compositor puts new windows.

### Commands

```sh
pshell updates                 # the status, same as pshell updates status
pshell updates status          # e.g. 4 updates (3 repo, 1 AUR), checked 2 hours ago, by cachy-update
pshell updates count           # the number pending
pshell updates list            # one per line: repo, aur or flatpak, a tab, and the update
pshell updates refresh         # check now
pshell updates open            # run the updater in a terminal
pshell updates isAvailable     # whether cachy-update or arch-update is installed
```

Bare `pshell updates` only reports. Starting an update means a sudo prompt in a terminal, and that should be asked for by name.

`open` and `refresh` fail with exit 1, and say what to install, when neither tool is installed. Install one while the shell is running and the next try works. No restart needed.

## Volume tone

After the volume changes, pshell plays one short click once the level has stayed still for 180 ms. You hear how loud it is now, and which device will play, before anything else makes a sound. Windows does the same when you let go of its volume slider. The idea and the timing come from [omarchy-volume-beep](https://github.com/GruperTal/omarchy-volume-beep).

It is on by default. It plays for any change to the default output's volume, whoever made it: the volume keys, the control centre's slider, `pshell audio`, pavucontrol, or an app.

- Dragging a slider plays one tone at the end.
- Holding a key plays after the first step and again where it stops.
- The tone plays on the output whose volume changed, at that output's volume, never louder.
- A new tone stops one that is still playing, so they never pile up.

It stays silent:

- at start, when an output first appears, and when the default output changes, including for one second after the change;
- while the output is muted, and for a mute toggle;
- at 0%, and when the level ends up where it started.

```json
{
  "volumeTone": { "enabled": true, "keys": true, "sound": "~/sounds/tick.wav", "delay": 180 }
}
```

| Key | What it does | Default |
|---|---|---|
| `enabled` | Play the tone | `true` |
| `keys` | Also play for changes made outside pshell: the volume keys, pavucontrol, apps. `false` keeps it to the control centre and `pshell audio`. | `true` |
| `sound` | A sound file of your own. One the player cannot read falls back to the default click, with a warning. | the freedesktop volume-change click |
| `delay` | Milliseconds the level must stay still, from 50 to 2000. Lower plays sooner, but may play in the middle of a slow drag. Above about 650, a held key plays only once. | `180` |

`enabled` and `keys` are also on the settings app's Notifications page.

It needs a player: `pw-play` (part of pipewire), or `paplay`, or `canberra-gtk-play`. The last one cannot pick an output and always plays on the default. The default sound comes from `sound-theme-freedesktop`. Without a player or a sound, nothing plays and the shell logs one warning.

swayosd plays no sound of its own, so with swayosd on the volume keys you hear one click. If you bind the keys to something else that also clicks, you will hear both; turn one off.

```sh
pshell audio tone                # the status, e.g. on, after 180ms, with pw-play, /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga
pshell audio tone on             # saved to config.json
pshell audio tone off
pshell audio tone toggle
pshell audio tone test           # play it once now, even when off
```

## Launcher

pshell does not have an app launcher. [walker](https://github.com/abenz1267/walker) is better at fuzzy search than anything worth writing here, so this is the one job pshell hands to another program.

```sh
pshell launcher
```

This runs `walker`, with no arguments. It is the only `pshell` command that is not an IPC call. It exists so your keybind says `pshell launcher` and not the name of another program. If pshell ever moves to a different launcher, your Hyprland config does not need to change.

You need both walker and its backend, elephant. On Arch:

```sh
sudo pacman -S walker
yay -S elephant-all-bin
elephant service enable && systemctl --user start elephant.service
```

elephant is a systemd user service. `elephant service enable` writes the service file but does not start it, which is why the second command is there. walker without elephant starts and finds nothing.

To make walker open instantly instead of starting up each time, run `walker --gapplication-service` from your compositor's startup.

If walker is not installed, `pshell launcher` says so and names what to install.

walker uses the wallpaper's colours through the `walker` theme template. See [Theming](theming.md#what-gets-generated) for how to turn that on, and the note about restarting the walker service once.

Because `pshell launcher` names no provider, walker searches whatever you set in `providers.default` in your own walker config. All of walker's prefixes keep working: `=` for the calculator, `.` for emoji, `:` for the clipboard, and the rest.
