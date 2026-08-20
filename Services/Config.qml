pragma Singleton

import QtCore
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var data: ({})

    readonly property string position: data.position || "top"
    readonly property int size: data.size || 30
    // Explicit colours win, then anything matugen derived from the wallpaper,
    // then the built-in defaults.
    readonly property string bg: data.bg || Theme.bg || "#1e1e2e"
    readonly property string fg: data.fg || Theme.fg || "#cdd6f4"
    readonly property string accent: data.accent || Theme.accent || "#89b4fa"
    readonly property string dim: data.dim || Theme.dim || "#6c7086"
    readonly property string fontFamily: data.font || "monospace"
    readonly property int fontSize: data.fontSize || 12
    // Glyph font for widget icons. Nerd Fonts are the least intrusive choice
    // here: they are usually already installed, so qsbar ships no font of its own.
    // Size of icons drawn in the bar itself. Popout and panel icons size
    // themselves off the font instead, so this does not touch them.
    readonly property int barIconSize: data.barIconSize || Math.round(size * 0.55)
    readonly property string iconFont: data.iconFont || "JetBrainsMono Nerd Font"
    readonly property string urgent: data.urgent || Theme.urgent || "#f38ba8"

    // "manual" uses the colours above as written. "wallpaper" runs matugen on
    // `wallpaper` and fills in whatever you have not set yourself.
    readonly property string theme: data.theme || "manual"
    readonly property string mode: data.mode === "light" ? "light" : "dark"
    readonly property string wallpaper: data.wallpaper || ""
    readonly property string wallpaperPath: {
        const path = String(wallpaper);
        if (path.indexOf("~/") === 0)
            return Quickshell.env("HOME") + path.substring(1);
        return path;
    }
    readonly property string matugenScheme: data.matugenScheme || "scheme-tonal-spot"
    // matugen refuses to guess when an image has several candidate source
    // colours and no terminal to ask, so a preference is mandatory here.
    readonly property string matugenPrefer: data.matugenPrefer || "saturation"
    readonly property int gap: data.gap !== undefined ? data.gap : 12
    readonly property int cornerRadius: data.cornerRadius !== undefined ? data.cornerRadius : 0
    readonly property int gapsOut: data.gapsOut !== undefined ? data.gapsOut : 5
    readonly property real spacingScale: data.spacingScale || 1.0
    readonly property bool scaleWithFont: data.scaleWithFont !== false

    readonly property var left: data.left || []
    readonly property var center: data.center || []
    readonly property var right: data.right || []

    FileView {
        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/qsbar/config.json"
        watchChanges: true
        blockLoading: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {
                console.warn("qsbar: bad config.json —", e);
            }
        }
    }
}
