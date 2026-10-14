.pragma library

// The volume tone's decisions: whether a change in the default sink's
// volume is one to answer with a tone, and the command line that plays it.
// Kept out of Services/VolumeTone.qml so `node --test` can load it the way
// tests/load-qml-js.mjs loads the others -- "no tone at start, on a device
// switch, when muted, at 0%, or when the level came back to where it was"
// is a list of corners, and corners are what a test is for.
//
// The QML side feeds it plain snapshots, never Pipewire objects:
//
//   seen  = { key, sink, volume, muted }
//
// `key` is "" while there is no default sink whose properties are ready,
// and otherwise names that sink and its Pipewire id together, so the same
// device unplugged and plugged back in counts as a new one. `sink` is the
// node name the player targets.

// Volumes closer than this are the same volume. Pipewire reports a level
// set from the command line back as the average of the channels, which
// lands a hair off the number asked for; a real step is a whole percent.
var EPSILON = 0.002;

// How long after a sink appears, or becomes the default, its level is
// taken as given rather than as a change. A device reports the level it
// stored as it binds, a moment after it is known -- that is not anyone
// turning it up.
var QUIET_MS = 1000;

// How long the level has to hold still before the tone plays. A held key
// repeats faster than this and a drag reports far faster, so either is one
// tone at the end. The prototype this follows settled on 180.
var DEFAULT_DELAY = 180;
var MIN_DELAY = 50;
var MAX_DELAY = 2000;

// How long after pshell sets the volume a change can land and still be
// pshell's: Pipewire reports a level set through Quickshell back within a
// few milliseconds, and a key press a moment later is not pshell's.
var OWN_LAG_MS = 150;

// The players, in the order they are tried. pw-play first because it is
// Pipewire's own and takes a node by name; paplay talks to the same server
// through pipewire-pulse and takes a sink by name; canberra-gtk-play is the
// last resort and the only one that cannot be aimed at a sink -- it plays
// on the default, which is the sink the tone is about anyway, as long as
// the default has not moved between the change and the tone. VolumeTone.qml
// checks that before it plays.
var PLAYERS = ["pw-play", "paplay", "canberra-gtk-play"];

// sound-theme-freedesktop's own volume-change sound: a 70 ms click, the
// sound GNOME plays for the same thing.
var DEFAULT_SOUND = "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga";

// The stream's name, so the control centre's list of what is playing can
// leave it out rather than flash a row for every tone. pw-play and paplay
// take it as a property; canberra-gtk-play cannot be told one, and names
// its node after itself -- see isToneStream.
var NODE_NAME = "pshell.volume-tone";
var CANBERRA_NODE = "canberra-gtk-play";

// --------------------------------------------------------------- config

function clampDelay(value) {
    if (value === undefined || value === null || value === "")
        return DEFAULT_DELAY;
    var n = Number(value);
    if (!isFinite(n))
        return DEFAULT_DELAY;
    return Math.min(MAX_DELAY, Math.max(MIN_DELAY, Math.round(n)));
}

// --------------------------------------------------------------- watching

function same(a, b) {
    return Math.abs(Number(a) - Number(b)) < EPSILON;
}

// What a new reading does to the state, and whether it starts (or
// restarts) the wait for the level to settle.
//
// state = { key, settled, last, muted, quietUntil, changedAt }, or null
// before the first reading. `settled` is the level the last tone was about,
// or the level the sink came up at; the tone is for a move away from it.
// `last` is the previous reading, so that only a moving level keeps the
// wait going. `changedAt` is when the level last moved, for isOwnChange.
//
// Returns { state, arm }. Never arms on:
//   - no sink, or a sink that is not ready yet;
//   - the first reading, or a different sink than last time -- shell start,
//     a sink appearing, the default switching to another device;
//   - anything inside the quiet window after one of those;
//   - a reading whose level did not move, which is what a mute toggle is.
function observe(state, seen, now) {
    if (!seen || !seen.key)
        return { state: null, arm: false };

    var volume = Number(seen.volume) || 0;
    var muted = !!seen.muted;

    if (!state || state.key !== seen.key) {
        return {
            state: { key: seen.key, settled: volume, last: volume, muted: muted, quietUntil: now + QUIET_MS, changedAt: 0 },
            arm: false
        };
    }

    if (now < state.quietUntil) {
        return {
            state: { key: state.key, settled: volume, last: volume, muted: muted, quietUntil: state.quietUntil, changedAt: 0 },
            arm: false
        };
    }

    var moved = !same(volume, state.last);
    return {
        state: { key: state.key, settled: state.settled, last: volume, muted: muted, quietUntil: state.quietUntil, changedAt: moved ? now : (state.changedAt || 0) },
        arm: moved
    };
}

// Whether the last change to land came from pshell itself: the control
// centre's slider or scroll, or `pshell audio`. Anything else -- swayosd on
// the volume keys, pavucontrol, an app -- is outside. Asked of the change,
// not of the moment the tone is due: a scroll followed half a second later
// by a volume key is the key's level, and the key's to answer for.
function isOwnChange(lastOwnAt, changedAt) {
    if (!lastOwnAt || !changedAt)
        return false;
    var lag = changedAt - lastOwnAt;
    return lag >= 0 && lag <= OWN_LAG_MS;
}

