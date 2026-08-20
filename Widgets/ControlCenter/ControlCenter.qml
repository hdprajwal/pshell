import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
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
    // Which row of tiles owns the open list: the top pair or the bottom one.
    readonly property int detailRow: detail === "sink" || detail === "source" ? 1 : 0
    readonly property int detailHeight: detail === "" ? 0 : Math.min(Style.space(320), detailColumn.implicitHeight + Style.spacing.xxl)

    function showDetail(name) {
        detail = detail === name ? "" : name;
        netList.scan(detail === "wifi");
        btList.discover(detail === "bluetooth");
    }

    // Reports the things people glance at the bar for. Bluetooth only earns
    // its place when something is actually connected, otherwise it is a
    // permanent reminder of a radio nobody is using.
    readonly property var iconNames: {
        const list = [];
        list.push(Glyphs.wifi(wifiOn, activeWifi !== null, activeWifi ? activeWifi.signalStrength : 0));
        if (btConnected.length > 0)
            list.push(Glyphs.bluetooth(true, true));
        list.push(Glyphs.volume(Audio.muted, Audio.volume));
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
        // Padded the same as a single-icon slot, so a widget carrying
        // three icons sits the same distance from its neighbour as one
        // carrying one.
        iconNames: root.iconNames

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
                                        icon: Glyphs.lock,
                                        cmd: root.cfg.lock || "loginctl lock-session",
                                        tip: "Lock"
                                    },
                                    {
                                        icon: Glyphs.powerOff,
                                        cmd: root.cfg.power || "systemctl poweroff",
                                        tip: "Power off"
                                    },
                                    {
                                        icon: Glyphs.logout,
                                        cmd: root.cfg.logout || "loginctl terminate-user $USER",
                                        tip: "Log out"
                                    }
                                ]

                                // The glyph is a child rather than `iconText`
                                // because that draws in the button's own font,
                                // which is also the tooltip's.
                                PanelActionButton {
                                    required property var modelData

                                    foreground: Color.popups.text
                                    tooltipText: modelData.tip
                                    onClicked: {
                                        root.run(modelData.cmd);
                                        root.close();
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: modelData.icon
                                        size: Style.font.icon
                                        color: Color.popups.text
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

                    MaterialIcon {
                        id: volumeIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.volume(Audio.muted, Audio.volume)
                        size: Math.round(Style.font.body * 1.4)
                        color: Color.popups.text
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

                    MaterialIcon {
                        id: brightnessIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.brightness(Brightness.fraction)
                        size: Math.round(Style.font.body * 1.4)
                        color: Color.popups.text
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
                //
                // Two rows of two, with the open list dropping in under the row
                // that owns it rather than below all four. A list that appears
                // three tiles away from the one you clicked does not read as
                // belonging to it.
                Column {
                    width: parent.width
                    spacing: Style.spacing.lg

                    readonly property int cellWidth: (width - Style.spacing.lg) / 2

                    Row {
                        width: parent.width
                        spacing: Style.spacing.lg

                        ControlTile {
                            width: parent.parent.cellWidth
                            iconName: Glyphs.wifi(root.wifiOn, root.activeWifi !== null, root.activeWifi ? root.activeWifi.signalStrength : 0)
                            title: root.wifiOn ? (root.activeWifi ? root.activeWifi.name : "Not connected") : "Wi-Fi"
                            subtitle: root.wifiOn ? (root.activeWifi ? Math.round(root.activeWifi.signalStrength * 100) + "%" : "On") : "Off"
                            active: root.wifiOn
                            expanded: root.detail === "wifi"
                            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                            onDetailRequested: root.showDetail("wifi")
                        }

                        ControlTile {
                            width: parent.parent.cellWidth
                            iconName: Glyphs.bluetooth(root.btOn, root.btConnected.length > 0)
                            title: root.btOn ? (root.btConnected.length > 0 ? root.btConnected[0].deviceName || root.btConnected[0].name : "Bluetooth") : "Disabled"
                            subtitle: root.btOn ? (root.btConnected.length > 0 ? "Connected" : "On") : "Off"
                            active: root.btOn
                            expanded: root.detail === "bluetooth"
                            onToggled: if (Bluetooth.defaultAdapter)
                                Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                            onDetailRequested: root.showDetail("bluetooth")
                        }
                    }

                    // Where the list goes when the row above owns it. The list
                    // itself is built once and moves between these, so opening
                    // one does not tear down the scan running in another.
                    Item {
                        id: topSlot
                        width: parent.width
                        height: root.detailRow === 0 ? root.detailHeight : 0
                        visible: height > 0
                    }

                    Row {
                        width: parent.width
                        spacing: Style.spacing.lg

                        ControlTile {
                            width: parent.parent.cellWidth
                            iconName: Glyphs.volume(Audio.muted, Audio.volume)
                            title: Audio.sinkName
                            subtitle: Math.round(Audio.volume * 100) + "%"
                            active: !Audio.muted
                            expanded: root.detail === "sink"
                            onToggled: Audio.toggleMute()
                            onDetailRequested: root.showDetail("sink")
                        }

                        ControlTile {
                            width: parent.parent.cellWidth
                            iconName: Glyphs.microphone(Audio.micMuted)
                            title: Audio.sourceName
                            subtitle: Math.round(Audio.micVolume * 100) + "%"
                            active: !Audio.micMuted
                            expanded: root.detail === "source"
                            onToggled: Audio.toggleMicMute()
                            onDetailRequested: root.showDetail("source")
                        }
                    }

                    Item {
                        id: bottomSlot
                        width: parent.width
                        height: root.detailRow === 1 ? root.detailHeight : 0
                        visible: height > 0
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
                        iconName: Glyphs.nightMode
                        title: "Night Mode"
                        hasDetail: false
                        onToggled: root.run(String(root.cfg.nightMode))
                    }

                    ControlTile {
                        width: parent.cellWidth
                        visible: root.cfg.darkMode !== false
                        iconName: Glyphs.darkMode
                        title: "Dark Mode"
                        hasDetail: false
                        // Lit from the setting the default command writes. A
                        // custom darkModeCommand that writes somewhere else
                        // leaves the tile dark, which is honest: the state is
                        // then something qsbar cannot see.
                        active: SystemTheme.available && SystemTheme.scheme === "dark"
                        onToggled: root.run(root.cfg.darkModeCommand || "gsettings set org.gnome.desktop.interface color-scheme \"$(test \"$(gsettings get org.gnome.desktop.interface color-scheme)\" = \"'prefer-dark'\" && echo prefer-light || echo prefer-dark)\"")
                    }
                }
            }
        }
    }

    // The open list. One instance, reparented into the slot under whichever
    // row owns it, so switching tiles moves the panel rather than rebuilding
    // it and restarting whatever scan is running inside.
    Rectangle {
        parent: root.detailRow === 1 ? bottomSlot : topSlot
        anchors.fill: parent
        visible: root.detail !== ""
        radius: Style.cornerRadius
        color: Style.normalFill
        clip: true

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

    // ---- Reusable inline component ----

    // A control centre tile. The icon square toggles the thing on and off; the
    // rest of the tile opens its detail list, which is how DMS splits it too.
    // One tile, two targets, so a mis-click never toggles your wifi off when
    // you meant to pick a network. A tile with no detail list has nothing to
    // split, so the whole surface toggles instead of just the icon.
    component ControlTile: BorderSurface {
        id: tile

        property string iconName: ""
        property string title: ""
        property string subtitle: ""
        property bool active: false
        property bool expanded: false
        property bool hasDetail: true

        signal toggled
        signal detailRequested

        readonly property bool hot: bodyHover.containsMouse || (!tile.hasDetail && iconHover.containsMouse)

        // A tile with no detail list is one button, so the whole surface shows
        // the state that the icon square shows on the tiles that are two.
        // Nesting a lit square inside a lit tile would only say it twice.
        readonly property bool solid: tile.active && !tile.hasDetail
        readonly property color onColor: Style.selectedStateColor(Color.popups.text, Color.accent)
        readonly property color ink: tile.solid ? Color.popups.background : Color.popups.text

        implicitHeight: Math.round(Style.font.body * 4.2)
        radius: Style.cornerRadius
        // Fill alone, no outline. A tile is a filled surface rather than a
        // form control, and four outlined boxes stacked two deep turn the
        // panel into a grid of frames instead of a row of things to press.
        //
        // Hovering a lit tile thins its fill towards the panel rather than
        // darkening it, which reads the same way whether the palette is light
        // or dark.
        color: tile.solid ? Util.alpha(tile.onColor, tile.hot ? 0.86 : 1.0) : (tile.expanded ? Style.selectedFill : (tile.hot ? Style.hoverFill : Style.normalFill))
        borderSpec: Border.none()

        Behavior on color {
            ColorAnimation {
                duration: 100
            }
        }

        MouseArea {
            id: bodyHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.hasDetail ? tile.detailRequested() : tile.toggled()
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
                color: tile.solid ? "transparent" : (tile.active ? tile.onColor : (iconHover.containsMouse ? Style.selectedFillFor(Color.popups.text, Color.accent) : Style.hoverFillFor(Color.popups.text, Color.accent)))
                borderSpec: Border.none()

                // Material Symbols carry a solid cut of most icons, so "on"
                // is a filled glyph as well as a filled box.
                MaterialIcon {
                    anchors.centerIn: parent
                    name: tile.iconName
                    filled: tile.active
                    size: Math.round(Style.font.body * 1.4)
                    color: tile.solid ? tile.ink : (tile.active ? Color.background : Color.popups.text)
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
                    color: tile.ink
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: tile.subtitle !== ""
                    text: tile.subtitle
                    color: tile.solid ? Util.alpha(tile.ink, 0.7) : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }
            }
        }
    }
}
