import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Services
import qs.Components
import qs.Commons
import qs.Ui

// Whether anything is listening or watching right now.
//
// The two halves are not detected the same way and it is worth knowing which
// is which. A microphone capture is a real Pipewire stream, so it arrives as
// an event and the dot appears the instant a program opens the mic. A camera
// is opened straight on /dev/videoN by most programs, which emits nothing at
// all, so that half is a poll and can be up to `interval` seconds late.
BarIndicator {
    id: root

    property var cfg: ({})

    readonly property bool showCamera: cfg.showCamera !== false
    readonly property int interval: (cfg.interval || 2) * 1000

    // A capture stream is an input stream carrying audio. Sinks are playback
    // and non-streams are the devices themselves, so both are excluded.
    readonly property var micStreams: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio)
    readonly property bool micActive: micStreams.length > 0
    property bool cameraActive: false

    // Properties only populate while something tracks the object, so without
    // this every stream reports an empty property map and there is no way to
    // say which program is recording.
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // application.name is what a program calls itself to Pipewire; the node
    // name is the fallback when it does not bother to say. A dot alone
    // cannot say who is listening, so the detail moves into the tooltip.
    readonly property string detailText: {
        const lines = root.micStreams.map(m => {
            const props = m.properties || ({});
            return String(props["application.name"] || m.name || "something") + " is using the microphone";
        });
        if (root.cameraActive)
            lines.push("The camera is in use");
        return lines.join("\n");
    }

    active: root.micActive || root.cameraActive
    // "active" rather than the default "single": a hover over the bar
    // reveals the indicators you can act on, and this is not one of
    // them. Nothing capturing means nothing to show.
    indicatorBlock: "active"

    iconComponent: Component {
        BarIcon {
            anchors.fill: parent
            // The mic takes the glyph when both are live: it is the
            // event-driven half, so it is the one worth not missing.
            iconSource: root.micActive ? Icons.microphone(false) : Icons.first(["camera-web-symbolic", "camera-video-symbolic", "camera-photo-symbolic"])
            size: Style.bar.iconCanvas
            color: Color.urgent
        }
    }

    // The old panel listed every capturing program by name; that detail
    // lives on here as a tooltip rather than a click target, since a status
    // dot has nothing to open.
    PanelToolTip {
        visible: root.tooltipHovered && root.detailText !== ""
        text: root.detailText
    }

    // fuser exits non-zero when nothing holds the device, which is the whole
    // test; the device list is globbed so a webcam on video2 still counts.
    Process {
        id: cameraProbe
        command: ["sh", "-c", "fuser /dev/video* >/dev/null 2>&1 && echo yes || echo no"]

        stdout: StdioCollector {
            onStreamFinished: root.cameraActive = String(text).trim() === "yes"
        }
    }

    Timer {
        interval: root.interval
        running: root.showCamera
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cameraProbe.running)
                cameraProbe.running = true;
        }
    }

    // Stop claiming the camera is live once the poll is switched off.
    onShowCameraChanged: if (!root.showCamera)
        root.cameraActive = false
}