// Whether the tone plays now that the level has held still. `opts` is
// { enabled, keys, own }: `keys` is whether a change from outside pshell
// sounds, and `own` whether this one was pshell's. Returns the reason it
// does not, or "" when it does -- the reason is for `pshell audio tone
// status` and for the tests, not for a log.
function verdict(state, seen, opts) {
    if (!opts || !opts.enabled)
        return "off";
    if (!state || !seen || !seen.key || seen.key !== state.key)
        return "sink changed";
    if (seen.muted)
        return "muted";
    var volume = Number(seen.volume) || 0;
    if (volume < EPSILON)
        return "silent";
    if (same(volume, state.settled))
        return "unchanged";
    if (!opts.own && !opts.keys)
        return "not pshell's";
    return "";
}

// The state once the tone has played or been passed over: whatever the
// level is now is the one the next change is measured from. A level that
// moved while muted is taken as settled too, so unmuting at it is quiet.
function settle(state, seen) {
    if (!state || !seen || seen.key !== state.key)
        return state;
    var volume = Number(seen.volume) || 0;
    return { key: state.key, settled: volume, last: volume, muted: !!seen.muted, quietUntil: state.quietUntil, changedAt: state.changedAt || 0 };
}

// ---------------------------------------------------------------- playing

// What `sh` printed for the probe in VolumeTone.qml: one line per player
// found on PATH, by name, and one `file <path>` line per sound that is
// readable. Anything else is ignored.
function parseProbe(text) {
    var out = { players: [], files: [] };
    var lines = String(text === undefined || text === null ? "" : text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\r$/, "");
        if (line.indexOf("file ") === 0) {
            var path = line.substring(5);
            if (path !== "" && out.files.indexOf(path) < 0)
                out.files.push(path);
        } else if (PLAYERS.indexOf(line.trim()) >= 0 && out.players.indexOf(line.trim()) < 0) {
            out.players.push(line.trim());
        }
    }
    return out;
}

function choosePlayer(found) {
    var list = found || [];
    for (var i = 0; i < PLAYERS.length; i++) {
        if (list.indexOf(PLAYERS[i]) >= 0)
            return PLAYERS[i];
    }
    return "";
}

// The sound to play: the configured one when it is readable, and otherwise
// the freedesktop one, so a typo in config.json costs the custom sound
// rather than the tone. "" when neither can be read.
function chooseSound(custom, readable) {
    var list = readable || [];
    var mine = String(custom || "");
    if (mine !== "" && list.indexOf(mine) >= 0)
        return mine;
    if (list.indexOf(DEFAULT_SOUND) >= 0)
        return DEFAULT_SOUND;
    return "";
}

// A path the player cannot take for an option. Every player here reads a
// leading `-` as a flag, and canberra-gtk-play has no `--` to stop that, so
// a relative path that starts with one is spelled from `./` instead.
function safePath(file) {
    var path = String(file || "");
    return path.charAt(0) === "-" ? "./" + path : path;
}

// The command line that plays `file` once on the sink named `sink`.
//
// No volume flag on any of them. Each plays at its own unity, so the tone
// comes out exactly as loud as the sink now is -- which is the point -- and
// never louder. pw-play's stream properties name the stream so it is not
// mistaken for an app, and give WirePlumber a name of its own to remember
// a stream volume under, rather than the one every other pw-play shares.
// No `--media-role Notification`, which the prototype used: WirePlumber
// keys every Notification-role stream's volume together
// (state-stream.lua, formKey), so a notification sound turned down in
// pavucontrol would quietly turn the tone down with it.
// canberra-gtk-play cannot be told a sink; see PLAYERS.
function playerArgv(player, file, sink) {
    var target = String(sink || "");
    if (!file)
        return [];
    file = safePath(file);
    if (player === "pw-play") {
        var argv = ["pw-play"];
        if (target !== "")
            argv.push("--target", target);
        argv.push("-P", JSON.stringify({
            "node.name": NODE_NAME,
            "application.name": "pshell",
            "media.name": "Volume tone"
        }));
        argv.push(file);
        return argv;
    }
    if (player === "paplay") {
        var pa = ["paplay"];
        if (target !== "")
            pa.push("--device=" + target);
        pa.push("--client-name=pshell", "--stream-name=Volume tone", "--property=node.name=" + NODE_NAME, file);
        return pa;
    }
    if (player === "canberra-gtk-play")
        return ["canberra-gtk-play", "-f", file, "-d", "Volume tone"];
    return [];
}

// Whether a Pipewire stream is the tone. pw-play and paplay carry
// NODE_NAME. canberra-gtk-play names its node after itself and puts the
// file in media.name, but Quickshell only has a node's properties once
// something binds it -- the row the list would draw -- so the name is all
// there is to go on. A canberra-gtk-play stream is taken for the tone only
// while pshell is playing one with it, so someone else's sound at any other
// moment stays listed.
function isToneStream(nodeName, tonePlayer, tonePlaying) {
    if (nodeName === NODE_NAME)
        return true;
    return !!tonePlaying && tonePlayer === CANBERRA_NODE && nodeName === CANBERRA_NODE;
}
