import QtQuick

// A bar entry made of one or more icons and optional text. Shared by the
// widgets that open a panel, so they hover and space identically.
//
// `iconSources` shows several icons side by side, which is how the control
// centre reports wifi, bluetooth and volume at a glance. `iconSource` is the
// single-icon case. `icon` is a glyph string, used when the icon theme has
// nothing, so a widget still shows something.
Item {
    id: root

    property var iconSources: []
    property string iconSource: ""
    property string icon: ""
    property string text: ""
    property color iconColor: Config.fg
    property bool active: false

    signal clicked(int button)
    signal wheel(int delta)

    readonly property bool usingMulti: iconSources.length > 0
    readonly property bool usingImage: iconSource !== ""
    readonly property int iconSize: Config.barIconSize

    implicitWidth: content.implicitWidth + 10
    implicitHeight: Config.size

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 4
        color: root.active ? Qt.rgba(1, 1, 1, 0.14) : (pointer.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: root.iconSources

            BarIcon {
                required property var modelData

                anchors.verticalCenter: parent.verticalCenter
                iconSource: modelData
                size: root.iconSize
                color: root.iconColor
            }
        }

        BarIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.usingMulti && root.usingImage
            iconSource: root.iconSource
            size: root.iconSize
            color: root.iconColor
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.usingMulti && !root.usingImage && root.icon !== ""
            text: root.icon
            color: root.iconColor
            font.family: Config.iconFont
            font.pixelSize: Math.round(Config.fontSize * 1.1)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: Config.fg
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => root.clicked(mouse.button)
        onWheel: w => root.wheel(w.angleDelta.y)
    }
}
