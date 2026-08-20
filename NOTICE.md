# Third-party code in qsbar

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

`Ui/BarIconButton.qml` is modified. Omarchy's fits exactly one Nerd Font
glyph in a square canvas, so a widget wanting anything else -- several themed
icons, an icon beside a label -- had to compute its own slot width and widen
that canvas to match, and several of qsbar's got it wrong in different
directions. It now lays its content out as one centred row and takes its width
from that, the way qsbar's own bar button did before this kit replaced it.
`iconSources`, `iconSource`, `iconNames`, `iconName`, `label` and `iconColor`
are additions; `text` still means the glyph and still goes through the same
optically centred canvas, so an Omarchy widget behaves exactly as before.
`Ui/BarIcon.qml` is qsbar's own, not Omarchy's: it draws a recoloured icon
from the icon theme, which Omarchy has no equivalent for because it uses
glyphs throughout.

`Ui/KeyboardPanel.qml` and `Ui/PopupCard.qml` are modified. Both placed their
card by measuring down from the top of the output — `barH + gap` for a top bar
— which assumes the bar's own surface starts at the screen edge. qsbar can sit
below another shell's bar, and then the panel is drawn that much too high, over
the bar it belongs under. Both now anchor a layer surface to all four edges and
honour exclusive zones, so the compositor sizes the surface to what every bar
has left over and the card offsets itself by `gap` alone. That also lets the
bar keep its own clicks, so the mask and click-forwarding KeyboardPanel needed
to reach past its own overlay are gone. Both also gained a
`horizontalContentInset`, the mirror of the `verticalContentInset` they
already had, for panels that size themselves from their content. Nothing
either of them already exposed has changed.

`Commons/Color.qml`, `Commons/Style.qml` and `Commons/Util.qml` are qsbar's
own. They implement the same interface as Omarchy's, but read qsbar's
`config.json` and its matugen palette instead of Omarchy's theme files, which
is what bridges a widget written for one shell onto the other.

The manifest format for widgets under `~/.config/qsbar/widgets/` is Omarchy's,
as are the `qs.Commons` and `qs.Ui` module names.

## Material Symbols

`assets/fonts/material-symbols/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf`
is Google's [Material Symbols](https://github.com/google/material-design-icons)
Rounded variable font, Apache 2.0. The full licence text is in
[`licenses/LICENSE.material-symbols`](licenses/LICENSE.material-symbols). It is
shipped rather than depended on so the control centre looks right without an
icon theme or a font package installed.

`Services/Glyphs.qml` is qsbar's own code, but the mapping it encodes — which
symbol stands for 40% battery, where the Wi-Fi signal bands fall, what a
headset looks like next to a monitor — is
[DMS](https://github.com/AvengeMedia/DankMaterialShell)'s, MIT licensed,
copyright Avenge Media LLC. Following it means an icon means the same thing in
both shells.

## Simple Icons

`Widgets/Tailscale/tailscale.svg` is the Tailscale mark from
[Simple Icons](https://simpleicons.org), CC0 1.0. The mark itself is a
trademark of Tailscale Inc., used only to refer to the service.
