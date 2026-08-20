import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Services

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

    spacing: 1

    Text {
        visible: root.enabled && rows.count === 0
        text: "Searching..."
        color: Config.fg
        opacity: 0.6
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
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

        Rectangle {
            id: devRow

            required property var modelData
            readonly property string label: modelData.deviceName || modelData.name || modelData.address

            width: root.rowWidth
            height: Math.round(Config.fontSize * 2.4)
            radius: 4
            color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: devRow.label
                color: Config.fg
                opacity: devRow.modelData.paired ? 1 : 0.7
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
                width: root.rowWidth - 90
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 6
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
                color: devRow.modelData.connected ? Config.accent : Config.fg
                opacity: devRow.modelData.connected ? 1 : 0.55
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 0.9)
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
