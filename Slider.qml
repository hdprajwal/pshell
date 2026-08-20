import QtQuick

// Horizontal slider used by the control centre. Click or drag anywhere on
// the track.
Item {
    id: root

    property real value: 0
    property string iconSource: ""
    property bool dimmed: false

    signal moved(real value)

    implicitHeight: Math.round(Config.fontSize * 2.2)

    function _apply(mouseX) {
        const f = Math.max(0, Math.min(1, (mouseX - track.x) / track.width));
        root.moved(f);
    }

    Row {
        anchors.fill: parent
        spacing: 8

        BarIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconSource: root.iconSource
            size: Math.round(Config.fontSize * 1.4)
            opacity: root.dimmed ? 0.45 : 1
        }

        Item {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - Math.round(Config.fontSize * 1.4) - 8
            height: root.height

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.round(Config.fontSize * 1.5)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.1)

                Rectangle {
                    width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.value)))
                    height: parent.height
                    radius: parent.radius
                    color: root.dimmed ? Qt.rgba(1, 1, 1, 0.25) : Config.fg
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => root._apply(mouse.x)
                onPositionChanged: mouse => {
                    if (pressed)
                        root._apply(mouse.x);
                }
            }
        }
    }
}
