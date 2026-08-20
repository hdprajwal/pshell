import QtQuick
import qs.Services
import qs.Commons

// One row in the expanded exit node list.
Rectangle {
    id: root

    property string label: ""
    property bool selected: false

    signal picked

    height: Math.round(Style.font.body * 2.2)
    radius: 4
    color: pointer.containsMouse ? Style.hoverFill : "transparent"

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: (root.selected ? "✓  " : "") + root.label
        color: root.selected ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
