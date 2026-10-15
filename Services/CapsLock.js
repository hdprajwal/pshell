.pragma library

// Reading the caps lock LEDs. Kept out of Services/CapsLock.qml so
// `node --test` can load it the way tests/load-qml-js.mjs loads the other
// libraries.

// What the discovery script printed: one LED directory per line, eg.
// /sys/class/leds/input4::capslock. Anything else is dropped, including the
// unexpanded glob a shell prints when nothing matched, and the list comes
// back sorted and without repeats so an unchanged machine compares equal
// and the readers are not rebuilt for nothing.
function parseLedDirs(output) {
    var seen = {};
    var dirs = [];
    var lines = String(output || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var dir = lines[i].trim();
        if (dir.indexOf("/sys/class/leds/") !== 0 || dir.indexOf("*") >= 0)
            continue;
        if (!/::capslock$/.test(dir) || seen[dir])
            continue;
        seen[dir] = true;
        dirs.push(dir);
    }
    dirs.sort();
    return dirs;
}

// A `brightness` file holds a number and a newline. Anything above zero is
// lit; a file that could not be read, or that says something else, is not.
function isLit(text) {
    var n = parseInt(String(text === undefined || text === null ? "" : text).trim(), 10);
    return isFinite(n) && n > 0;
}

// Every keyboard has its own LED. Hyprland lights them all together, but a
// keyboard it has not caught up with yet should not hide the others, so
// any one lit means caps lock is on.
function anyLit(states) {
    if (!states)
        return false;
    for (var i = 0; i < states.length; i++) {
        if (states[i] === true)
            return true;
    }
    return false;
}
