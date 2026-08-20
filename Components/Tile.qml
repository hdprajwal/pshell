import QtQuick
import qs.Services
import qs.Commons

// A control centre tile. The icon square toggles the thing on and off; the
// rest of the tile opens its detail list, which is how DMS splits it too.
// One tile, two targets, so a mis-click never toggles your wifi off when you
// meant to pick a network.
Rectangle {
    id: root

    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool expanded: false
    property bool hasDetail: true

    signal toggled
    signal detailRequested

    implicitHeight: Math.round(Style.font.body * 4.2)
    radius: 8
    color: expanded ? Style.selectedFill : (bodyHover.containsMouse ? Style.hoverFill : Style.normalFill)

    MouseArea {
        id: bodyHover
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.hasDetail
        cursorShape: Qt.PointingHandCursor
        onClicked: root.detailRequested()
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            id: iconBox
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Style.font.body * 2.8)
            height: width
            radius: 6
            color: root.active ? Color.foreground : (iconHover.containsMouse ? Style.selectedFill : Style.hoverFill)

            BarIcon {
                anchors.centerIn: parent
                iconSource: root.iconSource
                size: Math.round(Style.font.body * 1.4)
                color: root.active ? Color.background : Color.foreground
            }

            MouseArea {
                id: iconHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled()
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - iconBox.width - 10
            spacing: 1

            Text {
                width: parent.width
                text: root.title
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Color.foreground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.85)
                elide: Text.ElideRight
            }
        }
    }
}
