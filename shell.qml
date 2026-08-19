//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar

            required property var modelData
            readonly property bool vertical: Config.position === "left" || Config.position === "right"

            screen: modelData
            color: Config.bg

            anchors {
                top: Config.position === "top" || bar.vertical
                bottom: Config.position === "bottom" || bar.vertical
                left: Config.position === "left" || !bar.vertical
                right: Config.position === "right" || !bar.vertical
            }

            implicitHeight: bar.vertical ? 0 : Config.size
            implicitWidth: bar.vertical ? Config.size : 0

            WlrLayershell.namespace: "qsbar"
            WlrLayershell.layer: WlrLayer.Top

            Section {
                entries: Config.left
                anchors.left: parent.left
                anchors.leftMargin: Config.gap
                anchors.verticalCenter: parent.verticalCenter
            }

            Section {
                entries: Config.center
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            Section {
                entries: Config.right
                anchors.right: parent.right
                anchors.rightMargin: Config.gap
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
