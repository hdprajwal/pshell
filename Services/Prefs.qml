pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

// Small bag of things pshell remembers between runs, kept apart from
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

    // Where the settings window was last left. Zero means "never opened", so
    // the window picks its own first size rather than opening at 0x0.
    readonly property string settingsTab: data.settingsTab || ""
    readonly property int settingsWidth: data.settingsWidth || 0
    readonly property int settingsHeight: data.settingsHeight || 0

    function setSettingsTab(tabId) {
        const next = Object.assign({}, root.data);
        next.settingsTab = String(tabId);
        root.data = next;
        _save();
    }

    function setSettingsSize(w, h) {
        if (w <= 0 || h <= 0)
            return;
        const next = Object.assign({}, root.data);
        next.settingsWidth = Math.round(w);
        next.settingsHeight = Math.round(h);
        root.data = next;
        _save();
    }

    function _save() {
        if (!_loaded)
            return;
        file.setText(JSON.stringify(root.data, null, 2));
    }

    FileView {
        id: file

        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/pshell/state.json"
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
