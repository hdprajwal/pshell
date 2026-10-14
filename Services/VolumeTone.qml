pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "VolumeTone.js" as Model

// A short tone on the default output once its volume stops moving, so you
// hear how loud it is now and which device is going to play -- what Windows
// does when you let go of its volume slider. Asked for on Omarchy
// (omacom/omarchy discussion 15016) and prototyped there as
// GruperTal/omarchy-volume-beep; this follows that prototype's timing and
// its silences, and differs from it in two places.
//
// The keys sound too, by default. The prototype stays silent on them and
// watches Hyprland's layer events to tell a key from its panel. pshell does
// not try: the request is about hearing the new level, and the keys are
// where most changes come from. `volumeTone.keys: false` keeps the tone to
// pshell's own slider, scroll and `pshell audio`, which pshell can tell
// apart because they go through Audio.setVolume (see Audio.lastSetAt).
//
// And the tone is aimed at the sink whose volume moved, by name, rather
// than at whatever the default is by the time it plays.
//
// Everything is seen through Pipewire, because that is the only place a
// change from swayosd, pavucontrol or an app shows up. What counts as a
// change, and what does not, is VolumeTone.js's.
//
// A singleton kept alive from shell.qml, so the tone works on a bar with no
// audio widget at all.
Singleton {
    id: root

    readonly property bool enabled: Config.volumeTone.enabled
    readonly property bool keys: Config.volumeTone.keys
    readonly property int delay: Config.volumeTone.delay
    readonly property string customSound: Config.volumeTone.sound

    // ------------------------------------------------------------ watching

    // Names the default sink and its Pipewire id, or "" while there is none
    // whose properties have arrived. A new key is a new sink as far as the
    // tone is concerned: start, a device plugged in, the default switching.
    readonly property string _key: Audio.sinkReady && Audio.sink.ready ? Audio.sink.name + "#" + Audio.sink.id : ""
    property var _state: null

    function _seen() {
        return {
            key: root._key,
            sink: root._key !== "" ? String(Audio.sink.name || "") : "",
            volume: Audio.volume,
            muted: Audio.muted
        };
    }

    function _observe() {
        const out = Model.observe(root._state, root._seen(), Date.now());
        root._state = out.state;
        // Armed whether or not the tone is on, so the level it is measured
        // from stays current and switching it on does not sound for a change
        // made while it was off.
        if (out.arm)
            settle.restart();
    }

    on_KeyChanged: root._observe()

    Component.onCompleted: {
        root._observe();
        root._probe();
    }

    Connections {
        target: Audio

        function onVolumeChanged() {
            root._observe();
        }

        function onMutedChanged() {
            root._observe();
        }
    }

    Timer {
        id: settle

        interval: root.delay
        onTriggered: root._landed()
    }

    // The level has held still for `delay`. Whatever it is now is what the
    // next change is measured from, whether or not this one sounded.
    function _landed() {
        const seen = root._seen();
        const why = Model.verdict(root._state, seen, {
            enabled: root.enabled,
            keys: root.keys,
            own: Model.isOwnChange(Audio.lastSetAt, root._state ? root._state.changedAt : 0)
        });
        root._state = Model.settle(root._state, seen);
        if (why === "")
            root._play(seen.sink);
    }

    // ------------------------------------------------------------- playing

    // What the probe found: the players on PATH, and which of the two
    // candidate sounds can be read.
    property bool probed: false
    property var _players: []
    property var _files: []
    readonly property string player: Model.choosePlayer(_players)
    readonly property string sound: Model.chooseSound(customSound, _files)

    // One warning per run, whatever it is about. A missing player is not
    // news the second time, and the tone is not worth a log full of it.
    property bool _warned: false

    function _warn(message) {
        if (root._warned)
            return;
        root._warned = true;
        console.warn("pshell: " + message);
    }

    // Plays the tone once on `sink`. "" when it started, or the line to
    // hand back to `pshell audio tone test`.
    function _play(sink) {
        if (!root.probed)
            return "error: still looking for a player, try again in a moment";
        if (root.player === "") {
            root._warn("no pw-play, paplay or canberra-gtk-play on PATH, so volume changes make no tone.");
            return "error: no pw-play, paplay or canberra-gtk-play on PATH. pw-play comes with pipewire.";
        }
        if (root.sound === "") {
            root._warn("no readable sound for the volume tone at " + (root.customSound || Model.DEFAULT_SOUND) + ", so volume changes make no tone.");
            return "error: no sound to play. Install sound-theme-freedesktop, or point volumeTone.sound at a file.";
        }
        if (root.customSound !== "" && root.sound !== root.customSound)
            root._warn("cannot read " + root.customSound + " for the volume tone; using " + root.sound + " instead.");

        const argv = Model.playerArgv(root.player, root.sound, sink);
        if (argv.length === 0)
            return "error: nothing to play with";

        // Never two at once. A tone still playing when the next is due is
        // stopped, and the new one starts when it has gone: the level that
        // matters is the newest.
        tone.next = argv;
        if (tone.busy) {
            tone.stopping = true;
            tone.running = false;
        } else {
            root._startNext();
        }
        return "";
    }

    // Whether a tone is playing, or about to: the control centre hides a
    // canberra-gtk-play stream only then.
    readonly property bool playing: tone.busy

    // Why the last tone did not play, while it is still true: set when the
    // player could not be started, cleared when one starts. For `test`,
    // which answers before the player has had the chance to fail.
    property string _failure: ""

    function _startNext() {
        if (tone.next.length === 0)
            return;
        tone.command = tone.next;
        tone.next = [];
        tone.stopping = false;
        tone.busy = true;
        tone.running = true;
        deadline.restart();
    }

    Process {
        id: tone

        // Ours, not `running`: a Process told to stop is still on its way
        // out, and a third tone in that moment must wait for it too.
        property bool busy: false
        property bool stopping: false
        property var next: []

        onStarted: root._failure = ""

        // A player that cannot be started -- pw-play removed by an upgrade
        // since the probe -- never exits. Quickshell drops the process and
        // reports only that it is not running, so without this `busy` would
        // stay set and every tone after it would wait for an exit that is
        // never coming. A normal exit has cleared `busy` by now.
        onRunningChanged: {
            if (!tone.running && tone.busy)
                root._failedToStart();
        }

        onExited: code => {
            deadline.stop();
            tone.busy = false;
            if (code !== 0 && !tone.stopping)
                root._warn(String(tone.command[0]) + " exited with " + code + " playing the volume tone on " + JSON.stringify(tone.command));
            tone.stopping = false;
            root._startNext();
        }
    }

    // The sound is a fraction of a second. A player that is still going
    // after three -- stuck on a sink that went away -- is stopped, so it
    // cannot hold the next tone up for ever.
    Timer {
        id: deadline

        interval: 3000
        onTriggered: {
            if (!tone.running && tone.busy) {
                root._failedToStart();
                return;
            }
            tone.stopping = true;
            tone.running = false;
        }
    }

    // Clears the way for the next tone, and looks for the players again:
    // the one chosen is gone, and another may be there to take its place.
    function _failedToStart() {
        deadline.stop();
        const player = String(tone.command[0]);
        tone.busy = false;
        tone.stopping = false;
        root._failure = player + " could not be started";
        root._warn(player + " could not be started for the volume tone; looking for a player again.");
        root._probe();
        root._startNext();
    }

    // Which players are on PATH and which sounds can be read, through sh so
    // the lookup is the one the player itself will get. Again whenever the
    // configured sound changes.
    function _probe() {
        if (prober.running) {
            prober.again = true;
            return;
        }
        prober.command = ["sh", "-c", "for p in " + Model.PLAYERS.join(" ") + "; do command -v \"$p\" >/dev/null 2>&1 && echo \"$p\"; done; for f; do [ -f \"$f\" ] && [ -r \"$f\" ] && echo \"file $f\"; done; exit 0", "sh", root.customSound, Model.DEFAULT_SOUND];
        prober.running = true;
    }

    onCustomSoundChanged: {
        root._warned = false;
        root._probe();
    }

    Process {
        id: prober

        property bool again: false

        stdout: StdioCollector {
            id: proberOut
        }
        onExited: {
            const found = Model.parseProbe(proberOut.text);
            root._players = found.players;
            root._files = found.files;
            root.probed = true;
            if (prober.again) {
                prober.again = false;
                root._probe();
            }
        }
    }

    // `pshell audio tone`, by way of Audio's IPC handler: the target is
    // pshell.audio, and two handlers cannot share a target.
    function command(action) {
        switch (String(action || "")) {
        case "on":
            Config.set("volumeTone.enabled", true);
            return "on";
        case "off":
            Config.set("volumeTone.enabled", false);
            return "off";
        case "toggle":
            {
                const next = !root.enabled;
                Config.set("volumeTone.enabled", next);
                return next ? "on" : "off";
            }
        case "test":
            return root.test();
        case "status":
        case "":
            return root.status();
        }
        return "error: tone takes on, off, toggle, test or status, not " + JSON.stringify(String(action));
    }

    // Once, now, on the default output at its current level, whether the
    // tone is on or not -- to hear what it sounds like before choosing.
    function test() {
        if (root._key === "")
            return "error: there is no output to play on";
        const sink = String(Audio.sink.name || "");
        const failed = root._failure;
        const err = root._play(sink);
        if (err !== "")
            return err;
        // Starting is asynchronous, so a player that cannot start has not
        // said so yet. The last attempt's failure is the honest answer.
        if (failed !== "")
            return "error: " + failed + " last time; tried again, run test once more to hear whether it worked";
        return "played on " + Audio.sinkName + " at " + Math.round(Audio.volume * 100) + "%" + (Audio.muted ? ", which is muted" : "");
    }

    function status() {
        return (root.enabled ? "on" : "off")
            + (root.keys ? "" : ", pshell's own changes only")
            + ", after " + root.delay + "ms"
            + ", " + (!root.probed ? "looking for a player" : root.player !== "" ? "with " + root.player : "no player")
            + ", " + (root.sound !== "" ? root.sound : "no sound");
    }
}
