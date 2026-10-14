# Third-party code in pshell

## Omarchy

`Ui/`, `Commons/Border.qml` and `Commons/BorderGeometry.js` are taken from
[Omarchy](https://github.com/basecamp/omarchy), copyright David Heinemeier
Hansson, MIT licensed. The full licence text is in
[`licenses/LICENSE.omarchy`](licenses/LICENSE.omarchy).

They are vendored from the `quattro` branch at commit
`945549699026df6c888a6b1bd4e06fbf55a67595`, so an Omarchy widget that imports
`qs.Ui` or `qs.Commons` finds the same types with the same behaviour it was
written against. Everything is byte-identical to that commit except the two
files below, which makes updating them a copy rather than a merge.

On top of that commit they carry one later upstream change: Omarchy's
`b83d3df0840504299d3099ebf391eb8110527edd` ("Qualify shell palette references
for Qt 6.12"), which imports `qs.Commons as Commons` and writes the palette as
`Commons.Color`. Qt 6.12's `QtQuick` exports its own `Color` singleton, and in
any file with an unversioned `import QtQuick` that one wins over `qs.Commons`,
so `Color.popups` comes back undefined. Only that commit's hunks are applied,
not the rest of what changed upstream in between, and each changed line is
the same as upstream's. The modified files below take the same change.

`Ui/BarIconButton.qml` is modified. Omarchy's fits exactly one Nerd Font
glyph in a square canvas, so a widget wanting anything else -- several themed
icons, an icon beside a label -- had to compute its own slot width and widen
that canvas to match, and several of pshell's got it wrong in different
directions. It now lays its content out as one centred row and takes its width
from that, the way pshell's own bar button did before this kit replaced it.
`iconSources`, `iconSource`, `iconNames`, `iconName`, `label` and `iconColor`
are additions; `text` still means the glyph and still goes through the same
optically centred canvas, so an Omarchy widget behaves exactly as before.
`Ui/BarIcon.qml` is pshell's own, not Omarchy's: it draws a recoloured icon
from the icon theme, which Omarchy has no equivalent for because it uses
glyphs throughout.

`Ui/KeyboardPanel.qml` and `Ui/PopupCard.qml` are modified. Both placed their
card by measuring down from the top of the output — `barH + gap` for a top bar
— which assumes the bar's own surface starts at the screen edge. pshell can sit
below another shell's bar, and then the panel is drawn that much too high, over
the bar it belongs under. Both now anchor a layer surface to all four edges and
honour exclusive zones, so the compositor sizes the surface to what every bar
has left over and the card offsets itself by `gap` alone. That also lets the
bar keep its own clicks, so the mask and click-forwarding KeyboardPanel needed
to reach past its own overlay are gone. Both also gained a
`horizontalContentInset`, the mirror of the `verticalContentInset` they
already had, for panels that size themselves from their content. Nothing
either of them already exposed has changed.

`Commons/Color.qml`, `Commons/Style.qml` and `Commons/Util.qml` are pshell's
own. They implement the same interface as Omarchy's, but read pshell's
`config.json` and its matugen palette instead of Omarchy's theme files, which
is what bridges a widget written for one shell onto the other.

The manifest format for widgets under `~/.config/pshell/widgets/` is Omarchy's,
as are the `qs.Commons` and `qs.Ui` module names.

The clipboard history is adapted from Omarchy's first-party clipboard plugin
on the same `quattro` branch, at commit
`84cfb93959f4fe0bbb71de71593b36647d2ba78d`. Unlike the files above these are
not vendored byte for byte; they are rewritten in pshell's style, with the
design and most of the logic kept:

- `Services/ClipboardHistory.js` is adapted from
  `shell/plugins/clipboard/ClipboardHistory.js`: the entry shapes, dedupe,
  cap, display truncation, search and file-URI handling. Entries carry an
  epoch time instead of a formatted string, the translation layer is gone,
  and `orphanedImages` is pshell's own.
- `Services/clipboard.sh` adapts `shell/plugins/clipboard/capture.sh` (the
  password-manager skip, the bounded reads, the UTF-16 detection and the
  content-addressed images) and `bin/omarchy-clipboard-paste-text` and
  `-file` (copy, wait, Shift+Insert). Its `reap` verb is pshell's own and
  narrower than Omarchy's `pkill`; setting the primary selection on paste is
  pshell's own too.
- `Services/Clipboard.qml` and `Widgets/Clipboard/ClipboardOverlay.qml` follow
  `shell/plugins/clipboard/Clipboard.qml`: the `setpriv --pdeathsig` watchers,
  the snapshot at start, the one-second watcher restart, and the panel's
  layout and keys.

The nightlight follows Omarchy's nightlight service on the same branch
(`shell/plugins/services/nightlight/Service.qml` and `NightlightModel.js`,
and `bin/omarchy-toggle-nightlight`): ask hyprsunset over `hyprctl hyprsunset
temperature`, start one if nothing answers, read the temperature back, 4000K
as the default and 6000K as the point past which it does nothing. The code is
rewritten in pshell's style rather than vendored:

- `Services/Nightlight.js` adapts `NightlightModel.js`. Its parser is
  stricter, and the range, the schedule and the status line are pshell's own.
- `Services/Nightlight.qml` adapts `Service.qml`. Owning the hyprsunset it
  starts as a `setpriv --pdeathsig` child, leaving one it did not start
  alone, and turning off with `identity` rather than 6500K are pshell's own.

The update indicator follows Omarchy's `SystemUpdate.qml` bar widget on the
same branch (`shell/plugins/bar/widgets/SystemUpdate.qml`): hidden unless
something is pending, a refresh over IPC, and a click that runs the updater
in a floating terminal. No code is taken from it. Where its updates come
from is pshell's own: Omarchy polls `omarchy-update-available` every six
hours, and `Services/Updates.qml` watches the state files arch-update's own
timer writes instead, counting what is pending rather than whether anything
is.

## Material Symbols

`assets/fonts/material-symbols/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf`
is Google's [Material Symbols](https://github.com/google/material-design-icons)
Rounded variable font, Apache 2.0. The full licence text is in
[`licenses/LICENSE.material-symbols`](licenses/LICENSE.material-symbols). It is
shipped rather than depended on so the control centre looks right without an
icon theme or a font package installed.

`Services/Glyphs.qml` is pshell's own code, but the mapping it encodes — which
symbol stands for 40% battery, where the Wi-Fi signal bands fall, what a
headset looks like next to a monitor — is
[DMS](https://github.com/AvengeMedia/DankMaterialShell)'s, MIT licensed,
copyright Avenge Media LLC. Following it means an icon means the same thing in
both shells.

## Simple Icons

`Widgets/Tailscale/tailscale.svg` is the Tailscale mark from
[Simple Icons](https://simpleicons.org), CC0 1.0. The mark itself is a
trademark of Tailscale Inc., used only to refer to the service.

## Provider marks

`Widgets/AiUsage/assets/*.svg` are the Claude, Codex and Fireworks marks, taken
from the assets of Omarchy's `omarchy-agents` widget, MIT licensed. Each mark is
a trademark of its owner -- Anthropic, OpenAI and Fireworks AI respectively --
used only to refer to that service. `codex-light.svg` is the same artwork in the
cut meant for a light background.

`cmd/pshell-agents` writes those records itself, in the format Omarchy's
`omarchy-agent-usage-update` and its three collectors wrote. None of their code
is vendored here -- they are Python and this is Go, and every line of it was
written for pshell -- but the record format is theirs, and so is the
understanding of which files on disk hold what: which key in a Claude Code
transcript carries the model, that Codex's cumulative token counter must not be
summed, that a cached prompt token is inside the prompt total and not beside
it. That work was Omarchy's first, MIT licensed, and it is the reason this port
prints the same numbers.
