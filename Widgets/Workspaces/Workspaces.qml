import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Paints its own pills rather than delegating to one button, because a
// workspace strip is several buttons wide, not one — but each pill is still
// a WidgetButton underneath, for the same hover/press/tooltip wiring every
// other bar control gets, with its own fill colour riding the same
// normal/hover/selected ladder those controls use instead of the old
// invert-on-focus scheme.
BarWidget {
    id: root
    moduleName: "qsbar.workspaces"

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

    implicitWidth: row.implicitWidth
    implicitHeight: root.barSize

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

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
                readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0

                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(root.barSize - 8, button.implicitWidth)
                height: root.barSize - 8
                radius: height / 2
                // Focused beats hover; hover beats idle. Never routed through
                // WidgetButton's own `active`, which means "open panel" and
                // paints urgent — a focused workspace is not an error state.
                color: focused ? Style.selectedFill : (button.tooltipHovered ? Style.hoverFill : Style.normalFill)

                Behavior on color {
                    ColorAnimation {
                        duration: 140
                    }
                }

                WidgetButton {
                    id: button
                    anchors.fill: parent
                    bar: root.bar
                    text: String(pill.modelData)
                    useActiveColor: false
                    opacity: pill.focused ? 1 : (pill.occupied ? 0.75 : 0.4)
                    horizontalMargin: 6
                    verticalPadding: 4
                    onPressed: b => {
                        if (b === Qt.LeftButton)
                            Hyprland.dispatch("workspace " + pill.modelData);
                    }
                }
            }
        }
    }
}
