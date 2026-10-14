import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.Services
import qs.Widgets.Bluetooth
import qs.Widgets.Network
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One panel for the things you actually reach for: volume, brightness, wifi,
// bluetooth, audio devices and the session buttons.
Panel {
    id: root
    moduleName: "pshell.controlcenter"
    ipcTarget: "pshell.controlcenter"

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

    // ---------- Session actions ----------
    //
    // The commands and the confirmation policy both come from
    // Services/PowerMenu.qml now. They used to be three inline `{icon, cmd,
    // tip}` objects in the Repeater below, which meant this panel and any
    // other surface offering "log out" would each carry their own idea of
    // what that runs.
    //
    // The three legacy keys on this widget's own config entry -- `lock`,
    // `power`, `logout` -- still win where they are set. The README has
    // documented them since Phase 2 and a config.json in the wild cannot be
    // edited from here, so they are passed through as overrides rather than
    // being quietly replaced by the `power` config group.
    //
    // Three buttons, in the order they have always been in, rather than the
    // service's five: this is a header strip, not a menu, and suspend and
    // restart are one keystroke away in the menu that is.
    readonly property var sessionButtons: [
        {
            id: "lock",
            override: String(root.cfg.lock || "")
        },
        {
            id: "poweroff",
            override: String(root.cfg.power || "")
        },
        {
            id: "logout",
            override: String(root.cfg.logout || "")
        }
    ]

    // What the dialog is holding, while it is open.
    property string pendingId: ""
    property string pendingOverride: ""

    // New here, and deliberately: power off and log out used to fire on the
    // press, so a mis-click on a 22px button in a header ended the session
    // with everything unsaved in it. The policy is the service's, so this
    // panel and the power menu ask the same question about the same actions.
    function runAction(id, override) {
        const action = PowerMenu.actionFor(id);
        if (action && action.confirms) {
            root.pendingId = id;
            root.pendingOverride = override;
            confirm.message = action.question;
            // Cancel, not Confirm. The dialog's own default lands on the
            // right-hand button, which for a destructive question means
            // Return powers the machine off without reading it.
            confirm.selectedIndex = 0;
            confirm.opened = true;
            Qt.callLater(function () {
                if (confirm.opened)
                    confirm.forceActiveFocus();
            });
            return;
        }
        PowerMenu.invoke(id, override);
        root.close();
    }

    onOpenedChanged: {
        if (opened) {
            uptimeProc.running = true;
        } else {
            confirm.opened = false;
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
            // The dialog wants Left/Right and Return for its two buttons, not
            // this panel's cursor movement -- the same rule the search fields
            // follow.
            blocked: confirm.opened
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
                    foreground: Commons.Color.popups.text

                    iconComponent: Component {
                        BorderSurface {
                            width: Math.round(Style.font.body * 3)
                            height: width
                            radius: width / 2
                            color: Style.normalFillFor(Commons.Color.popups.text, Commons.Color.accent)
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
                                color: Commons.Color.popups.text
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

                            // Ahead of the session buttons, and separated
                            // from them by nothing but order: settings is a
                            // place you go, and lock/power/logout are things
                            // that end your session. Sitting the gear at the
                            // far end next to "power off" is how a mis-click
                            // becomes a shutdown.
                            PanelActionButton {
                                foreground: Commons.Color.popups.text
                                tooltipText: "Settings"
                                onClicked: {
                                    SettingsApp.open("");
                                    root.close();
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: Glyphs.settings
                                    size: Style.font.icon
                                    color: Commons.Color.popups.text
                                }
                            }

                            Repeater {
                                model: root.sessionButtons

                                // The glyph is a child rather than `iconText`
                                // because that draws in the button's own font,
                                // which is also the tooltip's.
                                PanelActionButton {
                                    required property var modelData

                                    readonly property var action: PowerMenu.actionFor(modelData.id)

                                    foreground: Commons.Color.popups.text
                                    tooltipText: action ? action.label : ""
                                    onClicked: root.runAction(modelData.id, modelData.override)

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: parent.action ? parent.action.icon : ""
                                        size: Style.font.icon
                                        color: Commons.Color.popups.text
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
                        color: Commons.Color.popups.text
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
                        color: Commons.Color.popups.text
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

                // ---------- Keyboard backlight ----------
                //
                // No mute or right-click behaviour: a keyboard backlight has
                // no muted state, zero is just its lowest step.
                Item {
                    width: parent.width
                    visible: Brightness.keyboardAvailable
                    height: visible ? keyboardSlider.implicitHeight : 0

                    MaterialIcon {
                        id: keyboardIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.keyboard
                        size: Math.round(Style.font.body * 1.4)
                        color: Commons.Color.popups.text
                    }

                    PanelSlider {
                        id: keyboardSlider
                        bar: root.bar
                        anchors.left: keyboardIcon.right
                        anchors.leftMargin: Style.spacing.lg
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        minimum: 0
                        maximum: 1
                        // One hardware step per notch, not 0.05: this device
                        // is usually three steps, and a slider with finer
                        // notches than the hardware jumps back under the
                        // finger when the service rounds the write.
                        step: Brightness.keyboardMax > 0 ? 1 / Brightness.keyboardMax : 1
                        value: Brightness.keyboardFraction
                        onMoved: v => Brightness.setKeyboardFraction(v)
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

                // The two whole-screen toggles. Night mode is pshell's own
                // nightlight (Services/Nightlight.qml) wherever hyprsunset is
                // installed. A `nightMode` command on this widget still wins,
                // as it did before there was a built-in one, so a config that
                // drives gammastep or wlsunset keeps doing so; `false` hides
                // the tile like `darkMode: false` does.
                Row {
                    width: parent.width
                    spacing: Style.spacing.lg
                    visible: hasNight || hasDark

                    readonly property bool nightCommand: typeof root.cfg.nightMode === "string" && root.cfg.nightMode !== ""
                    readonly property bool hasNight: root.cfg.nightMode !== false && (nightCommand || Nightlight.available)
                    readonly property bool hasDark: root.cfg.darkMode !== false
                    readonly property int cellWidth: hasNight && hasDark ? (width - spacing) / 2 : width

                    ControlTile {
                        width: parent.cellWidth
                        visible: parent.hasNight
                        iconName: Glyphs.nightMode
                        title: "Night Mode"
                        // A command of the user's own has no state pshell can
                        // read, so that tile stays dark, as it always has.
                        subtitle: parent.nightCommand ? "" : (Nightlight.active ? Nightlight.temperature + "K" : "Off")
                        active: !parent.nightCommand && Nightlight.active
                        hasDetail: false
                        onToggled: {
                            if (parent.nightCommand)
                                root.run(String(root.cfg.nightMode));
                            else
                                Nightlight.toggle();
                        }
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
                        // then something pshell cannot see.
                        active: SystemTheme.available && SystemTheme.scheme === "dark"
                        onToggled: root.run(root.cfg.darkModeCommand || "gsettings set org.gnome.desktop.interface color-scheme \"$(test \"$(gsettings get org.gnome.desktop.interface color-scheme)\" = \"'prefer-dark'\" && echo prefer-light || echo prefer-dark)\"")
                    }
                }
            }

            // Declared after the Column so it stacks above it, and outside it
            // so the Column does not lay it out as one more row.
            //
            // It handles its own keys rather than having the catcher above
            // translate them: ConfirmDialog.handleKey already knows Left,
            // Right, Return and Escape mean here, and a second copy of that
            // in every panel that grows a dialog is how the two come to
            // disagree about which button Escape hits.
            ConfirmDialog {
                id: confirm

                anchors.fill: parent
                background: Commons.Color.popups.background
                foreground: Commons.Color.popups.text
                confirmText: PowerMenu.actionFor(root.pendingId) ? PowerMenu.actionFor(root.pendingId).label : "Confirm"

                Keys.onPressed: function (event) {
                    if (confirm.handleKey(event))
                        event.accepted = true;
                }

                onCanceled: {
                    confirm.opened = false;
                    keyCatcher.forceActiveFocus();
                }

                onConfirmed: {
                    confirm.opened = false;
                    PowerMenu.invoke(root.pendingId, root.pendingOverride);
                    root.close();
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
                implicitHeight: {
                    if (root.detail === "wifi")
                        return wifiPane.implicitHeight;
                    if (root.detail === "bluetooth")
                        return btList.implicitHeight;
                    if (root.detail === "sink")
                        return sinkList.implicitHeight;
                    return sourceList.implicitHeight;
                }

                // The container outlived the "Network settings" button it was
                // added for, and it stays: keying visibility off root.detail
                // rather than off `netList.visible` keeps the size an input
                // rather than a value the pane also sets.
                Column {
                    id: wifiPane
                    width: detailColumn.width
                    visible: root.detail === "wifi"
                    spacing: Style.spacing.md

                    NetworkList {
                        id: netList
                        rowWidth: wifiPane.width
                    }
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
        readonly property color onColor: Style.selectedStateColor(Commons.Color.popups.text, Commons.Color.accent)
        readonly property color ink: tile.solid ? Commons.Color.popups.background : Commons.Color.popups.text

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
                color: tile.solid ? "transparent" : (tile.active ? tile.onColor : (iconHover.containsMouse ? Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent) : Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent)))
                borderSpec: Border.none()

                // Material Symbols carry a solid cut of most icons, so "on"
                // is a filled glyph as well as a filled box.
                MaterialIcon {
                    anchors.centerIn: parent
                    name: tile.iconName
                    filled: tile.active
                    size: Math.round(Style.font.body * 1.4)
                    color: tile.solid ? tile.ink : (tile.active ? Commons.Color.background : Commons.Color.popups.text)
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
                    color: tile.solid ? Util.alpha(tile.ink, 0.7) : Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }
            }
        }
    }
}
