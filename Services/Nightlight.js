.pragma library

// The nightlight's arithmetic: which temperatures are allowed, what
// `hyprctl hyprsunset temperature` said, and whether the schedule says it is
// night. Kept out of Services/Nightlight.qml so `node --test` can load it the
// way tests/load-qml-js.mjs loads the other libraries -- clock maths across
// midnight is exactly the kind of thing that is wrong by one in a way nobody
// notices until 23:59.
//
// The parsing follows Omarchy's NightlightModel.js, made stricter: see
// parseTemperature.

// Below 1000K hyprsunset's curve is all red and no picture. Above 6000K is
// Omarchy's identity threshold -- warmer than nothing by too little to see --
// so a nightlight set there is a nightlight that does nothing.
var MIN_TEMPERATURE = 1000;
var MAX_TEMPERATURE = 6000;
var DEFAULT_TEMPERATURE = 4000;

// A temperature from config.json, which a person typed. Anything that is not
// a number falls back to the default, and a number out of range is pulled
// into it: a config file is not a place to report errors to, and 9000 still
// says "as cool as it goes".
function clampTemperature(value) {
    if (value === undefined || value === null || value === "")
        return DEFAULT_TEMPERATURE;
    var n = Number(value);
    if (!isFinite(n))
        return DEFAULT_TEMPERATURE;
    return Math.min(MAX_TEMPERATURE, Math.max(MIN_TEMPERATURE, Math.round(n)));
}

// A temperature from the command line, which is answered rather than fixed
// up: `pshell nightlight setTemperature 400` is a typo for 4000, and quietly
// writing 1000 into config.json would be the wrong guess.
function isValidTemperature(value) {
    var n = Number(value);
    return isFinite(n) && Math.round(n) === n && n >= MIN_TEMPERATURE && n <= MAX_TEMPERATURE;
}

// What `hyprctl hyprsunset temperature` printed, or null.
//
// The whole answer has to be the number. Omarchy takes the first run of
// digits anywhere in the output, which reads hyprctl's own failure --
// "Couldn't connect to /run/user/1000/hypr/.../.hyprsunset.sock. (3)" -- as a
// temperature of 1000K. The exit code catches that too, but a parser that
// cannot be fooled does not need the caller to remember.
function parseTemperature(output) {
    var text = String(output === undefined || output === null ? "" : output);
    var m = text.match(/^\s*(\d+)\s*K?\s*$/i);
    return m ? Number(m[1]) : null;
}

function formatTemperature(kelvin) {
    return Math.round(Number(kelvin)) + "K";
}

// "HH:MM" on a 24-hour clock, as minutes since midnight; -1 for anything
// else. One digit of hour is allowed, because "7:00" is how people write it.
function parseClock(text) {
    var m = String(text === undefined || text === null ? "" : text).trim().match(/^(\d{1,2}):(\d{2})$/);
    if (!m)
        return -1;
    var h = Number(m[1]);
    var min = Number(m[2]);
    if (h > 23 || min > 59)
        return -1;
    return h * 60 + min;
}

// A schedule is two clock times that are not the same time. Equal start and
// end could mean "always" or "never", and either guess is wrong for someone,
// so it means no schedule.
function hasSchedule(start, end) {
    var s = parseClock(start);
    var e = parseClock(end);
    return s >= 0 && e >= 0 && s !== e;
}

// Whether the schedule says the nightlight is on at `minutes` past midnight.
// The start is inside the window and the end is not, so 20:00-07:00 is on at
// 20:00 and off at 07:00 sharp. A start later than the end runs through
// midnight, which is the normal case for a nightlight.
function scheduledOn(minutes, start, end) {
    if (!hasSchedule(start, end))
        return false;
    var s = parseClock(start);
    var e = parseClock(end);
    var now = ((Math.floor(Number(minutes)) % 1440) + 1440) % 1440;
    if (s < e)
        return now >= s && now < e;
    return now >= s || now < e;
}

// Minutes past local midnight for a Date. Local, not UTC: "20:00" in
// config.json means the clock on the wall.
function minutesOfDay(date) {
    return date.getHours() * 60 + date.getMinutes();
}

// The one line `pshell nightlight status` prints. `state` carries:
//   available  - hyprsunset is installed
//   on         - pshell wants the screen warm
//   temperature, reported (what hyprsunset last said, or null)
//   owned      - the hyprsunset doing it is pshell's child
//   start, end - the schedule, possibly empty
function statusLine(state) {
    if (!state.available)
        return "unavailable: hyprsunset is not installed (sudo pacman -S hyprsunset)";
    var parts = [state.on ? "on " + formatTemperature(state.temperature) : "off"];
    // What hyprsunset reports only means something while it is warming:
    // `identity` resets the screen, and nothing promises it resets the
    // number hyprsunset answers with.
    if (state.on) {
        parts.push(state.owned ? "hyprsunset started by pshell" : "hyprsunset already running");
        if (state.reported !== null && state.reported !== undefined)
            parts.push("hyprsunset reports " + formatTemperature(state.reported));
    }
    if (hasSchedule(state.start, state.end))
        parts.push("schedule " + String(state.start).trim() + "-" + String(state.end).trim());
    return parts.join(", ");
}
