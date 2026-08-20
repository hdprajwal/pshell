import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Components
import qs.Services
import qs.Commons
import qs.Ui

// Wi-Fi networks, strongest first with the connected one pinned to the top.
// Shared by the network widget and the control centre.
Column {
    id: root

    property QtObject bar: null
    property Item anchorItem: null
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

    // Same rule DMS uses: ask only when the network is secured and we have
    // no saved secret. A saved network reconnects without a prompt.
    function needsPassword(network) {
        return !network.known && network.security !== WifiSecurityType.Open;
    }

    function secured(network) {
        return network.security !== WifiSecurityType.Open;
    }

    // The network we asked to join, held until it either connects or fails.
    property var pending: null
    property var failed: null
    property string failure: ""

    function join(network) {
        // NetworkManager drops the current connection to attempt a new one,
        // so a second click mid-attempt leaves you offline with two
        // half-finished activations. DMS guards this the same way.
        if (root.pending)
            return;

        root.failure = "";
        root.failed = null;
        root.pending = network;
        network.connect();
    }

    function joinWithPassword(network, password) {
        root.failure = "";
        root.failed = null;
        root.pending = network;
        network.connectWithPsk(password);
    }

    Connections {
        target: root.pending

        function onStateChanged() {
            const network = root.pending;
            if (!network)
                return;

            if (network.connected) {
                root.pending = null;
                root.failure = "";
                return;
            }

            if (network.state !== ConnectionState.Disconnected)
                return;

            // Back to disconnected without connecting means the attempt
            // failed, and NetworkManager has already torn down whatever you
            // were on.
            //
            // Deliberately no modal here. Whichever process is registered as
            // NetworkManager's secret agent has already prompted, so opening
            // one too puts two password dialogs on screen for one attempt.
            // Show the failure and let the user ask for the prompt.
            root.pending = null;
            root.failed = network;
            root.failure = "Could not connect to " + network.name;
        }
    }

    spacing: Style.spacing.xxs

    Column {
        width: root.rowWidth
        visible: root.failure !== ""
        spacing: Style.spacing.sm

        Text {
            width: root.rowWidth
            text: root.failure
            color: Color.urgent
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }

        Button {
            visible: root.failed !== null && root.secured(root.failed)
            text: "Enter password"
            onClicked: passwordPrompt.open(root.failed, root.failure)
        }
    }

    Text {
        visible: Networking.wifiEnabled && rows.count === 0
        text: "Scanning..."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
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

        BorderSurface {
            id: netRow

            required property var modelData
            readonly property bool hot: hover.containsMouse

            width: root.rowWidth
            height: Math.round(Style.font.body * 2.4)
            radius: Style.cornerRadius
            color: Style.controlFill(false, hot, Color.foreground, Color.accent)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.md

                BarIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSource: Icons.wifi(netRow.modelData.signalStrength)
                    size: Math.round(Style.font.body * 1.1)
                    color: Color.popups.text
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: netRow.modelData.name
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    width: root.rowWidth - 150
                    elide: Text.ElideRight
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (root.pending === netRow.modelData || netRow.modelData.state === ConnectionState.Connecting)
                        return "connecting";
                    if (netRow.modelData.connected)
                        return "connected";
                    return Math.round(netRow.modelData.signalStrength * 100) + "%";
                }
                color: netRow.modelData.connected ? Color.accent : Color.popups.text
                opacity: netRow.modelData.connected ? 1 : 0.6
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
                    if (mouse.button === Qt.RightButton) {
                        if (netRow.modelData.known)
                            netRow.modelData.forget();
                        return;
                    }
                    // Clicking the network you are already on does nothing.
                    // It used to disconnect, which made a mis-click drop your
                    // wifi. Use the Wi-Fi toggle to go offline.
                    if (netRow.modelData.connected)
                        return;

                    if (root.needsPassword(netRow.modelData)) {
                        passwordPrompt.open(netRow.modelData, "");
                        return;
                    }
                    root.join(netRow.modelData);
                }
            }
        }
    }

    PasswordPrompt {
        id: passwordPrompt
        bar: root.bar
        anchorItem: root.anchorItem
        onAccepted: password => {
            if (passwordPrompt.network)
                root.joinWithPassword(passwordPrompt.network, password);
        }
    }
}
