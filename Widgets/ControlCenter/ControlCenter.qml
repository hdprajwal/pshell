import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.Components
import qs.Services
import qs.Widgets.Bluetooth
import qs.Widgets.Network
import qs.Commons
import qs.Ui

// One panel for the things you actually reach for: volume, brightness, wifi,
// bluetooth, audio devices and the session buttons.
Panel {
    id: root
    moduleName: "qsbar.controlcenter"
    ipcTarget: "qsbar.controlcenter"

    property var cfg: ({})

    readonly property int panelWidth: cfg.width || Style.space(380)
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
    readonly property var iconSources: {
        const list = [];
        list.push(wifiOn ? Icons.wifi(activeWifi ? activeWifi.signalStrength : 0) : Icons.wifiOff());
        if (btConnected.length > 0)
            list.push(Icons.bluetooth(true, true));
        list.push(Icons.first(Audio.muted ? ["audio-volume-muted-symbolic", "audio-volume-muted"] : ["audio-volume-high-symbolic", "audio-volume-high"]));
        return list;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    property string uptime: ""

    onOpenedChanged: {
        if (opened) {
            uptimeProc.running = true;
        } else {
            detail = "";
            netList.scan(false);
            btList.discover(false);
        }
    }

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

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        slotSize: Style.bar.iconCanvas * root.iconSources.length + Style.spacing.sm * Math.max(0, root.iconSources.length - 1) + Style.spacing.lg * 2

        iconComponent: Component {
            Row {
                anchors.centerIn: parent
                spacing: Style.spacing.sm

                Repeater {
                    model: root.iconSources

                    BarIcon {
                        required property string modelData

                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: modelData
                        size: Style.bar.iconCanvas
                        color: button.foreground
                    }
                }
            }
        }

        onPressed: b => {
            if (b === Qt.RightButton) {
                Audio.toggleMute();
                return;
            }
            root.toggle();
        }

        onWheelMoved: delta => Audio.setVolume(Audio.volume + (delta > 0 ? 0.05 : -0.05))
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(root.panelWidth + panel.horizontalContentInset)
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

                // ---------- User header: avatar, name/uptime, session actions ----------
                PanelHero {
                    width: parent.width
                    foreground: Color.popups.text

                    iconComponent: Component {
                        BorderSurface {
                            width: Math.round(Style.font.body * 3)
                            height: width
                            radius: width / 2
                            color: Style.normalFillFor(Color.popups.text, Color.accent)
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
                                color: Color.popups.text
                                font.family: Style.font.family
                                font.pixelSize: Style.font.title
                            }
                        }
                    }

                    title: root.cfg.name || Quickshell.env("USER") || ""
                    meta: root.uptime

                    trailingControl: Component {
                        Row {
                            spacing: Style.spacing.sm

                            Repeater {
                                model: [
                                    {
                                        icon: "󰌾",
                                        cmd: root.cfg.lock || "loginctl lock-session",
                                        tip: "Lock"
                                    },
                                    {
                                        icon: "󰐥",
                                        cmd: root.cfg.power || "systemctl poweroff",
                                        tip: "Power off"
                                    },
                                    {
                                        icon: "󰍃",
                                        cmd: root.cfg.logout || "loginctl terminate-user $USER",
                                        tip: "Log out"
                                    }
                                ]

                                PanelActionButton {
                                    required property var modelData

                                    foreground: Color.popups.text
                                    iconText: modelData.icon
                                    tooltipText: modelData.tip
                                    onClicked: {
                                        root.run(modelData.cmd);
                                        root.close();
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------- Volume ----------
                Item {
                    width: parent.width
                    height: volumeSlider.implicitHeight

                    BarIcon {
                        id: volumeIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: Icons.first(Audio.muted ? ["audio-volume-muted-symbolic", "audio-volume-muted"] : ["audio-volume-high-symbolic", "audio-volume-high"])
                        size: Math.round(Style.font.body * 1.4)
                        opacity: Audio.muted ? 0.45 : 1
                    }

                    PanelSlider {
                        id: volumeSlider
                        bar: root.bar
                        anchors.left: volumeIcon.right
                        anchors.leftMargin: Style.spacing.lg
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        minimum: 0
                        maximum: 1
                        step: 0.05
                        value: Audio.volume
                        opacity: Audio.muted ? 0.45 : 1
                        onMoved: v => Audio.setVolume(v)
                        onRightClicked: Audio.toggleMute()
                    }
                }

                // ---------- Brightness ----------
                Item {
                    width: parent.width
                    visible: Brightness.available
                    height: visible ? brightnessSlider.implicitHeight : 0

                    BarIcon {
                        id: brightnessIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: Icons.first(["display-brightness-symbolic", "brightness-high-symbolic", "video-display"])
                        size: Math.round(Style.font.body * 1.4)
                    }

                    PanelSlider {
                        id: brightnessSlider
                        bar: root.bar
                        anchors.left: brightnessIcon.right
                        anchors.leftMargin: Style.spacing.lg
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        minimum: 0
                        maximum: 1
                        step: 0.05
                        value: Brightness.fraction
                        onMoved: v => Brightness.setFraction(v)
                    }
                }

                // ---------- Wifi / bluetooth / output / input tiles ----------
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: Style.spacing.lg
                    rowSpacing: Style.spacing.lg

                    readonly property int cellWidth: (width - columnSpacing) / 2

                    ControlTile {
                        width: parent.cellWidth
                        iconSource: root.wifiOn ? Icons.wifi(root.activeWifi ? root.activeWifi.signalStrength : 0) : Icons.wifiOff()
                        title: root.wifiOn ? (root.activeWifi ? root.activeWifi.name : "Not connected") : "Wi-Fi"
                        subtitle: root.wifiOn ? (root.activeWifi ? Math.round(root.activeWifi.signalStrength * 100) + "%" : "On") : "Off"
                        active: root.wifiOn
                        expanded: root.detail === "wifi"
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                        onDetailRequested: root.showDetail("wifi")
                    }

                    ControlTile {
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

                    ControlTile {
                        width: parent.cellWidth
                        iconSource: Icons.first(Audio.muted ? ["audio-volume-muted-symbolic"] : ["audio-volume-high-symbolic", "audio-speakers-symbolic"])
                        title: Audio.sinkName
                        subtitle: Math.round(Audio.volume * 100) + "%"
                        active: !Audio.muted
                        expanded: root.detail === "sink"
                        onToggled: Audio.toggleMute()
                        onDetailRequested: root.showDetail("sink")
                    }

                    ControlTile {
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
                    height: visible ? Math.min(Style.space(320), detailColumn.implicitHeight + Style.spacing.xxl) : 0
                    radius: Style.cornerRadius
                    color: Style.normalFill

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Style.spacing.lg
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
                                bar: root.bar
                                rowWidth: detailColumn.width
                                settingsCommand: root.cfg.audioSettings || ""
                                onRunRequested: command => {
                                    root.run(command);
                                    root.close();
                                }
                            }

                            AudioDeviceList {
                                id: sourceList
                                visible: root.detail === "source"
                                input: true
                                bar: root.bar
                                rowWidth: detailColumn.width
                                settingsCommand: root.cfg.audioSettings || ""
                                onRunRequested: command => {
                                    root.run(command);
                                    root.close();
                                }
                            }
                        }
                    }
                }

                // Shell-command toggles. Night mode has no standard tool, so it
                // is whatever the user configures rather than a guess.
                Row {
                    width: parent.width
                    spacing: Style.spacing.lg
                    visible: root.cfg.nightMode !== undefined || root.cfg.darkMode !== false

                    readonly property bool hasNight: root.cfg.nightMode !== undefined
                    readonly property int cellWidth: hasNight ? (width - spacing) / 2 : width

                    ControlTile {
                        width: parent.cellWidth
                        visible: parent.hasNight
                        iconSource: Icons.first(["night-light-symbolic", "weather-clear-night-symbolic", "weather-clear-night"])
                        title: "Night Mode"
                        hasDetail: false
                        onToggled: root.run(String(root.cfg.nightMode))
                    }

                    ControlTile {
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

    // ---- Reusable inline component ----

    // A control centre tile. The icon square toggles the thing on and off; the
    // rest of the tile opens its detail list, which is how DMS splits it too.
    // One tile, two targets, so a mis-click never toggles your wifi off when
    // you meant to pick a network.
    component ControlTile: BorderSurface {
        id: tile

        property string iconSource: ""
        property string title: ""
        property string subtitle: ""
        property bool active: false
        property bool expanded: false
        property bool hasDetail: true

        signal toggled
        signal detailRequested

        readonly property bool hot: bodyHover.containsMouse

        implicitHeight: Math.round(Style.font.body * 4.2)
        radius: Style.cornerRadius
        color: Style.controlFill(false, tile.expanded || tile.hot, Color.popups.text, Color.accent)
        borderSpec: Border.controlSpec(tile.expanded ? "selected" : (tile.hot ? "hover-cursor" : "normal"), Color.popups.text, Color.accent)

        Behavior on color {
            ColorAnimation {
                duration: 100
            }
        }

        MouseArea {
            id: bodyHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: tile.hasDetail
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.detailRequested()
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: tile.borderLeft + Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: tile.borderRight + Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            BorderSurface {
                id: iconBox
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(Style.font.body * 2.8)
                height: width
                radius: Style.cornerRadius
                color: tile.active ? Style.selectedStateColor(Color.popups.text, Color.accent) : (iconHover.containsMouse ? Style.selectedFillFor(Color.popups.text, Color.accent) : Style.hoverFillFor(Color.popups.text, Color.accent))
                borderSpec: Border.none()

                BarIcon {
                    anchors.centerIn: parent
                    iconSource: tile.iconSource
                    size: Math.round(Style.font.body * 1.4)
                    color: tile.active ? Color.background : Color.popups.text
                }

                MouseArea {
                    id: iconHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.toggled()
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - iconBox.width - parent.spacing
                spacing: Style.spacing.xxs

                Text {
                    width: parent.width
                    text: tile.title
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: tile.subtitle !== ""
                    text: tile.subtitle
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }
            }
        }
    }
}
