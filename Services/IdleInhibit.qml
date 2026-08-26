pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Keep the screen awake.
//
// Wayland's idle inhibitor is attached to a surface and is only meant to count
// while that surface is visible. A bar gets occluded the moment anything goes
// fullscreen, which is exactly when you want this on, so the protocol alone is
// not enough to trust.
//
// So the inhibitor here is held by its own surface rather than the bar's: a
// one-pixel transparent window on the overlay layer, which sits above
// fullscreen windows and is never occluded. It is created only while the
// toggle is on, so nothing is on screen the rest of the time.
//
// A singleton rather than state on the widget: bar widgets are instantiated
// once per monitor under Variants, so keeping `inhibited` on the widget gave
// a two-monitor machine two inhibitors with two states, each deaf to the
// other's toggle. Owning the state here also gives it one IPC target, so a
// keybind can flip it without a widget on the bar at all.
Singleton {
    id: root

    // Off after a restart, always. A machine that silently refuses to sleep
    // because of something you turned on last week is a bad surprise.
    property bool inhibited: false

    function on() {
        root.inhibited = true;
    }

    function off() {
        root.inhibited = false;
    }

    function toggle() {
        root.inhibited = !root.inhibited;
    }

    Loader {
        active: root.inhibited

        sourceComponent: PanelWindow {
            // Anchored to one corner at one pixel so the compositor gives it a
            // real surface to hang the inhibitor on without anything visible.
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"

            // No exclusive zone, or this would push every other window over by
            // a pixel each time it was switched on.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "pshell:idle-inhibit"
            // Overlay rather than Top: it has to stay unoccluded above a
            // fullscreen window for the inhibitor to keep counting.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            IdleInhibitor {
                enabled: true
            }
        }
    }

    IpcHandler {
        target: "pshell.idle"

        // `on` and `off` rather than only `toggle`, so a script that wants
        // the screen awake can ask for that outright instead of asking for
        // "the other thing" and hoping about the current state.
        function on(): void {
            root.on();
        }

        function off(): void {
            root.off();
        }

        function toggle(): void {
            root.toggle();
        }

        function isInhibited(): bool {
            return root.inhibited;
        }
    }
}
