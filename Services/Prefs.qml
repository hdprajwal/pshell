pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

// Small bag of things qsbar remembers between runs, kept apart from
// config.json so hand-edited config is never rewritten by the shell.
Singleton {
    id: root

    property var data: ({})
    property bool _loaded: false

    readonly property var pinnedSinks: data.pinnedSinks || []
    readonly property var pinnedSources: data.pinnedSources || []

    function isPinned(name, input) {
        const list = input ? pinnedSources : pinnedSinks;
        return list.indexOf(String(name)) >= 0;
    }

    function togglePin(name, input) {
        const key = input ? "pinnedSources" : "pinnedSinks";
        const list = (data[key] || []).slice();
        const at = list.indexOf(String(name));
        if (at >= 0)
            list.splice(at, 1);
        else
            list.push(String(name));

        const next = Object.assign({}, data);
        next[key] = list;
        data = next;
        _save();
    }

    function _save() {
        if (!_loaded)
            return;
        file.setText(JSON.stringify(root.data, null, 2));
    }

    FileView {
        id: file

        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/qsbar/state.json"
        watchChanges: true
        blockWrites: false
        atomicWrites: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {
                root.data = ({});
            }
            root._loaded = true;
        }
        // No state file yet is the normal first run, not an error.
        onLoadFailed: root._loaded = true
    }
}
