import QtQuick
import Quickshell

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
                if (modelData.type === "clock" || modelData.type === "calendar" || modelData.type === "workspaces" || modelData.type === "tray" || modelData.type === "battery" || modelData.type === "network" || modelData.type === "bluetooth" || modelData.type === "controlCenter")
                    return modelData.type;
                if (WidgetRegistry.has(widgetId))
                    return "qml";
                return "proc";
            }
            readonly property var activeItem: builtinLoader.item || qmlLoader.item

            implicitWidth: activeItem ? activeItem.implicitWidth : 0
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
