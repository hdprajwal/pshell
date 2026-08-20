pragma Singleton

import Quickshell
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

    function setVolume(value) {
        if (sinkReady)
            sink.audio.volume = Math.max(0, Math.min(1, value));
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
}
