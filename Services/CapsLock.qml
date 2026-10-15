pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "CapsLock.js" as Model

// Whether caps lock is on.
//
// There is no event to listen for. Hyprland's socket2 says when the layout
// changes but not when a lock key does, Quickshell has no keyboard state to
// bind to, and DMS gets it from its own backend daemon, which pshell does
// not have. What is left is the keyboard LED: the kernel keeps one per
// keyboard under /sys/class/leds/*::capslock, and Hyprland lights it with
// the lock. sysfs does not tell inotify when an LED changes, so the files
// are read on a short timer -- in process, no command started per tick,
// two bytes from a file the kernel answers from memory.
//
// A singleton for the idle inhibitor's reason: bar widgets are instantiated
// once per monitor, and one timer is enough for all of them. The lockscreen
// can read the same `on` for its warning.
Singleton {
    id: root

    readonly property bool on: Model.anyLit(root.states)

    // False until some LED has been read, and on a machine with none: a
    // desktop keyboard without a caps lock light reports nothing here.
    readonly property bool available: root.readable

    // How often the LEDs are read, in milliseconds. Short enough that the
    // indicator follows the key without a visible lag.
    readonly property int interval: 300

    property var ledDirs: []
    property var states: []
    property bool readable: false

    // ------------------------------------------------------------ discovery

    // The glob is the shell's because FileView takes one path. Run again now
    // and then so a keyboard plugged in later is found too; that is one
    // short command a minute, against a read every tick.
    Process {
        id: discover
        command: ["sh", "-c", "for d in /sys/class/leds/*::capslock; do [ -e \"$d/brightness\" ] && echo \"$d\"; done; true"]

        stdout: StdioCollector {
            onStreamFinished: {
                const dirs = Model.parseLedDirs(text);
                // Same list, same readers: rebuilding them would drop every
                // state read so far for a tick.
                if (JSON.stringify(dirs) !== JSON.stringify(root.ledDirs))
                    root.ledDirs = dirs;
            }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!discover.running)
                discover.running = true;
        }
    }

    // --------------------------------------------------------------- reading

    Instantiator {
        id: readers
        model: root.ledDirs

        delegate: FileView {
            required property var modelData
            property var lit: null

            path: modelData + "/brightness"
            printErrors: false
            onLoaded: lit = Model.isLit(text())
            onLoadFailed: lit = null
            onLitChanged: root.collect()
        }

        onObjectAdded: root.collect()
        onObjectRemoved: root.collect()
    }

    function collect() {
        const list = [];
        var readable = false;
        for (var i = 0; i < readers.count; i++) {
            const reader = readers.objectAt(i);
            const lit = reader ? reader.lit : null;
            list.push(lit === true);
            if (lit !== null && lit !== undefined)
                readable = true;
        }
        root.states = list;
        root.readable = readable;
    }

    Timer {
        interval: root.interval
        running: readers.count > 0
        repeat: true
        onTriggered: {
            for (var i = 0; i < readers.count; i++) {
                const reader = readers.objectAt(i);
                if (reader)
                    reader.reload();
            }
        }
    }

    IpcHandler {
        target: "pshell.capslock"

        // "unavailable" rather than "off" where there is no LED to read, so
        // a script cannot mistake "cannot tell" for "not on".
        function status(): string {
            if (!root.available)
                return "unavailable";
            return root.on ? "on" : "off";
        }
    }
}
