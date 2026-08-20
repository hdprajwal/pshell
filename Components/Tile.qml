import QtQuick
import qs.Services

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

    implicitHeight: Math.round(Config.fontSize * 4.2)
    radius: 8
    color: expanded ? Qt.rgba(1, 1, 1, 0.14) : (bodyHover.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05))

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
            width: Math.round(Config.fontSize * 2.8)
            height: width
            radius: 6
            color: root.active ? Config.fg : (iconHover.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1))

            BarIcon {
                anchors.centerIn: parent
                iconSource: root.iconSource
                size: Math.round(Config.fontSize * 1.4)
                color: root.active ? Config.bg : Config.fg
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
                color: Config.fg
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Config.fg
                opacity: 0.55
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 0.85)
                elide: Text.ElideRight
            }
        }
    }
}
