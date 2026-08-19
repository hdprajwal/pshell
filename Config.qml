pragma Singleton

import QtCore
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var data: ({})

    readonly property string position: data.position || "top"
    readonly property int size: data.size || 30
    readonly property string bg: data.bg || "#1e1e2e"
    readonly property string fg: data.fg || "#cdd6f4"
    readonly property string accent: data.accent || "#89b4fa"
    readonly property string dim: data.dim || "#6c7086"
    readonly property string fontFamily: data.font || "monospace"
    readonly property int fontSize: data.fontSize || 12
    readonly property string urgent: data.urgent || "#f38ba8"
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
