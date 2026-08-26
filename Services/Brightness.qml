pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Backlight via brightnessctl. There is no Wayland protocol for this and no
// Quickshell service, so it shells out, which is what pshell does anyway.
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

    IpcHandler {
        target: "pshell.brightness"

        // Five points per step, matching the control centre's slider, so
        // the keybind and the mouse move the screen in the same increments.
        // setFraction already clamps -- to a 0.01 floor, not zero, so `down`
        // held too long dims the screen instead of turning it off.
        function up(): void {
            root.setFraction(root.fraction + 0.05);
        }

        function down(): void {
            root.setFraction(root.fraction - 0.05);
        }

        // Percent at the boundary, fraction inside, same as pshell.audio.
        function set(percent: int): void {
            root.setFraction(percent / 100);
        }

        function get(): int {
            return Math.round(root.fraction * 100);
        }
    }
}
