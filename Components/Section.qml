import QtQuick
import Quickshell
import qs.Services
import qs.Widgets.ActiveWindow
import qs.Widgets.Microphone
import qs.Widgets.Privacy
import qs.Widgets.IdleInhibitor
import qs.Widgets.Tailscale
import qs.Widgets.Battery
import qs.Widgets.Bluetooth
import qs.Widgets.Calendar
import qs.Widgets.Clock
import qs.Widgets.ControlCenter
import qs.Widgets.Network
import qs.Widgets.ProcWidget
import qs.Widgets.Tray
import qs.Widgets.Workspaces
import qs.Commons

Row {
    id: root

    property var entries: []
    property var bar: null

    readonly property bool vertical: Config.position === "left" || Config.position === "right"

    // Indicator host. A BarIndicator conceals itself when it has nothing to
    // report, and goes uninteractive with it — so an idle inhibitor that is
    // off could never be switched back on without somewhere to reveal it.
    // Omarchy answers that with a grouped Indicators widget that reveals its
    // dimmed members while the pointer is over them; qsbar keeps indicators
    // as ordinary bar entries, so the section itself plays that part.
    property bool indicatorAreaHovered: false
    property bool indicatorItemHovered: false
    readonly property bool revealInactiveIndicators: indicatorAreaHovered || indicatorItemHovered

    function setIndicatorItemHovered(hovered) {
        if (hovered) {
            indicatorItemHovered = true;
            indicatorHideTimer.stop();
        } else {
            indicatorHideTimer.restart();
        }
    }

    // A moment's grace on the way out, so crossing the gap between two
    // adjacent indicators does not make the row flicker away under the
    // pointer that is reaching for it.
    Timer {
        id: indicatorHideTimer
        interval: 260
        onTriggered: root.indicatorItemHovered = false
    }

    HoverHandler {
        onHoveredChanged: {
            root.indicatorAreaHovered = hovered;
            if (!hovered)
                indicatorHideTimer.restart();
            else
                indicatorHideTimer.stop();
        }
    }

    spacing: Style.spacing.barGap
    height: Style.bar.sizeHorizontal

    Repeater {
        model: root.entries

        Item {
            id: slot

            required property var modelData

            readonly property string widgetId: String(modelData.id || "")
            readonly property string kind: {
                if (modelData.type === "clock" || modelData.type === "calendar" || modelData.type === "activeWindow" || modelData.type === "microphone" || modelData.type === "privacy" || modelData.type === "idleInhibitor" || modelData.type === "tailscale" || modelData.type === "workspaces" || modelData.type === "tray" || modelData.type === "battery" || modelData.type === "network" || modelData.type === "bluetooth" || modelData.type === "controlCenter")
                    return modelData.type;
                if (WidgetRegistry.has(widgetId))
                    return "qml";
                return "proc";
            }
            readonly property var activeItem: builtinLoader.item || qmlLoader.item

            // An indicator keeps its slot width while concealed so the row
            // does not jump when it lights up. That leaves a hole in the bar
            // for something that is not there, so the slot collapses instead
            // and reopens when a hover over the section reveals it.
            //
            // Both flags are state, never visibility: `visible` on a child is
            // inherited from this slot, and this slot hides on zero width, so
            // reading it here would feed straight back into itself.
            readonly property bool slotWanted: {
                if (!activeItem)
                    return false;
                if ("concealed" in activeItem && activeItem.concealed)
                    return false;
                return !("belongsInBlock" in activeItem) || activeItem.belongsInBlock;
            }
            implicitWidth: activeItem && slotWanted ? activeItem.implicitWidth : 0
            implicitHeight: Style.bar.sizeHorizontal
            width: implicitWidth
            height: implicitHeight
            visible: implicitWidth > 0

            // Which widget has a panel open is the bar's business, not the
            // widget's: a widget that coloured itself would have to borrow a
            // palette role that already means something else, and the urgent
            // colour saying "open" reads as saying "wrong".
            readonly property bool panelOpen: PopoutManager.current === activeItem

            // A widget wider than the mark it wants — a text label in a padded
            // slot — can say how long the mark should be, so it tracks what
            // the widget paints rather than the slot it happens to fill.
            readonly property real markExtent: {
                const key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth";
                const hint = activeItem && key in activeItem ? activeItem[key] : undefined;
                if (hint !== undefined && hint !== null && hint > 0)
                    return Math.round(hint);
                return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55));
            }

            Rectangle {
                readonly property int inset: Style.space(2)

                visible: opacity > 0
                opacity: slot.panelOpen ? 0.9 : 0
                color: Color.accent
                radius: Math.min(width, height) / 2
                width: root.vertical ? Style.space(2) : slot.markExtent
                height: root.vertical ? slot.markExtent : Style.space(2)
                // On the edge facing the desktop, so it underlines a top bar
                // and overlines a bottom one — pointing at the side the panel
                // opens on.
                x: root.vertical ? (Config.position === "left" ? parent.width - width - inset : inset) : Math.round((parent.width - width) / 2)
                y: root.vertical ? Math.round((parent.height - height) / 2) : (Config.position === "top" ? parent.height - height - inset : inset)
                z: 50

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }


            Loader {
                id: builtinLoader
                anchors.verticalCenter: parent.verticalCenter
                active: slot.kind !== "qml"
                sourceComponent: {
                    switch (slot.kind) {
                    case "clock":
                        return clockComponent;
                    case "calendar":
                        return calendarComponent;
                    case "activeWindow":
                        return activeWindowComponent;
                    case "microphone":
                        return microphoneComponent;
                    case "privacy":
                        return privacyComponent;
                    case "idleInhibitor":
                        return idleInhibitorComponent;
                    case "tailscale":
                        return tailscaleComponent;
                    case "workspaces":
                        return workspacesComponent;
                    case "tray":
                        return trayComponent;
                    case "battery":
                        return batteryComponent;
                    case "network":
                        return networkComponent;
                    case "bluetooth":
                        return bluetoothComponent;
                    case "controlCenter":
                        return controlCenterComponent;
                    default:
                        return procComponent;
                    }
                }
                // Built-ins now sit on the same bases as a third-party
                // widget — Panel, BarWidget, BarIndicator — so what a slot can
                // inject varies by widget. Ask before setting rather than
                // requiring every widget to carry every property.
                onLoaded: {
                    if (!item)
                        return;
                    if ("cfg" in item)
                        item.cfg = slot.modelData;
                    if ("bar" in item)
                        item.bar = root.bar;
                    if ("settings" in item)
                        item.settings = slot.modelData;
                    if ("indicatorHost" in item)
                        item.indicatorHost = root;
                }
            }

            // A widget discovered on disk. Loading by path is what lets an
            // Omarchy widget drop in without being compiled into qsbar.
            Loader {
                id: qmlLoader
                anchors.verticalCenter: parent.verticalCenter
                active: slot.kind === "qml"
                source: slot.kind === "qml" ? WidgetRegistry.get(slot.widgetId).entry : ""

                onLoaded: {
                    if (!item)
                        return;
                    if ("bar" in item)
                        item.bar = root.bar;
                    if ("moduleName" in item)
                        item.moduleName = slot.widgetId;
                    if ("settings" in item)
                        item.settings = WidgetRegistry.settingsFor(slot.widgetId, slot.modelData);
                    if ("indicatorHost" in item)
                        item.indicatorHost = root;
                    if (root.bar)
                        root.bar.registerModuleWidget(slot.widgetId, item);
                }

                Component.onDestruction: if (item && root.bar)
                    root.bar.unregisterModuleWidget(slot.widgetId, item)
            }
        }
    }

    Component {
        id: clockComponent
        Clock {}
    }
    Component {
        id: calendarComponent
        Calendar {}
    }
    Component {
        id: activeWindowComponent
        ActiveWindow {}
    }
    Component {
        id: microphoneComponent
        Microphone {}
    }
    Component {
        id: privacyComponent
        Privacy {}
    }
    Component {
        id: idleInhibitorComponent
        IdleInhibitor {}
    }
    Component {
        id: tailscaleComponent
        Tailscale {}
    }
    Component {
        id: workspacesComponent
        Workspaces {}
    }
    Component {
        id: trayComponent
        Tray {}
    }
    Component {
        id: batteryComponent
        Battery {}
    }
    Component {
        id: networkComponent
        Network {}
    }
    Component {
        id: bluetoothComponent
        Bluetooth {}
    }
    Component {
        id: controlCenterComponent
        ControlCenter {}
    }
    Component {
        id: procComponent
        ProcWidget {}
    }
}
