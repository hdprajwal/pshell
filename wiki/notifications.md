# Notifications

pshell is its own notification server. You do not need mako, swaync or dunst. Notifications pop up as pshell toasts in pshell's colours.

Only one program can be the notification server at a time. If another daemon is running, stop it first, or pshell will not get any notifications.

## Toasts

Toasts stack in the corner opposite the bar, with the newest at the screen edge. They show above fullscreen windows.

- At most `maxVisible` toasts show at once. The rest wait behind a "+N more" row.
- Hovering a toast pauses its timer.
- Left click runs the notification's default action if it has one, and closes it otherwise.
- Middle click always closes it.
- Actions show as buttons.
- A notification that takes a reply gets a text field. It only takes the keyboard when you click into it.

## Settings

All under `notifications` in `config.json`:

```json
{
  "notifications": {
    "timeout": { "low": 5, "normal": 5, "critical": 0 },
    "maxVisible": 5,
    "historyDepth": 100,
    "position": "auto",
    "muted": ["some-desktop-entry"]
  }
}
```

| Key | What it does | Default |
|---|---|---|
| `timeout.low` | Seconds a low urgency toast stays. `0` means until you close it. | `5` |
| `timeout.normal` | Seconds a normal toast stays | `5` |
| `timeout.critical` | Seconds a critical toast stays | `0` |
| `maxVisible` | Most toasts on screen at once, 1 to 20 | `5` |
| `historyDepth` | How many notifications the history keeps, up to 1000 | `100` |
| `position` | `auto` (the corner opposite the bar), `top` or `bottom` | `auto` |
| `muted` | Apps whose notifications go to history without a toast. Use the app's desktop entry name, or its app name if it has none. | none |

Critical toasts stay until you close them by default. A critical notification that disappears on its own defeats the point of it being critical.

The settings app's Notifications page has all of these, and lists the apps that have sent you notifications so you can mute them with a click.

## The history panel

Add the bell to your bar:

```json
{ "type": "notifications" }
```

It shows the number of unread notifications. Left click opens the history panel. Right click turns do not disturb on or off.

The panel has a do not disturb switch, a clear all button, and every kept notification grouped by app. Actions still work while the notification is alive.

History is saved in `~/.local/state/pshell/notifications.json`, so it survives a restart.

## Do not disturb

While do not disturb is on, notifications still go to history. Only the toast is hidden. Muted apps work the same way.

Do not disturb is not saved. It is off after every restart, so you do not miss notifications because of something you switched on last week.

## Commands

`toggle`, `open` and `close` need the bell in your bar, since the bell draws the panel. Without it they do nothing. The other commands work on any bar.

```sh
pshell notifications toggle                  # the history panel
pshell notifications dnd toggle              # or: dnd on, dnd off
pshell notifications count                   # unread since the panel was last open
pshell notifications dismissAll              # close every notification on screen
pshell notifications history 10              # the last ten, one per line
pshell notifications dismiss 42              # one notification, by id
pshell notifications invoke 42 default       # a notification's action, by name
```

See [Commands](commands.md#notifications) for the full list.
