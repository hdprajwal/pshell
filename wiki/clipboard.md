# Clipboard

pshell keeps its own clipboard history. You do not need cliphist or any daemon. The panel is modelled on Omarchy's.

The shell runs two `wl-paste --watch` processes, one for text and one for PNG images. They are the shell's own child processes, so they stop when the shell stops, however it stops.

## Open it

```sh
pshell clipboard
```

That opens the panel, or closes it if it is open. Put it on a key:

```text
bind = SUPER, V, exec, pshell clipboard
```

## Using the panel

Type to filter. Images show as thumbnails, with a larger preview of the selected one. Files copied from a file manager show by name.

| Key | What it does |
|---|---|
| Up, Down | Move one row |
| Page Up, Page Down | Move six rows |
| Home, End | Jump to the first or last row |
| Enter | Paste into the window you came from |
| Shift + Enter | Copy without pasting |
| Ctrl + P | Pin or unpin |
| Delete | Forget this entry |
| Shift + Delete | Forget everything except the pins, after asking |
| Escape | Clear the filter. If the filter is empty, close. |

Clicking outside the card also closes it.

Pasting puts the entry back on the clipboard and sends Shift+Insert, which every app reads as paste. It also sets the primary selection, because kitty, alacritty and ghostty paste the primary selection on Shift+Insert.

## Pins

A pinned entry stays until you forget it.

- Pinned entries are listed first, with a pin icon, and the filter searches them like the rest.
- They do not count toward `historySize`, so no amount of copying pushes one out.
- Copying a pinned entry again leaves it pinned, in its place, instead of adding it twice.
- Images can be pinned too. Their file stays as long as the pin does.
- Delete on a pinned entry asks first.
- Unpinning puts the entry back at the top of the normal history, where it ages out like any other copy. With `historySize` at 0, unpinning forgets the entry, and the panel asks first.

## Settings

```json
{
  "clipboard": {
    "historySize": 500
  }
}
```

| Key | What it does | Default |
|---|---|---|
| `historySize` | How many unpinned copies to keep, up to 5000. `0` turns recording off. | `500` |

Lowering `historySize` forgets the oldest copies past the new limit straight away, or at the next start if the shell was not running. `0` stops the watchers and forgets every copy that is not pinned. Pins stay, because each one was kept on purpose. `pshell clipboard clearAll` forgets them too.

## What is not recorded

- Anything a password manager marks as secret. KeePassXC and similar apps flag these copies, and they never reach the history file.
- Text copies over 1 MiB. These are skipped whole, not cut short.

## Where it is stored

The history is `~/.local/state/pshell/clipboard/history.json`, newest first. Images are kept next to it in `images/`, one file per image, named by its sha256.

The `clipboard` folder is made `0700` and its files `0600`, so other users on the machine cannot read your copies.

Copying something already in the history moves it to the top instead of adding it twice. Forgetting an entry deletes its image file.

When the newest copy is forgotten, the clipboard itself is emptied too. Otherwise the copy would still be on the clipboard, and the shell records whatever is on the clipboard each time it starts. A password you just deleted would come straight back. This happens when you:

- delete the newest copy, pinned or not;
- unpin the newest copy with `historySize` at 0;
- use Shift+Delete or `clear`, unless the newest copy is pinned and so kept;
- use `clearAll`.

## What it needs

`wl-clipboard` and `wtype`, plus `perl` (to decode the UTF-16 some apps copy) and `setpriv` from util-linux. Most systems already have the last two.

## Commands

Everything works over IPC, with the panel open or not:

```sh
pshell clipboard toggle          # also: open, close
pshell clipboard count           # how many copies are kept, pins included
pshell clipboard history 20      # the pins, then the twenty newest copies, numbered
pshell clipboard copy 3          # put number 3 back on the clipboard
pshell clipboard remove 3        # forget number 3, pinned or not
pshell clipboard pin 3
pshell clipboard unpin 0         # forgets it if historySize is 0
pshell clipboard pinned          # only the pinned ones, same numbers
pshell clipboard clear           # forget everything but the pins, without asking
pshell clipboard clearAll        # forget the pins too
```

`history` lists pinned entries first, then the rest newest first, in the same order as the panel. Each line is a number, a tab, and a preview. A pinned entry's preview starts with `[pin] `. The number you give it counts only the unpinned copies, so `history 20` is every pin plus the twenty newest copies. `0` lists everything. The panel shows every pin and fifty other copies.

Every command takes the numbers `history` prints. Pinning, unpinning and forgetting move entries around, so list again before using a number twice.

`copy` only copies. From a script there is no way to know which window would get a paste, so pasting is left to the panel.

A small picker using fzf:

```sh
pshell clipboard copy "$(pshell clipboard history 50 | fzf | cut -f1)"
```
