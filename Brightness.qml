pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Backlight via brightnessctl. There is no Wayland protocol for this and no
// Quickshell service, so it shells out, which is what qsbar does anyway.
Singleton {
    id: root

    property int value: 0
    property int max: 0
    readonly property bool available: max > 0
    readonly property real fraction: available ? value / max : 0

    property bool _writing: false

    function refresh() {
        reader.running = false;
        reader.running = true;
    }

    function setFraction(f) {
        if (!available)
            return;
        const percent = Math.round(Math.max(0.01, Math.min(1, f)) * 100);
        root.value = Math.round(percent / 100 * root.max);
        writer.command = ["brightnessctl", "-m", "set", percent + "%"];
        writer.running = false;
        writer.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: reader
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            // device,class,current,percent,max
            onStreamFinished: {
                const parts = String(text || "").trim().split(",");
                if (parts.length < 5)
                    return;
                root.value = parseInt(parts[2]) || 0;
                root.max = parseInt(parts[4]) || 0;
            }
        }
    }

    Process {
        id: writer
    }

    // Catches changes made by hotkeys or anything else on the system.
    Timer {
        running: root.available
        interval: 3000
        repeat: true
        onTriggered: if (!writer.running)
            root.refresh()
    }
}
