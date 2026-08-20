import QtQuick
import qs.Services
import qs.Commons

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
    height: Math.round(Style.font.body * 2.1)
    radius: height / 2
    color: root.selected ? Color.accent : (pointer.containsMouse ? Style.selectedFill : Style.normalFill)

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
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.body * 0.9)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label + " (" + root.count + ")"
            color: root.selected ? Color.background : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.body * 0.9)
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
