pragma Singleton

import QtQuick
import qs.Services

// Palette. Names match Omarchy's qs.Commons.Color so its widgets resolve here.
// qsbar keeps one flat palette instead of Omarchy's per-surface roles, and the
// role objects below all point back at it.
QtObject {
    id: root

    readonly property color foreground: Config.fg
    readonly property color background: Config.bg
    readonly property color accent: Config.accent
    readonly property color urgent: Config.urgent

    readonly property QtObject bar: QtObject {
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }

    readonly property QtObject popups: QtObject {
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }

    readonly property QtObject tooltip: QtObject {
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }

    readonly property QtObject menu: QtObject {
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }
}
