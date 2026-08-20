import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Components
import qs.Services
import qs.Commons

BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter && adapter.enabled

    readonly property var connectedDevices: {
        if (!root.enabled)
            return [];
        return Bluetooth.devices.values.filter(d => d.connected);
    }

    // Paired devices first, then anything else in range, so the list is not
    // dominated by passing strangers.
    readonly property var listed: {
        if (!root.enabled)
            return [];
        const all = Bluetooth.devices.values.slice();
        all.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1;
            return String(a.deviceName || a.name).localeCompare(String(b.deviceName || b.name));
        });
        return all.slice(0, cfg.maxDevices || 8);
    }

    shown: adapter !== null
    iconSource: Icons.bluetooth(enabled, connectedDevices.length > 0)
    text: cfg.showCount === true && connectedDevices.length > 0 ? String(connectedDevices.length) : ""
    // Derived from the coordinator rather than this panel's own flag, so
    // exactly one widget can ever look active.
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button === Qt.RightButton) {
            if (root.adapter)
                root.adapter.enabled = !root.adapter.enabled;
            return;
        }
        panel.toggle(root);
        deviceList.discover(panel.opened);
    }

    Popout {
        id: panel
        bar: root.bar

        onDismissed: deviceList.discover(false)

        Column {
            spacing: 8

            Row {
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Bluetooth"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 1.2)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Style.font.body * 2.6)
                    height: Math.round(Style.font.body * 1.4)
                    radius: height / 2
                    color: root.enabled ? Color.accent : Util.alpha(Color.foreground, 0.18)

                    Rectangle {
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        color: Color.background
                        y: 2
                        x: root.enabled ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.adapter)
                            root.adapter.enabled = !root.adapter.enabled
                    }
                }
            }

            BluetoothList {
                id: deviceList
                maxDevices: root.cfg.maxDevices || 8
            }

            Text {
                visible: deviceList.children.length > 0
                text: "Right click a device to forget it"
                color: Color.foreground
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.85)
            }
        }
    }
}
