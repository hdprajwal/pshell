.pragma library

// Picking the screen and the keyboard out of `brightnessctl -lm`.
//
// Kept pure -- no Process, no Quickshell -- for the same reason ConfigPath.js
// is: parsing this output is real logic with real edge cases, and node can
// only test what it can load. Brightness.qml runs the command and hands the
// text in.
//
// The -lm format is one device per line, comma-separated:
//   device,class,current,percent,max
// e.g. `intel_backlight,backlight,4328,61%,7142`. The percent carries a `%`
// suffix, which parseInt reads past on its own.

function parseDevices(output) {
    var devices = [];
    var lines = String(output || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "")
            continue;
        var parts = line.split(",");
        // Anything that is not five fields of the -lm shape is noise --
        // a warning brightnessctl printed, a truncated read -- and one bad
        // line must never cost the caller the devices on the good ones.
        if (parts.length < 5)
            continue;
        var current = parseInt(parts[2], 10);
        var percent = parseInt(parts[3], 10);
        var max = parseInt(parts[4], 10);
        if (isNaN(current) || isNaN(percent) || isNaN(max))
            continue;
        devices.push({
            name: parts[0],
            class: parts[1],
            current: current,
            percent: percent,
            max: max
        });
    }
    return devices;
}

// A device that reports max 0 has no range to move in; treating it as
// present would put a slider on screen that divides by zero to draw itself.
// This is the same judgement Brightness.qml's `available: max > 0` guard
// already makes -- the pickers just make it before the device gets that far.
function usable(device) {
    return device.max > 0;
}

// By class, not by name: `intel_backlight`, `amdgpu_bl0`, `nvidia_0` and
// `acpi_video0` are all screens and all named differently, and the class
// `backlight` is the one thing the kernel gives them in common.
function pickScreen(devices) {
    for (var i = 0; i < devices.length; i++) {
        if (devices[i].class === "backlight" && usable(devices[i]))
            return devices[i];
    }
    return null;
}

// By suffix, not equality: the vendor prefix varies (`asus::`, `dell::`,
// `tpacpi::`, sometimes nothing at all), and `kbd_backlight` is the part
// the kernel's LED naming keeps stable. A prefix match or a substring
// search would be looser than needed -- `/sys/class/leds/` also holds
// `input10::capslock`, `phy0-led` and friends, and none of those end this
// way.
function pickKeyboard(devices) {
    for (var i = 0; i < devices.length; i++) {
        if (devices[i].name.endsWith("kbd_backlight") && usable(devices[i]))
            return devices[i];
    }
    return null;
}
