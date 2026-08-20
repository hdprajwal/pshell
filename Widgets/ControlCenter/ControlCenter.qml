import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.Components
import qs.Services
import qs.Widgets.Bluetooth
import qs.Widgets.Network

// One panel for the things you actually reach for: volume, brightness, wifi,
// bluetooth, audio devices and the session buttons.
BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property int panelWidth: cfg.width || 380
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool btOn: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled

    readonly property var activeWifi: {
        const devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type !== DeviceType.Wifi)
                continue;
            const nets = devices[i].networks.values;
            for (var j = 0; j < nets.length; j++) {
                if (nets[j].connected)
                    return nets[j];
            }
        }
        return null;
    }

    readonly property var btConnected: btOn ? Bluetooth.devices.values.filter(d => d.connected) : []

    // Which tile's detail list is showing, "" for none.
    property string detail: ""

    function showDetail(name) {
        detail = detail === name ? "" : name;
        netList.scan(detail === "wifi");
        btList.discover(detail === "bluetooth");
    }

    // Reports the things people glance at the bar for. Bluetooth only earns
    // its place when something is actually connected, otherwise it is a
    // permanent reminder of a radio nobody is using.
    iconSources: {
        const list = [];
        list.push(wifiOn ? Icons.wifi(activeWifi ? activeWifi.signalStrength : 0) : Icons.wifiOff());
        if (btConnected.length > 0)
            list.push(Icons.bluetooth(true, true));
        list.push(Icons.first(Audio.muted ? ["audio-volume-muted-symbolic", "audio-volume-muted"] : ["audio-volume-high-symbolic", "audio-volume-high"]));
        return list;
    }
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button === Qt.RightButton) {
            Audio.toggleMute();
            return;
        }
        panel.toggle(root);
    }

    onWheel: delta => Audio.setVolume(Audio.volume + (delta > 0 ? 0.05 : -0.05))

    Process {
        id: runner
    }

    function run(command) {
        runner.command = ["sh", "-c", command];
        runner.running = false;
        runner.running = true;
    }

    Process {
        id: uptimeProc
        command: ["uptime", "-p"]
        stdout: StdioCollector {
            onStreamFinished: root.uptime = String(text || "").trim()
        }
    }

    property string uptime: ""

    Popout {
        id: panel
        bar: root.bar

        onDismissed: {
            root.detail = "";
            netList.scan(false);
            btList.discover(false);
        }

        onOpenedChanged: if (opened)
            uptimeProc.running = true

        Column {
            width: root.panelWidth
            spacing: 12

            // Session header
            Rectangle {
                width: parent.width
                height: Math.round(Config.fontSize * 4.4)
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.05)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(Config.fontSize * 3)
                        height: width
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.cfg.avatar ? "file://" + String(root.cfg.avatar).replace("~", Quickshell.env("HOME")) : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !root.cfg.avatar
                            text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                            color: Config.fg
                            font.family: Config.fontFamily
                            font.pixelSize: Math.round(Config.fontSize * 1.4)
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: root.cfg.name || Quickshell.env("USER") || ""
                            color: Config.fg
                            font.family: Config.fontFamily
                            font.pixelSize: Math.round(Config.fontSize * 1.2)
                        }

                        Text {
                            text: root.uptime
                            color: Config.fg
                            opacity: 0.55
                            font.family: Config.fontFamily
                            font.pixelSize: Math.round(Config.fontSize * 0.85)
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: [
                            {
                                icon: ["system-lock-screen-symbolic", "system-lock-screen"],
                                cmd: root.cfg.lock || "loginctl lock-session"
                            },
                            {
                                icon: ["system-shutdown-symbolic", "system-shutdown"],
                                cmd: root.cfg.power || "systemctl poweroff"
                            },
                            {
                                icon: ["system-log-out-symbolic", "system-log-out"],
                                cmd: root.cfg.logout || "loginctl terminate-user $USER"
                            }
                        ]

                        Rectangle {
                            required property var modelData

                            width: Math.round(Config.fontSize * 2.4)
                            height: width
                            radius: 6
                            color: btnHover.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                            BarIcon {
                                anchors.centerIn: parent
                                iconSource: Icons.first(parent.modelData.icon)
                                size: Math.round(Config.fontSize * 1.2)
                            }

                            MouseArea {
                                id: btnHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.run(parent.modelData.cmd);
                                    panel.close();
                                }
                            }
                        }
                    }
                }
            }

            Slider {
                width: parent.width
                value: Audio.volume
                dimmed: Audio.muted
                iconSource: Icons.first(Audio.muted ? ["audio-volume-muted-symbolic", "audio-volume-muted"] : ["audio-volume-high-symbolic", "audio-volume-high"])
                onMoved: v => Audio.setVolume(v)
            }

            Slider {
                width: parent.width
                visible: Brightness.available
                value: Brightness.fraction
                iconSource: Icons.first(["display-brightness-symbolic", "brightness-high-symbolic", "video-display"])
                onMoved: v => Brightness.setFraction(v)
            }

            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                readonly property int cellWidth: (width - columnSpacing) / 2

                Tile {
                    width: parent.cellWidth
                    iconSource: root.wifiOn ? Icons.wifi(root.activeWifi ? root.activeWifi.signalStrength : 0) : Icons.wifiOff()
                    title: root.wifiOn ? (root.activeWifi ? root.activeWifi.name : "Not connected") : "Wi-Fi"
                    subtitle: root.wifiOn ? (root.activeWifi ? Math.round(root.activeWifi.signalStrength * 100) + "%" : "On") : "Off"
                    active: root.wifiOn
                    expanded: root.detail === "wifi"
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    onDetailRequested: root.showDetail("wifi")
                }

                Tile {
                    width: parent.cellWidth
                    iconSource: Icons.bluetooth(root.btOn, root.btConnected.length > 0)
                    title: root.btOn ? (root.btConnected.length > 0 ? root.btConnected[0].deviceName || root.btConnected[0].name : "Bluetooth") : "Disabled"
                    subtitle: root.btOn ? (root.btConnected.length > 0 ? "Connected" : "On") : "Off"
                    active: root.btOn
                    expanded: root.detail === "bluetooth"
                    onToggled: if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                    onDetailRequested: root.showDetail("bluetooth")
                }

                Tile {
                    width: parent.cellWidth
                    iconSource: Icons.first(Audio.muted ? ["audio-volume-muted-symbolic"] : ["audio-volume-high-symbolic", "audio-speakers-symbolic"])
                    title: Audio.sinkName
                    subtitle: Math.round(Audio.volume * 100) + "%"
                    active: !Audio.muted
                    expanded: root.detail === "sink"
                    onToggled: Audio.toggleMute()
                    onDetailRequested: root.showDetail("sink")
                }

                Tile {
                    width: parent.cellWidth
                    iconSource: Icons.microphone(Audio.micMuted)
                    title: Audio.sourceName
                    subtitle: Math.round(Audio.micVolume * 100) + "%"
                    active: !Audio.micMuted
                    expanded: root.detail === "source"
                    onToggled: Audio.toggleMicMute()
                    onDetailRequested: root.showDetail("source")
                }
            }

            // Detail list for whichever tile is open.
            Rectangle {
                width: parent.width
                visible: root.detail !== ""
                height: visible ? Math.min(320, detailColumn.implicitHeight + 12) : 0
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.05)

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 6
                    contentWidth: width
                    contentHeight: detailColumn.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        id: detailColumn
                        width: parent.width
                        implicitHeight: netList.visible ? netList.implicitHeight : (btList.visible ? btList.implicitHeight : (sinkList.visible ? sinkList.implicitHeight : sourceList.implicitHeight))

                        NetworkList {
                            id: netList
                            visible: root.detail === "wifi"
                            rowWidth: detailColumn.width
                        }

                        BluetoothList {
                            id: btList
                            visible: root.detail === "bluetooth"
                            rowWidth: detailColumn.width
                        }

                        AudioDeviceList {
                            id: sinkList
                            visible: root.detail === "sink"
                            rowWidth: detailColumn.width
                            settingsCommand: root.cfg.audioSettings || ""
                            onRunRequested: command => {
                                root.run(command);
                                panel.close();
                            }
                        }

                        AudioDeviceList {
                            id: sourceList
                            visible: root.detail === "source"
                            input: true
                            rowWidth: detailColumn.width
                            settingsCommand: root.cfg.audioSettings || ""
                            onRunRequested: command => {
                                root.run(command);
                                panel.close();
                            }
                        }
                    }
                }
            }

            // Shell-command toggles. Night mode has no standard tool, so it
            // is whatever the user configures rather than a guess.
            Row {
                width: parent.width
                spacing: 8
                visible: root.cfg.nightMode !== undefined || root.cfg.darkMode !== false

                readonly property bool hasNight: root.cfg.nightMode !== undefined
                readonly property int cellWidth: hasNight ? (width - spacing) / 2 : width

                Tile {
                    width: parent.cellWidth
                    visible: parent.hasNight
                    iconSource: Icons.first(["night-light-symbolic", "weather-clear-night-symbolic", "weather-clear-night"])
                    title: "Night Mode"
                    hasDetail: false
                    onToggled: root.run(String(root.cfg.nightMode))
                }

                Tile {
                    width: parent.cellWidth
                    visible: root.cfg.darkMode !== false
                    iconSource: Icons.first(["dark-mode-symbolic", "weather-clear-night-symbolic", "preferences-desktop-theme"])
                    title: "Dark Mode"
                    hasDetail: false
                    onToggled: root.run(root.cfg.darkModeCommand || "gsettings set org.gnome.desktop.interface color-scheme \"$(test \"$(gsettings get org.gnome.desktop.interface color-scheme)\" = \"'prefer-dark'\" && echo prefer-light || echo prefer-dark)\"")
                }
            }
        }
    }
}
