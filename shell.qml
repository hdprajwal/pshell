// Without a platform theme, Qt does not know which icon theme is in use and
// resolves almost nothing: only hicolor icons are found, so battery, network
// and bluetooth all come back empty. gtk3 makes it read the GTK icon theme,
// which is where Papirus and friends are configured.
//@ pragma Env QT_QPA_PLATFORMTHEME=gtk3
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Components
import qs.Services
import qs.Commons
// Qualified, because the unqualified name collides: qs.Services also has a
// `Wallpaper` -- the singleton the keep-alive line below reads -- and two
// modules both offering the name would leave this file using whichever one
// QML resolved last.
import qs.Widgets.Wallpaper as WallpaperLayer
// Qualified for the same collision, other direction: this module has a
// `Notifications` too -- the bar widget -- and the keep-alive line below
// must reach the qs.Services singleton, not the widget type.
import qs.Widgets.Notifications as NotificationLayer

ShellRoot {
    id: shell

    // Whether the bar is drawn, for SUPER+W. Session state, not config: a
    // bar hidden to watch a video full-height should come back on the next
    // login rather than stay gone with nothing on screen to say why.
    //
    // Hiding unmaps the window, so the compositor also drops the space it
    // reserved -- windows grow into the strip rather than leaving a hole.
    property bool barVisible: true

    IpcHandler {
        target: "pshell.bar"

        // show and hide besides toggle, for IdleInhibit's reason: a script
        // that wants the bar up should ask for that, not for "the other
        // thing".
        function toggle(): bool {
            shell.barVisible = !shell.barVisible;
            return shell.barVisible;
        }

        function show(): void {
            shell.barVisible = true;
        }

        function hide(): void {
            shell.barVisible = false;
        }

        function isVisible(): bool {
            return shell.barVisible;
        }
    }

    // Keeps the settings app's IPC handler alive for the whole session.
    //
    // QML brings a singleton to life on the first access that actually runs,
    // not on a mention of it inside a handler body. Both doors into settings
    // are such mentions: the control centre's gear calls SettingsApp from an
    // onClicked, and the settings widget only exists once it is placed in a
    // section. A shell with neither therefore answered `ipc call
    // pshell.settings toggle` with "Target not found", which is the one way
    // in that a first-time user has — the README hands it to them before
    // they have added the widget.
    //
    // Reading it here is the access, and it costs nothing: the window is
    // behind a LazyLoader that stays inactive until something opens it.
    readonly property var settingsApp: SettingsApp

    // Same reason, and a sharper one: the lock has no widget and no gear to
    // be reached from at all. IPC is its only door -- it is what hypridle's
    // lock_cmd calls -- so if nothing here referenced the singleton, `ipc
    // call pshell.lock lock` would answer "Target not found" and the
    // machine would never lock.
    //
    // Costs nothing until it is used: WlSessionLock builds no surface while
    // unlocked, and the preview window is not visible.
    readonly property var lock: Lock

    // Same again for the idle inhibitor: its widget is optional, so a bar
    // without one would leave the singleton unbuilt and `pshell idle
    // toggle` answering "Target not found" -- which is the whole point of
    // moving the state out of the widget.
    //
    // Costs nothing: the overlay surface is behind a Loader that stays
    // inactive while `inhibited` is false, which it is after every start.
    readonly property var idleInhibit: IdleInhibit

    // And again for the notifications service, with the most at stake: this
    // access is what builds the NotificationServer, and building it is what
    // claims org.freedesktop.Notifications on DBus. Left to lazy
    // initialisation, a bar without the notifications widget would never
    // own the name and every notification on the machine would silently go
    // nowhere -- and `pshell notifications toggle`, the keybind's door,
    // would answer "Target not found" on top.
    readonly property var notifications: Notifications

    // And again for the wallpaper: it has no bar widget at all -- the
    // background window below reads Config directly -- so IPC is its only
    // door, exactly like the lock. Without this line `pshell wallpaper next`
    // would answer "Target not found" on a bar without the settings app open.
    //
    // Costs nothing: the singleton holds a path list and two idle Processes.
    readonly property var wallpaper: Wallpaper

    // And the weather, for a reason the others do not have. It does have a bar
    // widget, so on a bar that carries one this line changes nothing. On a bar
    // that does not, it is the difference between `pshell weather current`
    // answering with a temperature and answering "Target not found" -- and a
    // shell script or a keybind should not have to care which widgets are in
    // the bar today.
    //
    // Costs nothing, and specifically costs Open-Meteo nothing: the service
    // gates its refresh timer on the widget being configured, not on being
    // alive, so a bar without the widget makes no request until something asks
    // it to. Existing and polling are two different things and this line only
    // buys the first.
    readonly property var weather: Weather

    // And the power menu, for the lock's reason rather than the weather's:
    // `pshell power poweroff` is a keybind's door and must answer on a bar
    // with no power widget on it -- which is every bar until somebody adds
    // one. Without this line the five session actions would exist only where
    // the menu is already in the bar, which is the one place you do not need
    // them by name.
    //
    // Costs nothing: the singleton holds five strings and an IPC handler, and
    // opens nothing until it is asked to.
    readonly property var powerMenu: PowerMenu

    // And the keybind sheet's service, for the sharpest version of the same
    // reason. Every other panel-only widget -- the control centre, the
    // battery, tailscale -- is a bar icon you click, and its keybind is a
    // convenience. This one exists to answer SUPER+SHIFT+/ and nothing else,
    // so a `Target not found` on a bar that happens not to carry the widget
    // is the whole feature missing rather than a shortcut missing.
    //
    // It does not conjure a sheet out of nothing: the widget still draws it,
    // and without one the service says so by name. What this line buys is
    // that the command is always answered and the answer is a sentence.
    readonly property var keybinds: Keybinds

    // And the clipboard history, for a reason none of the others have: it
    // is not only a door but a recorder. The wl-paste watchers live in the
    // singleton, so until something touched it no copy was being kept, and
    // the first `pshell clipboard` of a session would open on an empty
    // history and only start recording from then.
    //
    // Costs two idle wl-paste processes. The panel itself is behind a
    // LazyLoader that stays inactive until something opens it.
    readonly property var clipboard: Clipboard

    // And the nightlight, for both reasons at once: `pshell nightlight` is a
    // keybind's door on a bar with no nightlight widget, and the schedule
    // lives in the singleton, so until something touched it 20:00 would
    // come and go with the screen still blue.
    //
    // Costs one `command -v` at start and, with a schedule set, a clock
    // check every thirty seconds. hyprsunset is only started when the
    // nightlight is turned on.
    readonly property var nightlight: Nightlight

    // And the update indicator, for the lock's reason: `pshell updates open`
    // is a keybind's door, and the count is something a script may ask on a
    // bar that does not show it.
    //
    // Costs one `command -v` at start and five idle file watches on
    // arch-update's state directory. Nothing is checked until something
    // asks: the distro's own timer does the checking.
    readonly property var updates: Updates

    // The desktop background. A sibling of the bar's Variants, not inside
    // it: the widget carries its own Variants over the screens, and nesting
    // it under the bar's would make one background window per screen per
    // screen.
    WallpaperLayer.Wallpaper {}

    // The toast layer, a sibling of the bar's Variants for the wallpaper's
    // reason: it carries its own Variants over the screens, and nesting it
    // under the bar's would make one stack per screen per screen. Declared
    // here rather than by the bar widget because toasts must appear on a
    // bar with no notifications widget at all -- the server is running
    // either way.
    NotificationLayer.ToastStack {}

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow

            required property var modelData

            // The contract QML widgets read. Names match Omarchy's bar object
            // so a widget written for it works here without edits.
            readonly property bool vertical: Config.position === "left" || Config.position === "right"
            readonly property string position: Config.position
            readonly property int barSize: Style.bar.sizeHorizontal
            readonly property color foreground: Color.foreground
            readonly property color barForeground: Color.foreground
            readonly property color background: Color.background
            readonly property color urgent: Color.urgent
            readonly property string fontFamily: Style.font.family
            // Omarchy's widgets animate their foreground unless the bar says
            // not to. pshell has no setting for it, so it is simply on.
            readonly property bool foregroundAnimationEnabled: true

            // Which way a panel should open, given the edge the bar is on.
            readonly property int popoutEdge: {
                switch (Config.position) {
                case "bottom":
                    return Edges.Top;
                case "left":
                    return Edges.Right;
                case "right":
                    return Edges.Left;
                default:
                    return Edges.Bottom;
                }
            }

            property var moduleWidgetMap: ({})
            readonly property var activePopout: PopoutManager.current

            function run(command) {
                Quickshell.execDetached(["bash", "-lc", String(command)]);
            }

            function showTooltip(target, text) {
                if (!text)
                    return;
                tooltip.target = target;
                tooltip.text = String(text);
            }

            function hideTooltip(target) {
                if (tooltip.target === target)
                    tooltip.target = null;
            }

            // Part of the contract Omarchy widgets expect. Both defer to the
            // same coordinator the built-in panels use, so a third-party
            // widget's popup closes the battery panel and vice versa.
            function requestPopout(owner) {
                PopoutManager.open(owner);
            }

            function releasePopout(owner) {
                PopoutManager.release(owner);
            }

            function registerModuleWidget(name, item) {
                const map = moduleWidgetMap;
                const list = map[name] || [];
                if (list.indexOf(item) < 0)
                    list.push(item);
                map[name] = list;
                moduleWidgetMap = map;
            }

            function unregisterModuleWidget(name, item) {
                const map = moduleWidgetMap;
                const list = map[name] || [];
                const at = list.indexOf(item);
                if (at >= 0)
                    list.splice(at, 1);
                map[name] = list;
                moduleWidgetMap = map;
            }

            function moduleWidgets(name) {
                return moduleWidgetMap[name] || [];
            }

            screen: modelData
            visible: shell.barVisible
            // The surface is transparent and the bar is a rectangle inside
            // it, because a detached bar wants rounded corners and a window
            // cannot have them.
            color: "transparent"

            anchors {
                top: Config.position === "top" || barWindow.vertical
                bottom: Config.position === "bottom" || barWindow.vertical
                left: Config.position === "left" || !barWindow.vertical
                right: Config.position === "right" || !barWindow.vertical
            }

            // Lifts the bar off the screen edges. The compositor still
            // reserves the space, so a maximised window stops outside the
            // margin rather than sliding under it.
            margins {
                top: Style.spacing.barMarginTop
                bottom: Style.spacing.barMarginBottom
                left: Style.spacing.barMarginLeft
                right: Style.spacing.barMarginRight
            }

            implicitHeight: barWindow.vertical ? 0 : Style.bar.sizeHorizontal
            implicitWidth: barWindow.vertical ? Style.bar.sizeVertical : 0

            WlrLayershell.namespace: "pshell"
            WlrLayershell.layer: WlrLayer.Top

            // Clicking the bar itself dismisses whatever panel is open.
            //
            // A popout covers the screen so a click anywhere lands on its
            // own dismiss layer, but it honours exclusive zones, so it never
            // covers the bar. That is what keeps the widgets clickable while
            // a panel is open, and it leaves this as the handler for the one
            // strip the dismiss layer cannot reach.
            //
            // Declared before the sections so they sit above it: a widget's
            // own handler takes the press first and this only ever sees the
            // gaps between them.
            // Square while the bar is flush with the screen: rounding a
            // corner that has nothing behind it just eats the background.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                radius: Style.spacing.barDetached ? Style.cornerRadius : 0
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: PopoutManager.closeAll()
            }

            Section {
                entries: Config.left
                bar: barWindow
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.barPadding
                anchors.verticalCenter: parent.verticalCenter
            }

            Section {
                entries: Config.center
                bar: barWindow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            Section {
                entries: Config.right
                bar: barWindow
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.barPadding
                anchors.verticalCenter: parent.verticalCenter
            }

            PopupWindow {
                id: tooltip

                property var target: null
                property string text: ""

                visible: target !== null && text !== ""
                color: "transparent"
                implicitWidth: tooltipLabel.implicitWidth + 16
                implicitHeight: tooltipLabel.implicitHeight + 10

                anchor.window: barWindow
                anchor.rect.x: tooltip.target ? tooltip.target.mapToItem(null, 0, 0).x + tooltip.target.width / 2 - tooltip.implicitWidth / 2 : 0
                anchor.rect.y: Config.position === "bottom" ? -tooltip.implicitHeight : Style.bar.sizeHorizontal

                Rectangle {
                    anchors.fill: parent
                    color: Color.tooltip.background
                    radius: Style.cornerRadius
                    border.width: Style.spacing.hairline
                    border.color: Color.tooltip.border

                    Text {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        text: tooltip.text
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }
            }
        }
    }
}
