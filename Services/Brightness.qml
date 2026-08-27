pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Backlight.js" as Backlight

// Backlight via brightnessctl. There is no Wayland protocol for this and no
// Quickshell service, so it shells out, which is what pshell does anyway.
//
// Two devices, one command: the screen (class `backlight`) and the keyboard
// (a `leds` entry whose name ends in `kbd_backlight`), both picked out of a
// single `brightnessctl -lm` listing by Backlight.js, where the parsing and
// the picking live so node can test them.
Singleton {
    id: root

    // The screen. These names are load-bearing: Phase 0's IPC handler and
    // the control centre both bind to `fraction`, so it stays `fraction`
    // rather than becoming `screenFraction` -- renaming it would break both
    // callers for no gain.
    property int value: 0
    property int max: 0
    property string _screenDevice: ""
    readonly property bool available: max > 0
    readonly property real fraction: available ? value / max : 0

    // The keyboard backlight. Usually a coarse device -- this machine has
    // three steps, not a hundred -- which is why keyboardMax is public: the
    // control centre snaps its slider to 1/keyboardMax rather than
    // pretending the range is continuous.
    property int keyboardValue: 0
    property int keyboardMax: 0
    property string _keyboardDevice: ""
    readonly property bool keyboardAvailable: keyboardMax > 0
    readonly property real keyboardFraction: keyboardAvailable ? keyboardValue / keyboardMax : 0

    function refresh() {
        reader.running = false;
        reader.running = true;
    }

    function setFraction(f) {
        if (!available)
            return;
        // Floored at 1%, never zero: a screen at zero backlight is a screen
        // you cannot see to fix. The keyboard setter below deliberately has
        // no such floor -- an unlit keyboard is a normal thing to want.
        const percent = Math.round(Math.max(0.01, Math.min(1, f)) * 100);
        root.value = Math.round(percent / 100 * root.max);
        // The device is named even though brightnessctl has a default: on a
        // machine where the first listed device is a keyboard LED, the bare
        // form would dim the wrong thing.
        write(["brightnessctl", "-m", "-d", root._screenDevice, "set", percent + "%"]);
    }

    function setKeyboardFraction(f) {
        if (!keyboardAvailable)
            return;
        // Rounded to a real hardware step first, percent second. The slider
        // hands in fractions between steps, and showing one of those would
        // leave the handle somewhere no step is -- it then jumps under the
        // finger when the poll reads the truth back.
        _writeKeyboardStep(Math.round(Math.max(0, Math.min(1, f)) * root.keyboardMax));
    }

    // Five points per press, like `up`/`down` -- except that on a three-step
    // device five points rounds back onto the step you are on, and a keybind
    // that sometimes does nothing reads as broken. So when the rounded
    // target is the current step, the press moves one hardware step anyway.
    // brightnessctl makes the same promise for its own relative sets: its
    // calc_value forces a nonzero delta that rounded to zero up to one unit.
    function _nudgeKeyboard(direction) {
        if (!keyboardAvailable)
            return;
        const target = Math.round(Math.max(0, Math.min(1, root.keyboardFraction + direction * 0.05)) * root.keyboardMax);
        _writeKeyboardStep(target !== root.keyboardValue ? target : root.keyboardValue + direction);
    }

    function _writeKeyboardStep(step) {
        const s = Math.max(0, Math.min(root.keyboardMax, step));
        root.keyboardValue = s;
        // Percent survives the round trip: brightnessctl's percent_to_val
        // round()s, so the percent of a rounded step lands back on that
        // step even when max is 3 (33% of 3 is 0.99, read back as step 1).
        write(["brightnessctl", "-m", "-d", root._keyboardDevice, "set", Math.round(s / root.keyboardMax * 100) + "%"]);
    }

    function write(command) {
        writer.command = command;
        writer.running = false;
        writer.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: reader
        command: ["brightnessctl", "-lm"]
        stdout: StdioCollector {
            // device,class,current,percent,max -- one line per device.
            onStreamFinished: {
                const devices = Backlight.parseDevices(text);
                const screen = Backlight.pickScreen(devices);
                root._screenDevice = screen ? screen.name : "";
                root.value = screen ? screen.current : 0;
                root.max = screen ? screen.max : 0;
                const keyboard = Backlight.pickKeyboard(devices);
                root._keyboardDevice = keyboard ? keyboard.name : "";
                root.keyboardValue = keyboard ? keyboard.current : 0;
                root.keyboardMax = keyboard ? keyboard.max : 0;
            }
        }
    }

    Process {
        id: writer
    }

    // Catches changes made by hotkeys or anything else on the system. One
    // -lm listing refreshes both devices; still skipped while a write is in
    // flight, so the poll cannot read back the value a write is replacing.
    Timer {
        running: root.available || root.keyboardAvailable
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

        // The keyboard, same shape and same five-point step -- with the
        // coarse-device guarantee _nudgeKeyboard explains.
        function keyboardUp(): void {
            root._nudgeKeyboard(1);
        }

        function keyboardDown(): void {
            root._nudgeKeyboard(-1);
        }

        function keyboardSet(percent: int): void {
            root.setKeyboardFraction(percent / 100);
        }

        function keyboardGet(): int {
            return Math.round(root.keyboardFraction * 100);
        }
    }
}
