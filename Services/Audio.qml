pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Default sink and source, with their volumes bound live.
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

    function setSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
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
