import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Components
import qs.Services
import qs.Commons

BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i];
        }
        return null;
    }

    readonly property var wiredDevice: {
        const devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wired)
                return devices[i];
        }
        return null;
    }

    readonly property bool wiredUp: wiredDevice && wiredDevice.connected

    readonly property var activeWifi: {
        if (!wifiDevice)
            return null;
        const nets = wifiDevice.networks.values;
        for (var i = 0; i < nets.length; i++) {
            if (nets[i].connected)
                return nets[i];
        }
        return null;
    }

    // Wired wins when it is up: it is the connection actually carrying
    // traffic, so showing wifi strength there would be misleading.
    iconSource: {
        if (wiredUp)
            return Icons.wired(true);
        if (!Networking.wifiEnabled)
            return Icons.wifiOff();
        if (activeWifi)
            return Icons.wifi(activeWifi.signalStrength);
        return Icons.wifi(0);
    }

    text: cfg.showName === true && activeWifi ? activeWifi.name : ""
    // Derived from the coordinator rather than this panel's own flag, so
    // exactly one widget can ever look active.
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button === Qt.RightButton) {
            Networking.wifiEnabled = !Networking.wifiEnabled;
            return;
        }
        panel.toggle(root);
        networkList.scan(panel.opened);
    }

    Popout {
        id: panel
        bar: root.bar

        // Scanning costs power, so it only runs while the panel is open.
        onDismissed: networkList.scan(false)

        Column {
            spacing: 8

            Row {
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 1.2)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Style.font.body * 2.6)
                    height: Math.round(Style.font.body * 1.4)
                    radius: height / 2
                    color: Networking.wifiEnabled ? Color.accent : Util.alpha(Color.foreground, 0.18)

                    Rectangle {
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        color: Color.background
                        y: 2
                        x: Networking.wifiEnabled ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                }
            }

            Text {
                visible: root.wiredUp
                text: "Wired connected"
                color: Color.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            NetworkList {
                id: networkList
                maxNetworks: root.cfg.maxNetworks || 8
            }

            Text {
                visible: networkList.children.length > 0
                text: "Right click a network to forget it"
                color: Color.foreground
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.85)
            }
        }
    }
}
