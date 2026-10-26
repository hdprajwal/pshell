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
    moduleName: "pshell.workspaces"

    property var cfg: ({})

    // Only workspaces with windows on them, plus the focused one even when
    // it's empty — otherwise switching to a fresh workspace would leave the
    // strip with nothing lit. Persistent-but-empty workspaces stay hidden.
    readonly property var ids: {
        const focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1;
        const base = [];
        const live = Hyprland.workspaces.values;
        for (var i = 0; i < live.length; i++) {
            const ws = live[i];
            if (ws.id > 0 && (ws.id === focusedId || ws.toplevels.values.length > 0))
                base.push(ws.id);
        }
        if (focusedId > 0 && base.indexOf(focusedId) === -1)
            base.push(focusedId);
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
                radius: 2
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
                    // Hyprland 0.5x moved dispatch to Lua: the request is
                    // evaluated as `hl.dispatch(<request>)`, so the old
                    // `workspace 3` reaches it as a bare identifier and dies
                    // on a syntax error. Dispatchers are now tables under
                    // `hl.dsp`, and switching workspace lives on focus rather
                    // than under workspace, which only renames and moves.
                    // `usingLua` is Quickshell's own flag for which IPC a
                    // running Hyprland speaks, so both stay supported without
                    // parsing a version.
                    onPressed: b => {
                        if (b !== Qt.LeftButton)
                            return;
                        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.focus{workspace=" + pill.modelData + "}" : "workspace " + pill.modelData);
                    }
                }
            }
        }
    }
}
