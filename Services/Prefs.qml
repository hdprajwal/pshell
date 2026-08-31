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
    property bool _writing: false

    // Whether state.json has been read yet. Public because a reader that
    // caches something here has to tell "nothing was ever stored" apart from
    // "the file has not loaded": the weather service would otherwise resolve a
    // place name it already had the coordinates for, every time the shell
    // starts. This FileView does not block on loading, unlike Config's.
    readonly property bool loaded: _loaded

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

    // What the weather service last resolved and last read: a geocoded place
    // and one forecast, so a restart on a dead network still has something to
    // show. It is bulkier than anything else in this file -- about a kilobyte
    // against a handful of strings -- and it is still shell-owned runtime
    // state that is regenerated rather than authored, which is what this file
    // is for. A cache file of its own would be a second FileView with a second
    // copy of the load guard, the atomic write and the "no file yet is a
    // normal first run" case, and those three are where the bugs are.
    readonly property var weather: data.weather && typeof data.weather === "object" ? data.weather : ({})

    function setWeather(next) {
        const out = Object.assign({}, root.data);
        out.weather = next;
        root.data = out;
        _save();
    }

    function _save() {
        if (!_loaded)
            return;
        root._writing = true;
        file.setText(JSON.stringify(root.data, null, 2));
    }

    FileView {
        id: file

        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/pshell/state.json"
        watchChanges: true
        blockWrites: false
        atomicWrites: true
        printErrors: false

        // Our own write fires the watcher a moment later, and the reload it
        // causes can land between two writes and hand `data` back the older of
        // them. That was survivable while every writer here was a user action
        // seconds apart; the weather cache writes on a timer for as long as
        // the shell runs, which makes an overlap a matter of time. Same guard,
        // and same reasoning, as Config.qml's.
        onFileChanged: {
            if (root._writing)
                return;
            reload();
        }

        onSaved: root._writing = false

        onSaveFailed: error => {
            root._writing = false;
            console.warn("pshell: could not write state.json —", error);
        }

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
