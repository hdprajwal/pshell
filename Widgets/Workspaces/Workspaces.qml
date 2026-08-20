import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Services

Row {
    id: root

    property var cfg: ({})

    // Fall back to a fixed 1..5 so empty workspaces still have somewhere to
    // click, then add any live ones beyond that.
    readonly property var ids: {
        const base = [1, 2, 3, 4, 5];
        const live = Hyprland.workspaces.values;
        for (var i = 0; i < live.length; i++) {
            const id = live[i].id;
            if (id > 0 && base.indexOf(id) === -1)
                base.push(id);
        }
        base.sort((a, b) => a - b);
        return base;
    }

    spacing: 2
    height: Config.size

    Repeater {
        model: root.ids

        Rectangle {
            id: pill

            required property int modelData

            readonly property var workspace: {
                const live = Hyprland.workspaces.values;
                for (var i = 0; i < live.length; i++) {
                    if (live[i].id === modelData)
                        return live[i];
                }
                return null;
            }
            readonly property bool active: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
            readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0

            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(Config.size - 8, label.implicitWidth + 12)
            height: Config.size - 8
            radius: height / 2

            // Inverted pill: the active workspace fills with the foreground
            // colour and draws its number in the background colour.
            color: active ? Config.fg : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }

            Text {
                id: label
                anchors.centerIn: parent
                text: pill.modelData
                color: pill.active ? Config.bg : Config.fg
                opacity: pill.active ? 1 : (pill.occupied ? 0.75 : 0.4)
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
                renderType: Text.NativeRendering

                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + pill.modelData)
            }
        }
    }
}
