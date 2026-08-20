import QtQuick

// Horizontal slider used by the control centre. Click or drag anywhere on
// the track.
Item {
    id: root

    property real value: 0
    property string iconSource: ""
    property bool dimmed: false

    signal moved(real value)

    // While dragging, draw where the pointer is rather than what the service
    // has reported back. Pipewire and brightnessctl both answer a frame or
    // two late, and following them makes the fill trail the cursor even when
    // the value is already correct.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, dragging ? dragValue : value))

    readonly property int iconSize: Math.round(Config.fontSize * 1.4)

    implicitHeight: Math.round(Config.fontSize * 2.2)

    // mouseX is already relative to the track, because the MouseArea fills
    // it. Subtracting the track's own x here as well was what put the fill
    // behind the pointer by exactly the icon's width.
    function _apply(mouseX) {
        const fraction = Math.max(0, Math.min(1, mouseX / track.width));
        root.dragValue = fraction;
        root.moved(fraction);
    }

    Row {
        anchors.fill: parent
        spacing: 8

        BarIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconSource: root.iconSource
            size: root.iconSize
            opacity: root.dimmed ? 0.45 : 1
        }

        Item {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - root.iconSize - 8
            height: root.height

            Rectangle {
                id: groove
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.round(Config.fontSize * 1.5)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.1)

                Rectangle {
                    // Round the cap only once there is something to draw, so
                    // zero reads as empty instead of a stray dot.
                    width: root.shown <= 0 ? 0 : Math.max(parent.height, parent.width * root.shown)
                    height: parent.height
                    radius: parent.radius
                    color: root.dimmed ? Qt.rgba(1, 1, 1, 0.25) : Config.fg
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => {
                    root.dragging = true;
                    root._apply(mouse.x);
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        root._apply(mouse.x);
                }
                onReleased: root.dragging = false
                onCanceled: root.dragging = false
            }
        }
    }
}
