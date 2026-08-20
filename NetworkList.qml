import QtQuick
import Quickshell
import Quickshell.Networking

// Wi-Fi networks, strongest first with the connected one pinned to the top.
// Shared by the network widget and the control centre.
Column {
    id: root

    property int rowWidth: 260
    property int maxNetworks: 8

    readonly property var device: {
        const devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i];
        }
        return null;
    }

    function scan(on) {
        if (device)
            device.scannerEnabled = on;
    }

    spacing: 1

    Text {
        visible: Networking.wifiEnabled && rows.count === 0
        text: "Scanning..."
        color: Config.fg
        opacity: 0.6
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
    }

    Repeater {
        id: rows

        model: {
            if (!root.device || !Networking.wifiEnabled)
                return [];
            const nets = root.device.networks.values.slice();
            nets.sort((a, b) => {
                if (a.connected !== b.connected)
                    return a.connected ? -1 : 1;
                return b.signalStrength - a.signalStrength;
            });
            return nets.slice(0, root.maxNetworks);
        }

        Rectangle {
            id: netRow

            required property var modelData

            width: root.rowWidth
            height: Math.round(Config.fontSize * 2.4)
            radius: 4
            color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                BarIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSource: Icons.wifi(netRow.modelData.signalStrength)
                    size: Math.round(Config.fontSize * 1.1)
                    opacity: 0.8
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: netRow.modelData.name
                    color: Config.fg
                    font.family: Config.fontFamily
                    font.pixelSize: Config.fontSize
                    width: root.rowWidth - 150
                    elide: Text.ElideRight
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (netRow.modelData.state === ConnectionState.Connecting)
                        return "...";
                    if (netRow.modelData.connected)
                        return "connected";
                    return Math.round(netRow.modelData.signalStrength * 100) + "%";
                }
                color: netRow.modelData.connected ? Config.accent : Config.fg
                opacity: netRow.modelData.connected ? 1 : 0.6
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
                    if (mouse.button === Qt.RightButton) {
                        if (netRow.modelData.known)
                            netRow.modelData.forget();
                        return;
                    }
                    if (netRow.modelData.connected)
                        netRow.modelData.disconnect();
                    else
                        netRow.modelData.connect();
                }
            }
        }
    }
}
