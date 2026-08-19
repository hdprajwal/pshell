pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

// Finds QML widgets on disk. A widget is a directory under
// ~/.config/qsbar/widgets/ holding a manifest.json, which is the same layout
// Omarchy uses, so its widgets can be cloned straight in.
Singleton {
    id: root

    readonly property string widgetsDir: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/qsbar/widgets"

    // id -> { id, dir, entry, manifest, defaultSection, defaults, allowMultiple }
    property var widgets: ({})
    property var errors: []

    signal scanned

    function get(id) {
        return widgets[String(id || "")] || null;
    }

    function has(id) {
        return !!get(id);
    }

    function defaultsFor(id) {
        const w = get(id);
        return w ? w.defaults : ({});
    }

    // Merge manifest defaults under the user's inline settings so a widget
    // gets every option its manifest declares, whether or not the user set it.
    function settingsFor(id, entry) {
        const merged = {};
        const defs = defaultsFor(id) || {};
        for (var k in defs)
            merged[k] = defs[k];
        for (var j in entry) {
            if (j === "id" || j === "type")
                continue;
            merged[j] = entry[j];
        }
        return merged;
    }

    function rescan() {
        scanner.running = false;
        scanner.running = true;
    }

    Component.onCompleted: rescan()

    Process {
        id: scanner
        command: ["sh", "-c", 'dir="$HOME/.config/qsbar/widgets"; [ -d "$dir" ] || exit 0; for f in "$dir"/*/manifest.json; do [ -f "$f" ] || continue; echo "===QSBAR==="; dirname "$f"; cat "$f"; done']

        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                const problems = [];
                const blocks = String(text || "").split("===QSBAR===");

                for (var i = 0; i < blocks.length; i++) {
                    const block = blocks[i].trim();
                    if (block === "")
                        continue;

                    const cut = block.indexOf("\n");
                    if (cut < 0)
                        continue;
                    const dir = block.substring(0, cut).trim();
                    const raw = block.substring(cut + 1);

                    var manifest;
                    try {
                        manifest = JSON.parse(raw);
                    } catch (e) {
                        problems.push(dir + ": manifest.json is not valid JSON");
                        continue;
                    }

                    const id = String(manifest.id || "");
                    if (id === "") {
                        problems.push(dir + ": manifest has no id");
                        continue;
                    }

                    const kinds = manifest.kinds || [];
                    if (kinds.indexOf("bar-widget") < 0) {
                        problems.push(id + ": not a bar-widget, skipped");
                        continue;
                    }

                    const entryFile = (manifest.entryPoints || {}).barWidget || "";
                    if (entryFile === "") {
                        problems.push(id + ": manifest has no barWidget entry point");
                        continue;
                    }

                    const bw = manifest.barWidget || {};
                    found[id] = {
                        id: id,
                        dir: dir,
                        entry: "file://" + dir + "/" + entryFile,
                        manifest: manifest,
                        defaultSection: bw.defaultSection || "center",
                        defaults: bw.defaults || {},
                        allowMultiple: bw.allowMultiple === true
                    };
                }

                root.widgets = found;
                root.errors = problems;

                const names = Object.keys(found);
                if (names.length > 0)
                    console.info("qsbar: loaded widgets:", names.join(", "));
                for (var p = 0; p < problems.length; p++)
                    console.warn("qsbar:", problems[p]);

                root.scanned();
            }
        }
    }
}
