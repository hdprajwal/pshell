.pragma library

// When to warn about a low battery. Kept out of Services/BatteryAlert.qml so
// `node --test` can load it, as IdleInhibit.js is.
//
// Warnings come in steps: one at the threshold, then one more each time the
// charge falls another step, so 20%, 15%, 10%, 5% by default. A reading that
// jumps several steps at once (say, 22% before a suspend and 12% after) gives
// one warning for the lowest step reached, not a burst of three.

// The step a charge sits in, or -1 above the threshold: 20 for 16-20%, 15 for
// 11-15%, and so on.
function alertLevel(percent, threshold, step) {
    if (percent > threshold)
        return -1;
    return Math.max(0, threshold - step * Math.floor((threshold - percent) / step));
}

// The step to warn for now, or -1 for no warning. `last` is the step already
// warned for since the charger was last plugged in, -1 for none.
function nextAlert(percent, last, threshold, step) {
    var level = alertLevel(percent, threshold, step);
    if (level < 0)
        return -1;
    if (last < 0 || level < last)
        return level;
    return -1;
}
