# Third-party code in qsbar

## Omarchy

`Ui/`, `Commons/Border.qml` and `Commons/BorderGeometry.js` are taken from
[Omarchy](https://github.com/basecamp/omarchy), copyright David Heinemeier
Hansson, MIT licensed. The full licence text is in
[`licenses/LICENSE.omarchy`](licenses/LICENSE.omarchy).

They are vendored from the `quattro` branch at commit
`945549699026df6c888a6b1bd4e06fbf55a67595`, unmodified, so an Omarchy widget
that imports `qs.Ui` or `qs.Commons` finds the same types with the same
behaviour it was written against. Keeping them byte-identical is the point:
it is what lets a widget be cloned in and run, and it makes updating them a
copy rather than a merge.

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
