# pshell

pshell stands for "personal shell". It is my own desktop shell for Hyprland, built on [Quickshell](https://quickshell.org). It started as a status bar and now also does notifications, the lockscreen, the wallpaper and theming. It is inspired by [Omarchy](https://github.com/basecamp/omarchy) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

A bar widget is either a program that prints a line to stdout, or a QML file. Scripts cover the simple things, like a clock or a load average. QML covers the things that need a live connection, like the tray or volume. The QML widgets use Omarchy's format, so bar widgets built for Omarchy run here unchanged. There is no daemon: everything runs in the one Quickshell process.

## Install

On Arch or CachyOS, clone it and run the install script:

```sh
git clone https://github.com/hdprajwal/pshell ~/.config/quickshell/pshell
~/.config/quickshell/pshell/install.sh
pshell run
```

The script installs Quickshell and the programs pshell's features use, from the repos or the AUR (through yay or paru). Then it writes `~/.config/pshell/config.json`, puts the `pshell` command in `~/.local/bin`, and builds the AI usage helper. It is safe to run again. `--core` installs only what pshell itself needs, `--dry-run` shows what it would do, and `--help` lists the rest.

`~/.local/bin` must be on your `PATH` for the last line to work. `pshell run` starts the shell in the foreground; it is the same as `qs -p ~/.config/quickshell/pshell`.

To start it with Hyprland, add this to `hyprland.conf`:

```text
exec-once = qs -p ~/.config/quickshell/pshell
```

[Getting started](wiki/getting-started.md) has the details, including installing by hand, a Lua config, the optional programs each feature uses, and what to do if another shell is already running.

## What it does

- **A bar** with 23 built-in widgets, plus your own scripts and QML widgets. See [Configuration](wiki/configuration.md), [Built-in widgets](wiki/widgets.md), [Script widgets](wiki/script-widgets.md) and [QML widgets](wiki/qml-widgets.md).
- **Colours from your wallpaper**, through matugen, with matching theme files for GTK, kitty, ghostty, alacritty, btop, Zed, qt6ct, swayosd, walker and Hyprland. See [Theming](wiki/theming.md).
- **Wallpaper**, drawn by the shell itself, with a thumbnail picker and a fullscreen carousel. See [Wallpaper](wiki/wallpaper.md).
- **A control centre** with volume, brightness, Wi-Fi, Bluetooth, audio devices, night mode and dark mode. See [Control centre](wiki/control-centre.md).
- **Notifications**, served by pshell itself, with history and do not disturb. See [Notifications](wiki/notifications.md).
- **Clipboard history** with pins and image support. See [Clipboard](wiki/clipboard.md).
- **A lockscreen** that works with hypridle. See [Lockscreen](wiki/lockscreen.md).
- **A power menu, a keybind sheet, an idle inhibitor, a nightlight, system updates, a volume tone and a launcher shortcut.** See [Session](wiki/session.md).
- **Weather** from Open-Meteo, with no account needed. See [Weather](wiki/weather.md).
- **AI usage** for Claude Code, Codex, Fireworks and opencode. See [AI usage](wiki/ai-usage.md).

Everything can be driven from a keybind or a script with the `pshell` command. See [Commands](wiki/commands.md) for the full list and [Keybinds](wiki/keybinds.md) for a keymap to start from.

## Documentation

The [wiki](wiki/README.md) has a page for each feature.

[Credits](wiki/credits.md) says what came from where.

## Tests

```sh
node --test tests/*.test.mjs
```

## License

MIT.

Parts of this are Omarchy's, MIT licensed and copied in unchanged. See [NOTICE.md](NOTICE.md).
