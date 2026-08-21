pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours derived from the wallpaper with matugen.
//
// matugen prints the whole palette as JSON, so qsbar runs it and reads stdout
// rather than going through matugen's template and config files. Nothing is
// written to disk and there is no file to keep in sync.
//
// This is inert unless the config sets `theme: "wallpaper"`, and explicit
// colours in config.json always win over anything generated here.
Singleton {
    id: root

    property var palette: ({})
    property bool available: false

    readonly property bool enabled: Config.theme === "wallpaper" && Config.wallpaperPath !== ""

    readonly property string bg: palette.bg || ""
    readonly property string fg: palette.fg || ""
    readonly property string accent: palette.accent || ""
    readonly property string urgent: palette.urgent || ""
    readonly property string dim: palette.dim || ""

    function refresh() {
        if (!enabled) {
            palette = ({});
            return;
        }
        generator.command = ["matugen", "image", Config.wallpaperPath, "--json", "hex", "--dry-run", "--prefer", Config.matugenPrefer, "--type", Config.matugenScheme, "--mode", Config.mode];
        generator.running = false;
        generator.running = true;
    }

    onEnabledChanged: refresh()
    Component.onCompleted: refresh()

    // wallpaperPath, not wallpaper: the two are separate bindings, and the
    // notification for the one being edited arrives before the one derived
    // from it has been re-evaluated. Watching `wallpaper` meant refresh() read
    // last wallpaper's path and matugen re-ran on the image just replaced.
    Connections {
        target: Config
        function onWallpaperPathChanged() {
            root.refresh();
        }
        function onModeChanged() {
            root.refresh();
        }
    }

    Process {
        id: generator

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (raw === "")
                    return;

                var parsed;
                try {
                    parsed = JSON.parse(raw);
                } catch (e) {
                    console.warn("qsbar: matugen output was not JSON:", e);
                    return;
                }

                const colors = parsed.colors;
                if (!colors)
                    return;

                const mode = Config.mode;
                function pick(name) {
                    const role = colors[name];
                    if (!role)
                        return "";
                    const variant = role[mode] || role.default;
                    return variant ? variant.color || "" : "";
                }

                // surface over background: on a wallpaper with a flat dark
                // edge the two are identical anyway, and surface stays
                // readable when they differ.
                root.palette = {
                    bg: pick("surface"),
                    fg: pick("on_surface"),
                    accent: pick("primary"),
                    urgent: pick("error"),
                    dim: pick("outline")
                };
                root.available = true;
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("qsbar: matugen failed with exit", code, "- falling back to configured colours");
        }
    }
}
