import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Services
import qs.Commons
import qs.Ui

// Connected devices first, then paired, then anything else in range, so the
// list is not dominated by passing strangers.
Column {
    id: root

    property int rowWidth: 260
    property int maxDevices: 8

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter && adapter.enabled

    function discover(on) {
        if (adapter && root.enabled)
            adapter.discovering = on;
    }

    spacing: Style.spacing.xxs

    Text {
        visible: root.enabled && rows.count === 0
        text: "Searching..."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }

    Repeater {
        id: rows

        model: {
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
            return all.slice(0, root.maxDevices);
        }

        BorderSurface {
            id: devRow

            required property var modelData
            readonly property string label: modelData.deviceName || modelData.name || modelData.address
            readonly property bool hot: hover.containsMouse

            width: root.rowWidth
            height: Math.round(Style.font.body * 2.4)
            radius: Style.cornerRadius
            color: Style.controlFill(false, hot, Color.foreground, Color.accent)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: devRow.label
                color: Color.popups.text
                opacity: devRow.modelData.paired ? 1 : 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                width: root.rowWidth - 90
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (devRow.modelData.pairing)
                        return "pairing";
                    if (devRow.modelData.state === BluetoothDeviceState.Connecting)
                        return "...";
                    if (devRow.modelData.connected)
                        return devRow.modelData.batteryAvailable ? Math.round(devRow.modelData.battery * 100) + "%" : "connected";
                    return devRow.modelData.paired ? "paired" : "";
                }
                color: devRow.modelData.connected ? Color.accent : Color.popups.text
                opacity: devRow.modelData.connected ? 1 : 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    const device = devRow.modelData;
                    if (mouse.button === Qt.RightButton) {
                        if (device.paired)
                            device.forget();
                        return;
                    }
                    if (device.connected)
                        device.disconnect();
                    else if (device.paired)
                        device.connect();
                    else
                        device.pair();
                }
            }
        }
    }
}
