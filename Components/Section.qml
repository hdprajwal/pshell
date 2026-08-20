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

Row {
    id: root

    property var entries: []
    property var bar: null

    spacing: Config.gap
    height: Config.size

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

            // A widget that hides itself takes no slot, which is how Omarchy's
            // own bar sizes these: a plugin with nothing to report sets
            // visible false and expects the gap to close behind it.
            implicitWidth: activeItem && activeItem.visible ? activeItem.implicitWidth : 0
            implicitHeight: Config.size
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
                onLoaded: {
                    if (!item)
                        return;
                    item.cfg = slot.modelData;
                    if ("bar" in item)
                        item.bar = root.bar;
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
