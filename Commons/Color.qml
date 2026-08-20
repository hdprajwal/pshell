pragma Singleton

import QtQuick
import qs.Services

// Palette. Names match Omarchy's qs.Commons.Color so its widgets resolve here.
// qsbar keeps one flat palette instead of Omarchy's per-surface roles, and the
// role objects below all point back at it.
QtObject {
    id: root

    // Omarchy reads generated theme files and exposes them here as a flat
    // "section.key" map. qsbar has one palette that comes from config.json or
    // matugen, and no per-section overrides, so this stays empty and every
    // lookup falls through to the default the caller already carries.
    readonly property var shellValues: ({})

    readonly property color foreground: Config.fg
    readonly property color background: Config.bg
    readonly property color accent: Config.accent
    readonly property color urgent: Config.urgent

    readonly property QtObject bar: QtObject {
        // Omarchy's kit calls the readable colour `text`; qsbar named the
        // same thing `foreground`. Both are exposed so either name resolves.
        readonly property color text: root.bar.foreground
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }

    readonly property QtObject popups: QtObject {
        // Omarchy's kit calls the readable colour `text`; qsbar named the
        // same thing `foreground`. Both are exposed so either name resolves.
        readonly property color text: root.popups.foreground
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }

    readonly property QtObject tooltip: QtObject {
        // Omarchy's kit calls the readable colour `text`; qsbar named the
        // same thing `foreground`. Both are exposed so either name resolves.
        readonly property color text: root.tooltip.foreground
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }

    readonly property QtObject menu: QtObject {
        // Omarchy's kit calls the readable colour `text`; qsbar named the
        // same thing `foreground`. Both are exposed so either name resolves.
        readonly property color text: root.menu.foreground
        readonly property color foreground: root.foreground
        readonly property color background: root.background
        readonly property color border: Util.alpha(root.foreground, 0.2)
    }
}
