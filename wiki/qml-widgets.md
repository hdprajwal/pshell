# QML widgets

A [script widget](script-widgets.md) cannot hold live state. Anything that needs a connection to the system, or a panel of its own, is a QML file instead.

pshell uses Omarchy's widget format for this, so widgets written for Omarchy's bar run in pshell without changes.

## Writing one

Put each widget in its own folder under `~/.config/pshell/widgets/`, with a `manifest.json`:

```text
~/.config/pshell/widgets/gpu/
  manifest.json
  Widget.qml
```

```json
{
  "schemaVersion": 1,
  "id": "me.gpu",
  "name": "GPU",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": { "defaultSection": "right", "defaults": { "unit": "C" } }
}
```

| Field | What it does |
|---|---|
| `id` | The name you use in `config.json`. Required. |
| `kinds` | Must include `bar-widget`, or the widget is skipped. |
| `entryPoints.barWidget` | The QML file to load |
| `barWidget.defaults` | Default settings. Your settings in `config.json` override them. |

Add it to a section by its id. Any other key on the entry is a setting:

```json
{ "id": "me.gpu", "unit": "F" }
```

The widget extends `BarWidget` and reads what the bar gives it:

```qml
import QtQuick
import qs.Ui

BarWidget {
  id: root
  implicitWidth: label.implicitWidth + 12
  implicitHeight: barSize

  Text {
    id: label
    anchors.centerIn: parent
    text: "gpu " + root.setting("unit", "C")
    color: root.bar.foreground
    font.family: root.bar.fontFamily
  }
}
```

`root.setting(name, fallback)` reads a setting, with the manifest defaults filled in.

Changes to a widget's files show up the next time the shell starts or reloads.

## Omarchy widgets

The manifest format above is Omarchy's. pshell ships `Commons` and `Ui` modules with the same type and token names, so an Omarchy bar widget's `import qs.Commons` and `import qs.Ui` load pshell's versions instead. Clone one in and it runs:

```sh
git clone https://github.com/ragnacron/omarchy-workspaces-per-monitor \
  ~/.config/pshell/widgets/omarchy-workspaces-per-monitor
```

Then add `{ "id": "ragnacron.workspaces-per-monitor" }` to a section.

Widgets that open a panel work too. Omarchy's `Ui` kit is copied into pshell unchanged: `Panel`, `KeyboardPanel`, `Button`, `TextField`, `Dropdown` and the rest. A widget written against them behaves the same here. pshell copies them rather than rewriting them, because a rewrite would slowly drift, and every drift is a widget that works in Omarchy and not here.

What is pshell's own is the layer underneath. `Color`, `Style` and `Util` have the same interface as Omarchy's, but they read `config.json` and the wallpaper palette instead of Omarchy's theme files. So a widget written for Omarchy picks up pshell's colours. Omarchy calls the text colour `text` and pshell calls it `foreground`; both work.

[NOTICE.md](../NOTICE.md) lists what came from where.

### Qt 6.12 and the `Color` name

From Qt 6.12, `QtQuick` has a `Color` singleton of its own. In a file with a plain `import QtQuick`, it hides the palette, and `Color.popups` comes back undefined.

New QML should do what Omarchy now does:

```qml
import qs.Commons as Commons

// then
Commons.Color.popups
```

Widgets that still say `Color` keep working. On Qt 6.12 and later, pshell loads every widget from a copy under `~/.cache/pshell/widgets/`, with `import QtQuick 6.11` in place of the plain import. Omarchy's shell does the same. Your own files are never edited.

## How the code is laid out

If you want to read or change pshell itself:

```text
shell.qml            the bar window, and what widgets can read from it
Services/            singletons: config, theme, icons, audio, brightness, and the rest
Components/          the section that lays out widgets in the bar
Widgets/<Name>/      one folder per widget, holding its panels too
Commons/  Ui/        the Omarchy compatible modules
assets/              fonts and theme templates pshell ships
cmd/pshell-agents/   the Go helper for the AI usage widget
bin/pshell           the command line wrapper
tests/               node tests, run with: node --test tests/*.test.mjs
```

Quickshell makes every folder a module, so `Widgets/Network/` is `qs.Widgets.Network` and a file reaches its neighbours by importing it. The two `qmldir` files that exist are there to pin the names Omarchy widgets import.

A widget keeps the panels only it uses. `Widgets/Network/` holds the list of networks and the password prompt next to the widget itself. The control centre imports `qs.Widgets.Network` and `qs.Widgets.Bluetooth` because it reuses their lists rather than keeping its own copies. Omarchy's own shell is laid out the same way.
