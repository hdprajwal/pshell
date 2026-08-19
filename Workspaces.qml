import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    id: root

    property var cfg: ({})

    spacing: 8
    height: Config.size

    Repeater {
        model: Hyprland.workspaces

        Text {
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            text: modelData.id
            color: modelData.active ? Config.accent : Config.dim
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize

            MouseArea {
                anchors.fill: parent
                onClicked: Hyprland.dispatch("workspace " + modelData.id)
            }
        }
    }
}
