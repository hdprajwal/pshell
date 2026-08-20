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

`Ui/KeyboardPanel.qml` and `Ui/PopupCard.qml` are modified. Both placed their
card by measuring down from the top of the output — `barH + gap` for a top bar
— which assumes the bar's own surface starts at the screen edge. qsbar can sit
below another shell's bar, and then the panel is drawn that much too high, over
the bar it belongs under. Both now anchor a layer surface to all four edges and
honour exclusive zones, so the compositor sizes the surface to what every bar
has left over and the card offsets itself by `gap` alone. That also lets the
bar keep its own clicks, so the mask and click-forwarding KeyboardPanel needed
to reach past its own overlay are gone. The public API of both is unchanged.

`Commons/Color.qml`, `Commons/Style.qml` and `Commons/Util.qml` are qsbar's
own. They implement the same interface as Omarchy's, but read qsbar's
`config.json` and its matugen palette instead of Omarchy's theme files, which
is what bridges a widget written for one shell onto the other.

The manifest format for widgets under `~/.config/qsbar/widgets/` is Omarchy's,
as are the `qs.Commons` and `qs.Ui` module names.

## Simple Icons

`Widgets/Tailscale/tailscale.svg` is the Tailscale mark from
[Simple Icons](https://simpleicons.org), CC0 1.0. The mark itself is a
trademark of Tailscale Inc., used only to refer to the service.
