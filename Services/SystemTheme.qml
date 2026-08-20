pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop's light/dark preference, read from the GTK setting that the
// control centre's Dark Mode tile writes.
//
// There is no Wayland protocol for this and no Quickshell service, so it
// shells out like Brightness does. `gsettings monitor` only prints on change,
// so the initial value comes from a separate `get`.
//
// Absent gsettings, or a scheme of "default" (no preference expressed), both
// leave this at "dark", which is what qsbar assumed before it asked.
Singleton {
    id: root

    readonly property string scheme: _scheme
    readonly property bool available: _available

    property string _scheme: "dark"
    property bool _available: false

    function _parse(text) {
        const line = String(text || "");
        if (line.indexOf("prefer-light") >= 0)
            return "light";
        if (line.indexOf("prefer-dark") >= 0)
            return "dark";
        // "default" means the desktop states no preference.
        return "dark";
    }

    Process {
        id: reader
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (raw === "")
                    return;
                root._scheme = root._parse(raw);
                root._available = true;
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("qsbar: gsettings unavailable, colours stay on the configured mode");
        }
    }

    // Long-lived: it prints a line every time the setting changes and is
    // expected to run for as long as the shell does.
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = String(data || "").trim();
                if (line === "")
                    return;
                root._scheme = root._parse(line);
                root._available = true;
            }
        }
    }
}
