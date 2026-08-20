import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Services
import qs.Commons
import qs.Ui

// Wi-Fi + wired status in the bar with a network list panel. Shaped the way
// Calendar is: a qs.Ui.Panel owns open/close/IPC, a BarIconButton paints the
// bar slot, and a KeyboardPanel is the popup surface.
Panel {
    id: root
    moduleName: "qsbar.network"
    ipcTarget: "qsbar.network"

    property var cfg: ({})

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
    readonly property string iconSource: {
        if (wiredUp)
            return Icons.wired(true);
        if (!Networking.wifiEnabled)
            return Icons.wifiOff();
        if (activeWifi)
            return Icons.wifi(activeWifi.signalStrength);
        return Icons.wifi(0);
    }

    readonly property bool showName: cfg.showName === true && activeWifi !== null

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // Scanning costs power, so it only runs while the panel is open.
    onOpenedChanged: networkList.scan(root.opened)

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // No wired link and no connected wifi is the one state actually
        // worth flagging; a radio the user turned off on purpose is not.
        active: Networking.wifiEnabled && !root.wiredUp && !root.activeWifi

        iconSource: root.iconSource
        label: root.showName && root.activeWifi ? root.activeWifi.name : ""

        onPressed: b => {
            if (b === Qt.RightButton) {
                Networking.wifiEnabled = !Networking.wifiEnabled;
                return;
            }
            root.toggle();
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(280))
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                Row {
                    spacing: Style.spacing.lg

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wi-Fi"
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.subtitle
                    }

                    ToggleSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Networking.wifiEnabled
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                }

                Text {
                    visible: root.wiredUp
                    text: "Wired connected"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                NetworkList {
                    id: networkList
                    bar: root.bar
                    anchorItem: button
                    maxNetworks: root.cfg.maxNetworks || 8
                }

                Text {
                    visible: networkList.children.length > 0
                    text: "Right click a network to forget it"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }
}
