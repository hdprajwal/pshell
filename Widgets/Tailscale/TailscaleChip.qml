import QtQuick
import qs.Services

// A filter chip with its count. Selected fills with the accent and draws its
// text in the background colour, which is the same inverted pill the active
// workspace uses, so the bar has one idea of what "selected" looks like.
Rectangle {
    id: root

    property string label: ""
    property int count: 0
    property bool selected: false

    signal picked

    width: row.implicitWidth + 20
    height: Math.round(Config.fontSize * 2.1)
    radius: height / 2
    color: root.selected ? Config.accent : (pointer.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.selected
            text: "✓"
            color: Config.bg
            font.family: Config.fontFamily
            font.pixelSize: Math.round(Config.fontSize * 0.9)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label + " (" + root.count + ")"
            color: root.selected ? Config.bg : Config.fg
            font.family: Config.fontFamily
            font.pixelSize: Math.round(Config.fontSize * 0.9)
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
