pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

// Finds QML widgets on disk. A widget is a directory under
// ~/.config/pshell/widgets/ holding a manifest.json, which is the same layout
// Omarchy uses, so its widgets can be cloned straight in.
Singleton {
    id: root

    readonly property string widgetsDir: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/pshell/widgets"

    // Qt 6.12's QtQuick exports a `Color` singleton, and in a file importing
    // QtQuick without a version it shadows qs.Commons' palette, so a widget
    // written for Omarchy reads `Color.popups` as undefined. pshell's own QML
    // says `Commons.Color`; a widget on disk is someone else's to edit. So,
    // like Omarchy's shell, load widgets with their bare `import QtQuick`
    // pinned to 6.11, the last version without the singleton. The pin goes
    // into a copy under ~/.cache/pshell/widgets, never the widget's own files.
    //
    // This file imports no qs.Commons, so the only `Color` it can see is
    // QtQuick's. Asking for it rather than for a Qt version means an older Qt,
    // where `import QtQuick 6.11` might not exist, loads widgets as before.
    readonly property bool pinQtQuick: typeof Color !== "undefined"

    // id -> { id, dir, entry, manifest, defaultSection, defaults, allowMultiple }
    // `dir` is where the widget lives; `entry` is the file to load, inside
    // the pinned copy when pinQtQuick is set.
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
        command: ["sh", Quickshell.shellDir + "/Services/widgets.sh", root.pinQtQuick ? "6.11" : ""]

        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                const problems = [];
                const blocks = String(text || "").split("===PSHELL===");

                for (var i = 0; i < blocks.length; i++) {
                    const block = blocks[i].trim();
                    if (block === "")
                        continue;

                    // The widget's directory, the one to load it from, then
                    // the manifest; see Services/widgets.sh.
                    const cut = block.indexOf("\n");
                    const cut2 = cut < 0 ? -1 : block.indexOf("\n", cut + 1);
                    if (cut2 < 0)
                        continue;
                    const dir = block.substring(0, cut).trim();
                    const loadDir = block.substring(cut + 1, cut2).trim();
                    const raw = block.substring(cut2 + 1);

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
                        entry: "file://" + loadDir + "/" + entryFile,
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
                    console.info("pshell: loaded widgets:", names.join(", "));
                for (var p = 0; p < problems.length; p++)
                    console.warn("pshell:", problems[p]);

                root.scanned();
            }
        }

        // widgets.sh warns here when it cannot stage a widget, or a file in
        // one, and loads it unpinned or without that file.
        stderr: StdioCollector {
            onStreamFinished: {
                const message = String(text || "").trim();
                if (message !== "")
                    console.warn("pshell:", message);
            }
        }
    }
}
