pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigPath.js" as ConfigPath

// Small bag of things pshell remembers between runs, kept apart from
// config.json so hand-edited config is never rewritten by the shell.
Singleton {
    id: root

    property var data: ({})
    property bool _loaded: false
    property bool _writing: false

    // state.json is on disk but unusable -- it does not parse, is not a JSON
    // object, or could not be read. Writes rewrite the whole file from
    // `data`, which in that state is `{}` or stale, so they are refused until
    // the file parses again rather than wiping it. Same guard as Config.qml's.
    property bool _unreadable: false

    function _writable() {
        return root._loaded && !root._unreadable;
    }

    // Whether state.json has been read yet. Public because a reader that
    // caches something here has to tell "nothing was ever stored" apart from
    // "the file has not loaded": the weather service would otherwise resolve a
    // place name it already had the coordinates for, every time the shell
    // starts. This FileView does not block on loading, unlike Config's.
    readonly property bool loaded: _loaded

    // One shared empty array for the unset case, not a fresh `[]` per
    // evaluation.
    //
    // `data.pinnedSinks || []` looks harmless and is not: with nothing pinned
    // -- the default -- every re-evaluation of that binding mints a new array
    // with a new identity, so the change signal fires whether or not anything
    // changed. AudioDeviceList's `devices` binding calls isPinned(), so it
    // re-sorts and its Repeater rebuilds every delegate, for a list that is
    // empty and stayed empty. Any writer to state.json pays that, so the fix
    // belongs here rather than at the writer that happened to notice.
    readonly property var _none: []

    readonly property var pinnedSinks: Array.isArray(data.pinnedSinks) ? data.pinnedSinks : _none
    readonly property var pinnedSources: Array.isArray(data.pinnedSources) ? data.pinnedSources : _none

    function isPinned(name, input) {
        const list = input ? pinnedSources : pinnedSinks;
        return list.indexOf(String(name)) >= 0;
    }

    function togglePin(name, input) {
        if (!root._writable())
            return;
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
        if (!root._writable())
            return;
        const next = Object.assign({}, root.data);
        next.settingsTab = String(tabId);
        root.data = next;
        _save();
    }

    function setSettingsSize(w, h) {
        if (w <= 0 || h <= 0 || !root._writable())
            return;
        const next = Object.assign({}, root.data);
        next.settingsWidth = Math.round(w);
        next.settingsHeight = Math.round(h);
        root.data = next;
        _save();
    }

    // The coordinates the weather service last resolved a place name to, and
    // the name it resolved. One small object, written when the location
    // setting changes and at no other time -- a user action, like every other
    // writer in this file.
    //
    // The forecast itself is deliberately not here. It is a kilobyte rewritten
    // every fifteen minutes for as long as the shell runs, and every write to
    // this file re-evaluates every binding that reads it. Services/Weather.qml
    // keeps that one in a state file of its own, the shape
    // Services/Notifications.qml already uses for its history.
    readonly property var weather: data.weather && typeof data.weather === "object" ? data.weather : ({})

    function setWeather(next) {
        if (!root._writable())
            return;
        const out = Object.assign({}, root.data);
        out.weather = next;
        root.data = out;
        _save();
    }

    function _save() {
        if (!root._writable())
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
        // them -- undoing a setting that was just changed. Every writer here
        // is a user action, so two overlapping needs two actions inside a
        // filesystem round trip, which is rare rather than impossible: pinning
        // a sink while the settings window is being resized is enough. Same
        // guard, and same reasoning, as Config.qml's.
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

        // A bad file leaves `data` alone, so pins and the weather location
        // already in memory keep working for the rest of the session.
        onLoaded: {
            const parsed = ConfigPath.parseObject(text());
            if (parsed === null) {
                if (!root._unreadable)
                    console.warn("pshell: state.json is not a valid JSON object — not saving to it until it is fixed");
                root._unreadable = true;
            } else {
                root.data = parsed;
                root._unreadable = false;
            }
            root._loaded = true;
        }

        // No state file yet is the normal first run, not an error. Any other
        // failure means a file is there that could not be read.
        onLoadFailed: error => {
            const missing = error === FileViewError.FileNotFound;
            if (!missing && !root._unreadable)
                console.warn("pshell: could not read state.json —", FileViewError.toString(error), "— not saving to it");
            root._unreadable = !missing;
            root._loaded = true;
        }
    }
}
