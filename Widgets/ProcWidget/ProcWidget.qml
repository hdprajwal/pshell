import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import qs.Commons

// The whole point of qsbar: a widget is a program.
//
//   interval > 0  ->  run it every N seconds, read its last output
//   interval == 0 ->  keep it running, read one line per update
//
// Output is plain text, or Waybar-style JSON:
//   {"text": "42%", "tooltip": "cpu", "class": "warn"}
Item {
    id: root

    property var cfg: ({})

    readonly property string exec: cfg.exec || ""
    readonly property int interval: cfg.interval !== undefined ? cfg.interval : 0
    readonly property bool streaming: interval <= 0

    property string content: ""
    property string tooltip: ""
    property string cls: ""

    implicitWidth: label.implicitWidth
    implicitHeight: Style.bar.sizeHorizontal
    visible: content !== ""

    function apply(raw) {
        const s = (raw || "").trim();
        if (s === "") {
            content = "";
            tooltip = "";
            cls = "";
            return;
        }
        if (s.charAt(0) === "{") {
            try {
                const o = JSON.parse(s);
                content = o.text !== undefined ? String(o.text) : "";
                tooltip = o.tooltip !== undefined ? String(o.tooltip) : "";
                cls = o.class !== undefined ? String(o.class) : "";
                return;
            } catch (e)
            // not JSON after all, fall through to plain text
            {}
        }
        content = s;
        tooltip = "";
        cls = "";
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.content
        color: root.cls === "urgent" || root.cls === "critical" ? "#f38ba8" : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }

    // Poll mode
    Process {
        id: poller
        command: ["sh", "-c", root.exec]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    Timer {
        running: !root.streaming && root.exec !== ""
        interval: root.interval * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            poller.running = false;
            poller.running = true;
        }
    }

    // Stream mode
    Process {
        running: root.streaming && root.exec !== ""
        command: ["sh", "-c", root.exec]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.apply(data)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !!root.cfg.onClick
        onClicked: Quickshell.execDetached(["sh", "-c", String(root.cfg.onClick)])
    }
}
