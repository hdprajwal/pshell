# Wallpaper

pshell draws the desktop background itself. You do not need swaybg or hyprpaper. There is one background window per screen, under everything else. Changing the wallpaper fades to the new picture.

## Settings

| Key | What it does | Default |
|---|---|---|
| `wallpaper` | The image on screen | none, so the background is a flat `bg` colour |
| `wallpaperDir` | The folder to pick wallpapers from | `~/wallpapers` |

```json
{
  "wallpaper": "~/wallpapers/black.jpg",
  "wallpaperDir": "~/wallpapers"
}
```

If `wallpaper` is not set, or the path is not an image, the background is a flat colour rather than a hole.

Every way of changing the wallpaper writes the `wallpaper` key in `config.json`. With `"theme": "wallpaper"`, that also recolours the bar and your apps. See [Theming](theming.md).

## Three ways to pick one

### The settings page

`pshell settings open wallpaper` shows `wallpaperDir` as a grid of thumbnails, in pages that fit the window.

- Click a thumbnail to set it.
- Click the folder path at the top to change the folder.
- The scroll wheel, a swipe, or the arrows under the grid turn pages.
- The shuffle button sets a random wallpaper.
- The carousel button opens the fullscreen picker.

The keyboard works too. See [Keybinds](keybinds.md#wallpaper-page-in-settings).

### The fullscreen carousel

```sh
pshell wallpaper carousel
```

A row of large cards over the whole screen. The highlighted image is in the middle, with its neighbours on each side. Use the arrow keys (or h and l) to move, Enter to set it, and Escape to leave without changing anything. Clicking outside the cards also closes it.

Moving through the carousel does not change the desktop until you press Enter. Every change re-runs matugen and rewrites the theme files, so pshell only does that once, for the one you pick.

The carousel opens on the focused screen, above fullscreen windows. It is a good fit for a keybind; see [Keybinds](keybinds.md#a-keymap-to-start-from).

### Commands

```sh
pshell wallpaper set ~/wallpapers/foo.png
pshell wallpaper next          # the next image in the folder, wrapping around
pshell wallpaper previous
pshell wallpaper random        # never the one already up
pshell wallpaper current
pshell wallpaper list          # one path per line
pshell wallpaper rescan        # after adding files to the folder
```

See [Commands](commands.md#wallpaper) for the full list.

## Thumbnails

The settings grid and the carousel show small copies of your images, not the originals. They are kept in `~/.cache/pshell/wallpaper-thumbs`.

pshell makes them with `vipsthumbnail` (from libvips) if it is installed, or ImageMagick's `magick` if not. Each image is done once, and again only when it changes.

With neither installed, there are no thumbnails. The grid shows empty tiles, and the carousel loads the full images, which is slow on a big folder.

## The lockscreen

The lockscreen uses the same wallpaper by default, blurred and dimmed. See [Lockscreen](lockscreen.md#settings).
