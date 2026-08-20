import QtQuick
import qs.Services

// One row in the expanded exit node list.
Rectangle {
    id: root

    property string label: ""
    property bool selected: false

    signal picked

    height: Math.round(Config.fontSize * 2.2)
    radius: 4
    color: pointer.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: (root.selected ? "✓  " : "") + root.label
        color: root.selected ? Config.accent : Config.fg
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
