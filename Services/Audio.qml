pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "VolumeTone.js" as ToneModel

// Default sink and source, with their volumes bound live, and the apps
// playing through them.
//
// PwObjectTracker is not optional: Pipewire objects only publish their
// properties while something is tracking them, so without this the volume
// reads back as zero and never changes.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property bool sinkReady: sink !== null && sink.audio !== null
    readonly property bool sourceReady: source !== null && source.audio !== null

    readonly property real volume: sinkReady ? sink.audio.volume : 0
    readonly property bool muted: sinkReady ? sink.audio.muted : true
    readonly property real micVolume: sourceReady ? source.audio.volume : 0
    readonly property bool micMuted: sourceReady ? source.audio.muted : true

    readonly property string sinkName: sink ? (sink.description || sink.nickname || sink.name || "") : ""
    readonly property string sourceName: source ? (source.description || source.nickname || source.name || "") : ""

    // Every sink and source Pipewire knows about, for the device pickers.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)

    // The apps playing right now, for the mixer. A playback stream is a
    // stream that is a sink, in Quickshell's terms: it takes audio from the
    // app and hands it on to a device. Recording streams are the
    // non-sink ones, and Privacy.qml's.
    //
    // Not pshell's own volume tone, which would flash a row after every
    // change made with the mixer open, whichever player plays it. Which
    // player that is comes from VolumeTone, which sets these two; reading
    // VolumeTone from here instead would have the two singletons each
    // waiting on the other to be built.
    property string tonePlayer: ""
    property bool tonePlaying: false
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio && !ToneModel.isToneStream(n.name, root.tonePlayer, root.tonePlaying))

    // When pshell itself last set the output volume -- the control centre's
    // slider and scroll, `pshell audio` -- so VolumeTone can tell those from
    // the keys, which reach Pipewire through swayosd and never pass here.
    property real lastSetAt: 0

    function setVolume(value) {
        if (sinkReady) {
            root.lastSetAt = Date.now();
            sink.audio.volume = Math.max(0, Math.min(1, value));
        }
    }

    function setMicVolume(value) {
        if (sourceReady)
            source.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleMute() {
        if (sinkReady)
            sink.audio.muted = !sink.audio.muted;
    }

    function toggleMicMute() {
        if (sourceReady)
            source.audio.muted = !source.audio.muted;
    }

    function setStreamVolume(node, value) {
        if (node && node.audio)
            node.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleStreamMute(node) {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    // What to call a stream. The app's own name where it gives one --
    // "Firefox", "Spotify" -- else the node's description, else the binary
    // that opened it. media.name is last: it is the tab or the track as
    // often as it is the app.
    function streamName(node) {
        if (!node)
            return "";
        const p = node.properties || {};
        return String(p["application.name"] || node.description || p["application.process.binary"] || p["media.name"] || node.name || "");
    }

    // The stream's app icon, resolved to a file or "". The icon name the app
    // sets comes first, then its desktop entry, then the binary as an icon
    // name, which is how Spotify and most Electron apps end up found.
    //
    // Reading the entry list's length is what makes a binding over this
    // re-run once the desktop entry scan has finished, as in ActiveWindow.
    function streamIcon(node) {
        if (!node)
            return "";
        const p = node.properties || {};
        const named = Icons.path(p["application.icon-name"]);
        if (named !== "")
            return named;
        const binary = String(p["application.process.binary"] || "");
        const app = String(p["application.name"] || "");
        const scanned = DesktopEntries.applications.values.length;
        const entry = scanned > 0 && (binary || app) ? DesktopEntries.heuristicLookup(binary || app) : null;
        const fromEntry = entry ? Icons.fromEntry(entry.icon) : "";
        if (fromEntry !== "")
            return fromEntry;
        return Icons.first([binary, app.toLowerCase()]);
    }

    // Every stream whose name is `name`, ignoring case. A browser playing in
    // two tabs is two streams under one name, and a script asking for
    // "firefox" means both.
    function streamsNamed(name) {
        const want = String(name || "").toLowerCase();
        return root.streams.filter(n => root.streamName(n).toLowerCase() === want);
    }

    function setSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // The streams are tracked here rather than by the rows that draw them,
    // so `pshell audio apps` reads real volumes with the panel shut.
    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.streams)
    }

    // Out here rather than in the handler, where every function is a
    // method on the command line.
    function setAppMuted(name, muted) {
        const found = root.streamsNamed(name);
        if (found.length === 0)
            return root.noApp(name);
        found.forEach(n => {
            n.audio.muted = muted;
        });
        return "";
    }

    function noApp(name) {
        return "error: nothing called " + JSON.stringify(String(name)) + " is playing. `pshell audio apps` lists what is.";
    }

    IpcHandler {
        target: "pshell.audio"

        // Percent at this boundary, fraction inside. A person typing
        // `pshell audio setVolume 40` means forty percent; the 0-1 fraction
        // is the service's convention, not the command line's. The
        // service's own setters already clamp, so nothing is checked twice.
        function volumeUp(): void {
            root.setVolume(root.volume + 0.05);
        }

        function volumeDown(): void {
            root.setVolume(root.volume - 0.05);
        }

        function setVolume(percent: int): void {
            root.setVolume(percent / 100);
        }

        // The absolute forms, not just the toggle. A script that wants
        // silence has to be able to ask for silence -- calling toggle from
        // a script is a coin flip on whatever the current state is.
        function mute(): void {
            if (root.sinkReady)
                root.sink.audio.muted = true;
        }

        function unmute(): void {
            if (root.sinkReady)
                root.sink.audio.muted = false;
        }

        function toggleMute(): void {
            root.toggleMute();
        }

        function micToggleMute(): void {
            root.toggleMicMute();
        }

        function micSetVolume(percent: int): void {
            root.setMicVolume(percent / 100);
        }

        // The tone after a volume change: on, off, toggle, test or status.
        // One method with a word rather than five, so they read as
        // `pshell audio tone on` beside the volume they are about. The
        // service lives in VolumeTone.qml; this target is the audio one.
        function tone(action: string): string {
            return VolumeTone.command(action);
        }

        // The mixer, by app name, ignoring case: `pshell audio
        // appSetVolume spotify 30`. A name that matches several streams
        // applies to all of them. One the shell cannot find is an error, so
        // a script hears about the typo.
        function apps(): string {
            return root.streams.map(n => "\"" + root.streamName(n) + "\" "
                + Math.round(n.audio.volume * 100) + "%"
                + (n.audio.muted ? " muted" : "")).join("\n");
        }

        function appSetVolume(name: string, percent: int): string {
            const found = root.streamsNamed(name);
            if (found.length === 0)
                return root.noApp(name);
            found.forEach(n => root.setStreamVolume(n, percent / 100));
            return "";
        }

        function appMute(name: string): string {
            return root.setAppMuted(name, true);
        }

        function appUnmute(name: string): string {
            return root.setAppMuted(name, false);
        }

        // Answers with the state it left the app in. Several streams under
        // one name move together: muted if any of them was playing, so a
        // toggle never leaves a browser half muted.
        function appToggleMute(name: string): string {
            const found = root.streamsNamed(name);
            if (found.length === 0)
                return root.noApp(name);
            const mute = found.some(n => !n.audio.muted);
            root.setAppMuted(name, mute);
            return mute ? "muted" : "unmuted";
        }

        // One line a script can grep. "muted" sits directly after the
        // percent it qualifies, so `pshell audio status | grep -q 'mic
        // .* muted'` and friends work without parsing.
        function status(): string {
            return "volume " + Math.round(root.volume * 100) + "%"
                + (root.muted ? " muted" : "")
                + " sink \"" + root.sinkName + "\""
                + " mic " + Math.round(root.micVolume * 100) + "%"
                + (root.micMuted ? " muted" : "")
                + " source \"" + root.sourceName + "\"";
        }
    }
}
