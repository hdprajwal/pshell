import QtQuick
import Quickshell
import qs.Services
import qs.Widgets.ActiveWindow
import qs.Widgets.AiUsage
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
import qs.Widgets.Settings
// Qualified because the unqualified name collides: qs.Services also exports a
// Notifications -- the singleton -- and this file imports both modules. The
// same answer shell.qml gives for Wallpaper.
import qs.Widgets.Notifications as NotificationsWidget
// Qualified for the same collision, third time: qs.Services also exports a
// Weather -- the singleton this widget draws.
import qs.Widgets.Weather as WeatherWidget
// And a fourth: qs.Services exports the PowerMenu singleton that holds the
// five session commands, and this module exports the widget that draws them.
import qs.Widgets.PowerMenu as PowerMenuWidget
// And a fifth, same shape: qs.Services exports the Keybinds singleton that
// owns the cheat sheet's IPC target and its wanted-open state.
import qs.Widgets.Keybinds as KeybindsWidget
// And a sixth: qs.Services exports the Nightlight singleton that owns
// hyprsunset and the schedule.
import qs.Widgets.Nightlight as NightlightWidget
// And a seventh: qs.Services exports the Updates singleton that watches
// arch-update's state files and owns pshell.updates.
import qs.Widgets.Updates as UpdatesWidget
import qs.Widgets.Tray
import qs.Widgets.Workspaces
import qs.Commons

Row {
    id: root

    property var entries: []
    property var bar: null

    // Every built-in widget type a config entry can name. This used to be a
    // fifteen-term || chain on one line inside `kind`, and every phase that
    // added a widget grew it by one more `modelData.type === "..."` — a line
    // that long stops being reviewable, and the next reader has to diff it
    // by eye to find the new term. An array says the same thing and a new
    // type is one entry here plus one case and one Component below.
    //
    // Order does not matter for the lookup, but it mirrors the switch in
    // builtinLoader so the three lists stay checkable against each other.
    readonly property var builtinTypes: ["clock", "calendar", "aiUsage", "activeWindow", "microphone", "privacy", "idleInhibitor", "tailscale", "workspaces", "tray", "battery", "network", "bluetooth", "controlCenter", "settings", "notifications", "weather", "power", "keybinds", "nightlight", "updates"]

    readonly property bool vertical: Config.position === "left" || Config.position === "right"

    // Indicator host. A BarIndicator conceals itself when it has nothing to
    // report, and goes uninteractive with it — so an idle inhibitor that is
    // off could never be switched back on without somewhere to reveal it.
    // Omarchy answers that with a grouped Indicators widget that reveals its
    // dimmed members while the pointer is over them; pshell keeps indicators
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
                if (root.builtinTypes.indexOf(modelData.type) >= 0)
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
                    case "aiUsage":
                        return aiUsageComponent;
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
                    case "settings":
                        return settingsComponent;
                    case "notifications":
                        return notificationsComponent;
                    case "weather":
                        return weatherComponent;
                    case "power":
                        return powerMenuComponent;
                    case "keybinds":
                        return keybindsComponent;
                    case "nightlight":
                        return nightlightComponent;
                    case "updates":
                        return updatesComponent;
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
            // Omarchy widget drop in without being compiled into pshell.
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
        id: aiUsageComponent
        AiUsage {}
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
        id: settingsComponent
        Settings {}
    }
    Component {
        id: notificationsComponent
        NotificationsWidget.Notifications {}
    }
    Component {
        id: weatherComponent
        WeatherWidget.Weather {}
    }
    Component {
        id: powerMenuComponent
        PowerMenuWidget.PowerMenu {}
    }
    Component {
        id: keybindsComponent
        KeybindsWidget.Keybinds {}
    }
    Component {
        id: nightlightComponent
        NightlightWidget.Nightlight {}
    }
    Component {
        id: updatesComponent
        UpdatesWidget.Updates {}
    }
    Component {
        id: procComponent
        ProcWidget {}
    }
}
