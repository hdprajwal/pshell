pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "IdleInhibit.js" as Clock

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
    // because of something you turned on last week is a bad surprise. A timer
    // is not restored either, for the same reason.
    property bool inhibited: false

    // When it switches itself off, in ms since the epoch; 0 for no limit.
    property real endsAt: 0
    // What started it, so the panel can light the right chip: minutes for a
    // preset, 0 for no limit, -1 for a clock time.
    property int preset: 0
    // Wall-clock now, refreshed by the tick below while a timer runs, so the
    // countdowns that bind to it move.
    property real now: Date.now()

    readonly property bool timed: inhibited && endsAt > 0
    readonly property string leftText: timed ? Clock.formatLeft(endsAt - now) : ""
    readonly property string endsAtText: timed ? Qt.formatTime(new Date(endsAt), "HH:mm") : ""

    function on() {
        root.start(0, 0);
    }

    function off() {
        root.inhibited = false;
        root.endsAt = 0;
        root.preset = 0;
    }

    function toggle() {
        if (root.inhibited)
            root.off();
        else
            root.on();
    }

    // Zero or less is no limit, as `on`.
    function forMinutes(minutes) {
        if (minutes <= 0)
            root.on();
        else
            root.start(Date.now() + minutes * 60000, minutes);
    }

    // False for text that is not a 24-hour HH:MM, so the caller can say so.
    function untilClock(text) {
        const end = Clock.endOfClock(text, Date.now());
        if (end < 0)
            return false;
        root.start(end, -1);
        return true;
    }

    function start(end, preset) {
        root.now = Date.now();
        root.endsAt = end;
        root.preset = preset;
        root.inhibited = true;
    }

    // A repeating check against the wall clock rather than one Timer set to
    // the whole duration: Qt's timers run on the monotonic clock, which stops
    // while the machine is suspended, so a single 2h timer started before a
    // suspend would end late by however long the lid was shut.
    Timer {
        running: root.timed
        repeat: true
        interval: 5000
        onTriggered: {
            root.now = Date.now();
            if (root.now >= root.endsAt) {
                root.off();
                Quickshell.execDetached(["notify-send", "-a", "pshell", "Keep awake ended", "The screen can sleep again."]);
            }
        }
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

        // Minutes rather than a "1h30m" string: a script does its own sums,
        // and a number is the one thing qs checks before calling.
        function forMinutes(minutes: int): void {
            root.forMinutes(minutes);
        }

        // A 24-hour clock time; one already past today means tomorrow.
        function until(time: string): string {
            if (!root.untilClock(time))
                return "error: expected a 24-hour time like 18:30, got \"" + time + "\"";
            return "until " + root.endsAtText;
        }

        // "off", "on" with no limit, or "47m until 18:30".
        function remaining(): string {
            if (!root.inhibited)
                return "off";
            root.now = Date.now();
            return root.timed ? root.leftText + " until " + root.endsAtText : "on";
        }

        function isInhibited(): bool {
            return root.inhibited;
        }
    }
}
