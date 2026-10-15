# Keybinds

pshell does not add any keybinds. You bind keys in your Hyprland config, and each bind runs a `pshell` command. Any command on the [Commands](commands.md) page can go on a key.

This page has two parts: a keymap to start from, and the keys that work inside pshell's panels.

## A keymap to start from

These binds are written in `hyprland.conf` syntax. Change the keys to suit you.

```text
# Panels and pickers
bind = SUPER, D, exec, pshell launcher
bind = SUPER, V, exec, pshell clipboard
bind = SUPER, N, exec, pshell notifications toggle
bind = SUPER, comma, exec, pshell settings toggle
bind = SUPER, Y, exec, pshell wallpaper carousel
bind = SUPER, X, exec, pshell power toggle
bind = SUPER SHIFT, slash, exec, pshell keybinds toggle

# Lock and the bar
bind = SUPER ALT, L, exec, pshell lock
bind = SUPER, W, exec, pshell bar toggle

# Keyboard backlight. bindel: e repeats while held, l works on the lockscreen
bindel = , XF86KbdBrightnessUp, exec, pshell brightness keyboardUp
bindel = , XF86KbdBrightnessDown, exec, pshell brightness keyboardDown
```

| Key | What it does |
|---|---|
| Super + D | App launcher (walker) |
| Super + V | Clipboard history |
| Super + N | Notification history |
| Super + , | Settings |
| Super + Y | Fullscreen wallpaper picker |
| Super + X | Power menu |
| Super + Shift + / | Keybind sheet |
| Super + Alt + L | Lock the screen |
| Super + W | Hide or show the bar |
| Keyboard backlight keys | Step the keyboard backlight |

Some of these need a widget in your bar:

| Command | Needs |
|---|---|
| `pshell notifications toggle` | the `notifications` widget (the bell), which draws the panel |
| `pshell power toggle` | the `power` widget, which draws the menu |
| `pshell keybinds toggle` | the `keybinds` widget, which draws the sheet |
| `pshell brightness keyboardUp` and `keyboardDown` | the `controlCenter` widget, since nothing else loads the brightness target |

Without the widget, the first three do nothing: they print nothing and exit 0, and the reason only shows up as a warning in the shell's log. The brightness commands say the target does not exist and exit 1. The other binds work with any bar.

### If a bind does nothing

Hyprland does not always have `~/.local/bin` on its `PATH`. If `pshell` works in a terminal but a bind does nothing, use the full path:

```text
bind = SUPER, V, exec, ~/.local/bin/pshell clipboard
```

### Give your binds a description

The [keybind sheet](session.md#keybind-sheet) shows a description next to each bind when Hyprland has one. Use `bindd` to add it:

```text
bindd = SUPER, D, Application launcher, exec, pshell launcher
```

With a Lua config, pass `description`:

```lua
hl.bind("SUPER + V", hl.dsp.exec_cmd("pshell clipboard"), { description = "Clipboard history" })
```

## Volume, brightness and media keys

pshell does not draw a popup when the volume or screen brightness changes. The suggested setup binds those keys to [swayosd](https://github.com/ErikReider/SwayOSD) instead, which changes the level and shows a popup in one call. pshell writes swayosd's stylesheet from the wallpaper colours, so the popup matches the bar. See [Theming](theming.md#what-gets-generated).

```text
bindel = , XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise
bindel = , XF86AudioLowerVolume, exec, swayosd-client --output-volume lower
bindl  = , XF86AudioMute, exec, swayosd-client --output-volume mute-toggle
bindl  = , XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle
bindl  = , XF86AudioPlay, exec, swayosd-client --playerctl play-pause
bindl  = , XF86AudioNext, exec, swayosd-client --playerctl next
bindl  = , XF86AudioPrev, exec, swayosd-client --playerctl prev
bindel = , XF86MonBrightnessUp, exec, swayosd-client --brightness raise
bindel = , XF86MonBrightnessDown, exec, swayosd-client --brightness lower
```

pshell still hears these changes. The [volume tone](session.md#volume-tone) plays after a volume key, and the bar and control centre update.

If you would rather not use swayosd, pshell has commands for the same things, without a popup. The two brightness lines need the `controlCenter` widget in your bar, as described above.

```text
bindel = , XF86AudioRaiseVolume, exec, pshell audio volumeUp
bindel = , XF86AudioLowerVolume, exec, pshell audio volumeDown
bindl  = , XF86AudioMute, exec, pshell audio toggleMute
bindl  = , XF86AudioMicMute, exec, pshell audio micToggleMute
bindel = , XF86MonBrightnessUp, exec, pshell brightness up
bindel = , XF86MonBrightnessDown, exec, pshell brightness down
```

swayosd does not know about keyboard backlights, which is why the keymap above uses `pshell brightness keyboardUp` for those.

## Keys inside panels

Once a panel is open, it takes the keyboard. These keys work in most of them.

| Key | What it does |
|---|---|
| Escape | Close the panel. In a search field, Escape clears the search first. |
| Up, Down, or j, k | Move up or down |
| Left, Right, or h, l | Move left or right |
| Enter or Space | Pick the highlighted thing |

While you are typing in a search or filter field, j, k, h and l type letters instead of moving.

Panels with their own keys:

| Panel | Keys |
|---|---|
| Calendar | Arrows, or h, j, k, l, change the month. Enter or Space goes back to this month. |
| Battery | Arrows move between power profiles. Enter picks one. |
| AI usage | Left and Right move between provider tabs. |
| Power menu | Arrows or j, k move between rows. Enter picks one. |
| Keybind sheet | `/` jumps to the filter. Escape in the filter clears it. Up and Down scroll the list. |

### Confirm dialogs

The power menu, the control centre, the clipboard and the lockscreen ask before doing something you cannot undo.

| Key | What it does |
|---|---|
| Left, Right or Tab | Move between the two buttons |
| Enter | Press the highlighted button. Cancel is highlighted when the dialog opens. |
| Escape | Cancel |

### Clipboard

The clipboard panel has its own keys for pasting, pinning and forgetting. See [Clipboard](clipboard.md#using-the-panel).

### Wallpaper carousel

| Key | What it does |
|---|---|
| Left, Right, or h, l | Move one image. It wraps around at the ends. |
| Home, End | Jump to the first or last image |
| Enter | Set the wallpaper and close |
| Escape | Close without changing anything |

### Wallpaper page in settings

| Key | What it does |
|---|---|
| Arrows, or h, j, k, l | Move around the grid. Moving past the edge goes to the next page. |
| Page Up, Page Down | Turn the page |
| Home, End | Jump to the first or last image |
| Enter or Space | Set the wallpaper |

When you edit the folder path at the top, Enter saves it and Escape puts it back.

### Lockscreen

Type your password and press Enter. The preview from `pshell preview` closes with Escape. The real lock has no Escape. See [Lockscreen](lockscreen.md).
