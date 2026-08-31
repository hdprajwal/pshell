pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The keybind sheet's lifecycle, split off from the widget that draws it.
//
// The same split Weather and Notifications make, for the same reason: the
// widget is built once per monitor under Variants, so an `IpcHandler` on the
// widget would be one handler per screen fighting over one target, and
// `toggle` would open a panel per monitor. The wanted-open state lives here
// and the widgets follow it.
//
// It matters more here than for a widget you click. The cheat sheet's whole
// reason to exist is a keybind -- nobody browses their own keybinds with the
// mouse -- so `pshell keybinds toggle` is the door rather than a convenience
// beside a bar icon. Phase 6 ruled the same way for the weather, and the
// power menu one commit earlier in this phase.
//
// Reading `hyprctl binds -j`, grouping it and drawing it all stay in
// Widgets/Keybinds/Keybinds.qml: those need a panel to live in, and this
// needs to exist on a bar that has no panel at all.
//
// There is a Services/Keybinds.js beside this file, and the pair is fine:
// Services/Weather.js and Services/Weather.qml have sat next to each other
// since Phase 6 and the shell runs. Quickshell synthesizes module types from
// .qml files; a .js library is imported by path and claims no type name.
Singleton {
    id: root

    property bool panelOpen: false
    property string panelScreen: ""

    // Whether a keybinds widget is in the bar at all. Same test Weather and
    // PowerMenu use: an entry whose `id` or `type` is "keybinds" in one of
    // the three sections.
    readonly property bool wanted: Config.hasWidget("keybinds")

    function openPanel(screenName) {
        if (!root.wanted) {
            // The widget draws this sheet, so without one there is nothing to
            // open. Saying so beats `pshell keybinds toggle` exiting 0 having
            // done nothing visible -- which is what a bare `panelOpen = true`
            // would do, twice, before anyone thought to check the bar config.
            //
            // Honest about what this split does and does not buy: the service
            // means the command is always answered, not that there is always
            // a sheet. Drawing one without a widget would mean a second panel
            // implementation living here, for a bar the user chose not to put
            // the widget on.
            console.warn("pshell: no keybinds widget in the bar, so there is no sheet to open. Add {\"type\": \"keybinds\"} to a section in config.json");
            return;
        }
        root.panelScreen = screenName !== undefined && String(screenName) !== "" ? String(screenName) : root._focusedScreenName();
        root.panelOpen = true;
    }

    function closePanel() {
        root.panelOpen = false;
    }

    function togglePanel(screenName) {
        if (root.panelOpen)
            closePanel();
        else
            openPanel(screenName);
    }

    // Same resolution Notifications, Weather and PowerMenu use, for the same
    // reason: IPC has no widget to ask, and the focused monitor is where the
    // eyes are.
    function _focusedScreenName() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            return mon.name;
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    IpcHandler {
        target: "pshell.keybinds"

        function toggle(): void {
            root.togglePanel();
        }

        function open(): void {
            root.openPanel();
        }

        function close(): void {
            root.closePanel();
        }
    }
}
