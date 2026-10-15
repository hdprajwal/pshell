# Control centre

One panel for the things you change often. Add it to your bar:

```json
{ "type": "controlCenter" }
```

In the bar, right click mutes the output and scrolling changes the volume. Left click opens the panel. `pshell controlcenter toggle` opens it from a keybind.

The panel has three parts:

1. A header with who is logged in and how long the machine has been up, plus lock, power off and log out buttons.
2. Sliders for volume, screen brightness and keyboard backlight.
3. A grid of tiles: Wi-Fi, Bluetooth, audio output, microphone, night mode and dark mode.

## Settings

```json
{
  "type": "controlCenter",
  "name": "Alex",
  "avatar": "~/.face",
  "audioSettings": "pavucontrol"
}
```

| Setting | What it does | Default |
|---|---|---|
| `name` | The name in the header | `$USER` |
| `avatar` | A picture for the header | none |
| `width` | Width of the panel, in pixels | `380` |
| `audioSettings` | A command for the gear in the audio device picker, for example `pavucontrol` | none, and no gear |
| `lock` | Command for the lock button | the [power menu](session.md#power-menu)'s `lock` |
| `power` | Command for the power off button | the power menu's `poweroff` |
| `logout` | Command for the log out button | the power menu's `logout` |
| `nightMode` | A command for the night mode tile, or `false` to hide it | pshell's [nightlight](session.md#nightlight) |
| `darkMode` | `false` hides the dark mode tile | shown |
| `darkModeCommand` | A command for the dark mode tile | flips the GTK `color-scheme` |

The lock, power off and log out buttons run the same commands as the power menu, so the two always agree on what "log out" means. Set `lock`, `power` or `logout` here only to make the control centre do something different.

Power off and log out ask first. Lock does not.

## Tiles

Most tiles have two parts:

- Click the **icon** to turn the thing on or off.
- Click **anywhere else** on the tile to open its list: networks to join, devices to pair, or audio devices to switch between.

This way, a slightly wrong click opens the list instead of turning your Wi-Fi off.

### Night mode

The night mode tile is pshell's [nightlight](session.md#nightlight). It lights up while the nightlight is on, with the temperature underneath. It hides when hyprsunset is not installed.

If you warm your screen with something else, like gammastep or wlsunset, set `nightMode` to a command and the tile runs that instead. pshell cannot see the state of another program, so the tile then stays unlit. `"nightMode": false` hides the tile.

### Dark mode

The dark mode tile flips the GTK `color-scheme` setting, unless you set `darkModeCommand`. If you have not set `mode` in `config.json`, pshell follows that setting and recolours too. See [Theming](theming.md#scheme-and-mode).

Night mode and dark mode have no list, so the whole tile is the button.

## Audio devices

The audio output and microphone tiles open a device picker. It shows:

- the active device, outlined and labelled;
- every other device;
- what is playing or recording right now.

The microphone view has its own level slider, since setting the mic level is often why you opened it. Set `audioSettings` to add a gear that opens your mixer of choice.

You can pin a device. Pinned devices float to the top of the list, so a headset you switch to often does not get lost under everything else Pipewire lists. Pins are saved in `~/.config/pshell/state.json`.

## Brightness and keyboard backlight

Both need `brightnessctl`.

The brightness slider hides when there is no backlight, so a desktop PC shows no slider rather than a broken one.

The keyboard backlight slider shows when `brightnessctl` lists a light whose name ends in `kbd_backlight`, whatever the vendor prefix (`asus::`, `tpacpi::`, or none). Keyboard backlights usually have a few fixed steps rather than a hundred, so the slider snaps to the real steps.

Both answer on the command line too, so a key can reach them without opening the panel: `pshell brightness up`, `down`, `set`, `get`, and `keyboardUp`, `keyboardDown`, `keyboardSet`, `keyboardGet`. See [Commands](commands.md#brightness). These commands only exist while the control centre is in your bar.

## Volume keys

The volume, mic, brightness and media keys are not handled by pshell. The suggested setup binds them to swayosd, which pshell themes to match the bar. See [Keybinds](keybinds.md#volume-brightness-and-media-keys).
