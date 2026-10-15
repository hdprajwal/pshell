# Lockscreen

pshell draws its own lockscreen, using the `ext-session-lock` protocol, and checks your password through PAM. You do not need hyprlock.

```sh
pshell lock
```

## What it shows

The layout follows DankMaterialShell's lockscreen, drawn in pshell's flat style:

- **Top centre:** the time, large.
- **Top left:** the date.
- **Top right:** a status card with the keyboard layout, what is playing, the weather, network and volume, and the battery.
- **Centre:** your picture and the password field. Under it, a warning if caps lock is on, and what went wrong if a password fails, with an attempt count.
- **Under the field:** notifications that arrived while you were away. Only a count, or the app names. Never the text.
- **Bottom left:** suspend, restart and power off.

The status card's media part has previous, play/pause and next buttons. They work without a password, since pausing music on a locked laptop is a common thing to want. Set `showMedia` to `false` to remove them.

Suspend works straight away. Restart and power off ask first, with Cancel highlighted. Lock and log out are not offered: you are already locked, and logging out from a screen that does not know who you are is a bad idea.

Type your password and press Enter. A wrong password clears the field.

## Locking on idle and before sleep

pshell draws the lock. It does not decide when to lock. That is a job for an idle daemon. Omarchy splits it the same way: hyprlock draws and checks the password, and hypridle owns the timers.

So keep `hypridle`, and point it at pshell in `~/.config/hypr/hypridle.conf`:

```text
general {
    lock_cmd = pshell lock
    unlock_cmd = pshell unlock
    before_sleep_cmd = loginctl lock-session
    inhibit_sleep = 3
}
```

That is all. Suspend, closing the lid and the idle timeout all go through `loginctl lock-session`, then hypridle, then `lock_cmd`. Locking twice does nothing the second time, which matters because an idle timeout often lands on top of a manual lock.

`unlock_cmd` is optional. With it, `loginctl unlock-session` unlocks pshell too.

If the machine stops locking on idle, check that hypridle can find `pshell`. It is started by your session, not your login shell, and may not have `~/.local/bin` on its `PATH`. If so, use the full path:

```text
lock_cmd = ~/.config/quickshell/pshell/bin/pshell lock
```

`pshell power lock` runs `loginctl lock-session`. That only locks if something, like hypridle, listens for logind's lock signal. pshell does not listen for it. So set up hypridle as above, or bind `pshell lock` to a key directly.

## Try it without locking yourself out

```sh
pshell preview
```

This draws the lockscreen in a normal window. Every password fails, including the right one, so you can see the error state too. Escape closes it. A clear "preview" badge is shown so a screenshot of it cannot be mistaken for the real lock. It uses the same code as the real lock.

Use it whenever you change lockscreen settings. A real lock is the one part of a shell you cannot safely experiment with. If something in it breaks, the session stays locked, and the screen may be blank.

## If you get stuck

If the lockscreen will not take your password, switch to a TTY (for example Ctrl+Alt+F2), log in, and run:

```sh
pshell unlock
```

`pshell` finds the right display by itself, even from a TTY. If that does not work:

```sh
loginctl unlock-session
```

The real lock has no Escape, no grace period and no timeout. That is on purpose.

## Settings

Everything is under `lock` in `config.json`, and every key is optional:

```json
{
  "lock": {
    "wallpaper": "~/Pictures/wall.png",
    "blur": true,
    "blurAmount": 0.75,
    "dim": 0.45,
    "showClock": true,
    "clockFormat": "HH:mm",
    "dateFormat": "dddd, d MMMM",
    "showAvatar": true,
    "showStatus": true,
    "showMedia": true,
    "showPower": true,
    "notifications": "count",
    "placeholder": "Enter Password",
    "pamService": "login"
  }
}
```

| Key | What it does | Default |
|---|---|---|
| `wallpaper` | Image behind the lock | the bar's `wallpaper` |
| `blur` | Blur the image | `true` |
| `blurAmount` | How much, from 0 to 1 | `0.75` |
| `dim` | How much to darken the image, from 0 to 1 | `0.45` |
| `showClock` | Show the time and date | `true` |
| `clockFormat` | Qt format for the time | `HH:mm` |
| `dateFormat` | Qt format for the date | `dddd, d MMMM` |
| `showAvatar` | Show your picture | `true` |
| `showStatus` | Show the status card | `true` |
| `showMedia` | Show what is playing, with its buttons | `true` |
| `showPower` | Show suspend, restart and power off | `true` |
| `notifications` | `count`, `apps` (app names only) or `off` | `count` |
| `placeholder` | Text in the empty password field | `Enter Password` |
| `pamService` | Which `/etc/pam.d` file to use | `login` |

The wallpaper defaults to the bar's own. That is the image the colours come from, so the picture and the colours on top of it always match. Colours cannot be set here: the lock uses the same theme as the rest of the shell.

`pamService` is `login` because `/etc/pam.d/hyprlock` and `/etc/pam.d/swaylock` both just include `login`. It is the same check they run, and it needs no file installed as root.

Your picture comes from `/var/lib/AccountsService/icons/$USER`, then `~/.face`, then `~/.face.icon`. With none of them, it is left out.
