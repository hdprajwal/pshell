# Getting started

This page covers installing pshell, starting it, installing the `pshell` command, and starting pshell with Hyprland.

## Install

You need [Quickshell](https://quickshell.org) installed. The command it gives you is `qs`.

```sh
git clone https://github.com/hdprajwal/pshell ~/.config/quickshell/pshell
mkdir -p ~/.config/pshell ~/.local/bin
cp ~/.config/quickshell/pshell/config.example.json ~/.config/pshell/config.json
ln -s ~/.config/quickshell/pshell/bin/pshell ~/.local/bin/pshell
pshell run
```

`~/.local/bin` must be on your `PATH` for the last line to work. The symlink installs the `pshell` command, described [below](#the-pshell-command). `pshell run` starts the shell; it is the same as `qs -p ~/.config/quickshell/pshell`. You should see a bar at the top of the screen. Your settings live in `~/.config/pshell/config.json`, and the bar reloads by itself when you save it. See [Configuration](configuration.md).

## Other programs

pshell itself only needs Quickshell. Some features use other programs, and each one hides itself or says what is missing when its program is not installed.

| Program | Used for |
|---|---|
| `matugen` | Colours from the wallpaper. See [Theming](theming.md). |
| `brightnessctl` | Screen and keyboard backlight. See [Control centre](control-centre.md). |
| `wl-clipboard`, `wtype`, `perl`, `setpriv` | Clipboard history. See [Clipboard](clipboard.md). |
| `hyprsunset` | Nightlight. See [Session](session.md#nightlight). |
| `cachy-update` or `arch-update` | Update count. See [Session](session.md#system-updates). |
| `walker` and `elephant` | The app launcher. See [Session](session.md#launcher). |
| `swayosd` | The popup for volume and brightness keys. See [Keybinds](keybinds.md#volume-brightness-and-media-keys). |
| `hypridle` | Locking on idle and before sleep. See [Lockscreen](lockscreen.md#locking-on-idle-and-before-sleep). |
| `vipsthumbnail` (libvips) or `magick` (ImageMagick) | Wallpaper thumbnails. See [Wallpaper](wallpaper.md). |
| `pw-play`, `paplay` or `canberra-gtk-play`, plus `sound-theme-freedesktop` | The volume tone. See [Session](session.md#volume-tone). |
| `gsettings` | Following the desktop's light or dark setting. See [Theming](theming.md#scheme-and-mode). |
| `tailscale` | The Tailscale widget. |
| `power-profiles-daemon` | The power profile picker in the battery panel. |
| NetworkManager | The network widget and the Wi-Fi tile. |
| `bluez` | The Bluetooth widget and tile. |
| Go 1.24 or newer, and `sqlite3` | The AI usage widget. See [AI usage](ai-usage.md). |

## The `pshell` command

Every way into the running shell is an IPC call. Typing the full `qs` command each time is slow, so `bin/pshell` is a small wrapper around it. The install steps above put it on your `PATH` with a symlink into `~/.local/bin`. Try it:

```sh
pshell help
pshell settings toggle
```

Without the wrapper, every `pshell x y` on this wiki is:

```sh
qs -p ~/.config/quickshell/pshell ipc call pshell.x y
```

[Commands](commands.md) lists everything it can do.

### Where it looks for the shell

The command looks for the shell in three places, in this order:

1. The checkout the script sits in. A symlink is followed first, so `<checkout>/bin/pshell` always talks to its own checkout. This makes it safe to try a second clone or a branch without uninstalling anything.
2. `$PSHELL_DIR`.
3. `~/.config/quickshell/pshell`.

If you would rather keep the script next to your config, copy it out and tell it where the checkout is:

```sh
cp ~/.config/quickshell/pshell/bin/pshell ~/.config/pshell/pshell
ln -s ~/.config/pshell/pshell ~/.local/bin/pshell
export PSHELL_DIR=~/.config/quickshell/pshell   # in your shell rc
```

`PSHELL_DIR` only matters for a copy that lives outside a checkout. It cannot point one checkout's own command at another.

### Running it from a TTY

`pshell` works from a TTY too. A TTY has no `WAYLAND_DISPLAY`, so the command finds the display your shell is running on by itself. This matters for `pshell unlock`, which is how you get back in if the lockscreen will not take your password. See [Lockscreen](lockscreen.md#if-you-get-stuck).

## Start it with Hyprland

Add this to `~/.config/hypr/hyprland.conf`:

```text
exec-once = qs -p ~/.config/quickshell/pshell
```

Or, with a Lua config (Hyprland 0.55 and later), to `~/.config/hypr/hyprland.lua`:

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/pshell")
end)
```

If another shell also starts at login, stop it, or you will get two bars. DankMaterialShell, for example, starts from a systemd unit rather than from the Hyprland config:

```sh
systemctl --user disable --now dms.service
```

pshell also serves notifications itself, so stop any other notification daemon (mako, swaync, dunst). See [Notifications](notifications.md).

## Next steps

- Add keybinds: [Keybinds](keybinds.md).
- Choose what goes in the bar: [Configuration](configuration.md) and [Widgets](widgets.md).
- Set a wallpaper and let it colour everything: [Wallpaper](wallpaper.md) and [Theming](theming.md).
- Point hypridle at the lockscreen: [Lockscreen](lockscreen.md).
