import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Services
import qs.Components

// Whether anything is listening or watching right now.
//
// The two halves are not detected the same way and it is worth knowing which
// is which. A microphone capture is a real Pipewire stream, so it arrives as
// an event and the dot appears the instant a program opens the mic. A camera
// is opened straight on /dev/videoN by most programs, which emits nothing at
// all, so that half is a poll and can be up to `interval` seconds late.
BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

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

    // Nothing in use hides the widget, the way activeWindow does, rather than
    // leaving a permanent icon that means nothing most of the time.
    shown: root.micActive || root.cameraActive
    iconSources: {
        const out = [];
        if (root.micActive)
            out.push(Icons.microphone(false));
        if (root.cameraActive)
            out.push(Icons.first(["camera-web-symbolic", "camera-video-symbolic", "camera-photo-symbolic"]));
        return out;
    }
    iconColor: Config.urgent
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button === Qt.LeftButton)
            panel.toggle(root);
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

    Popout {
        id: panel
        bar: root.bar

        Column {
            spacing: 8

            Text {
                text: "In use"
                color: Config.fg
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 1.2)
            }

            Repeater {
                model: root.micStreams

                Row {
                    required property var modelData

                    spacing: 8

                    BarIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: Icons.microphone(false)
                        size: Math.round(Config.fontSize * 1.2)
                        color: Config.urgent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // application.name is what a program calls itself to
                        // Pipewire; the node name is the fallback when it does
                        // not bother to say.
                        text: {
                            const props = parent.modelData.properties || ({});
                            return String(props["application.name"] || parent.modelData.name || "something") + " is using the microphone";
                        }
                        color: Config.fg
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }
                }
            }

            Row {
                visible: root.cameraActive
                spacing: 8

                BarIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSource: Icons.first(["camera-web-symbolic", "camera-video-symbolic"])
                    size: Math.round(Config.fontSize * 1.2)
                    color: Config.urgent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Deliberately vague. fuser says the device is held, not
                    // by whom, and naming the wrong program would be worse
                    // than naming none.
                    text: "The camera is in use"
                    color: Config.fg
                    font.family: Config.fontFamily
                    font.pixelSize: Config.fontSize
                }
            }
        }
    }
}
