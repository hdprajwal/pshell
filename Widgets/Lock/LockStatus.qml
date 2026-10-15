import QtQuick
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Services
import qs.Ui

// The status row in the top-right corner, in DMS's order: keyboard layout,
// what is playing, the weather, the radios and the volume, then the battery.
// Hairline dividers between whichever groups are present, as DMS draws them,
// on one flat card so the row stays legible over any wallpaper.
//
// Battery, because "is it going to be dead when I come back" is the one
// question you cannot answer by looking at the machine. Network, because a
// laptop that quietly dropped off wifi while locked explains a lot of
// mornings. The layout, because a password typed on the wrong one fails in
// a way that looks exactly like forgetting it.
//
// MaterialIcon rather than BarIcon throughout: the glyph font is vendored in
// assets/, so these cannot come up empty on a surface where an empty icon
// has no panel to open and no tooltip to explain itself.
Rectangle {
    id: root

    // Passed in rather than read here: the Lock service already polls
    // Hyprland for Caps Lock, and the layout arrives in the same answer.
    property string keyboardLayout: ""
    property bool showMedia: true

    signal layoutClicked

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int batteryPercent: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)
    readonly property bool batteryLow: hasBattery && !charging && batteryPercent <= 15

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

    readonly property bool wiredUp: wiredDevice !== null && wiredDevice.connected

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

    readonly property bool online: wiredUp || activeWifi !== null
    readonly property bool btOn: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property bool btConnected: btOn && Bluetooth.devices.values.some(d => d.connected)

    readonly property int pad: Style.spacing.xxl

    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: Math.round(Style.font.body * 3.4)
    radius: Style.cornerRadius
    color: Commons.Color.lock.background
    // Nothing to say, nothing drawn: an empty card in the corner reads as a
    // widget that failed to load.
    visible: row.visibleCount > 0

    // Over the layout group rather than inside it: a child of a Row sized
    // from that Row feeds its own width back into the Row's layout.
    MouseArea {
        x: row.x + layout.x
        y: row.y + layout.y
        width: layout.width
        height: layout.height
        visible: layout.visible
        cursorShape: Qt.PointingHandCursor
        onClicked: root.layoutClicked()
    }

    Row {
        id: row

        // How many groups made it, so the card can vanish with none and each
        // divider can tell whether it has a neighbour to divide from.
        readonly property int visibleCount: (layout.visible ? 1 : 0) + (media.visible ? 1 : 0) + (weather.visible ? 1 : 0) + 1 + (power.visible ? 1 : 0)

        anchors.centerIn: parent
        spacing: Style.spacing.xxl

        // Cycles on click, as DMS's does. Only here at all with two or more
        // layouts configured; see Lock.keyboardLayout.
        Row {
            id: layout

            anchors.verticalCenter: parent.verticalCenter
            visible: root.keyboardLayout !== ""
            spacing: Style.spacing.sm

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Glyphs.keyboard
                size: Style.font.icon
                color: Commons.Color.lock.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.keyboardLayout
                color: Commons.Color.lock.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }

        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.hairline
            height: Style.font.icon
            color: Util.alpha(Commons.Color.lock.text, 0.25)
            visible: layout.visible
        }

        LockMedia {
            id: media

            anchors.verticalCenter: parent.verticalCenter
            visible: root.showMedia && media.active
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.hairline
            height: Style.font.icon
            color: Util.alpha(Commons.Color.lock.text, 0.25)
            visible: media.visible
        }

        // Only with a reading in hand. The Weather service fetches only while
        // a weather widget is in the bar, so without one this stays away
        // rather than showing a dash for a forecast nobody asked for.
        Row {
            id: weather

            anchors.verticalCenter: parent.verticalCenter
            visible: Weather.summary.valid
            spacing: Style.spacing.sm

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Weather.summary.icon
                size: Style.font.icon
                color: Commons.Color.lock.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.summary.temp
                color: Commons.Color.lock.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.hairline
            height: Style.font.icon
            color: Util.alpha(Commons.Color.lock.text, 0.25)
            visible: weather.visible
        }

        // The radios and the volume, icons only, the way DMS draws them: a
        // network name is the one label here that could be long, and the
        // signal bars already answer the question that matters.
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            // Wired wins when it is up: it is the connection actually
            // carrying traffic, so wifi strength there would be the wrong
            // answer. Matches how the Network widget picks its bar icon.
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.wiredUp ? Glyphs.wired(true) : Glyphs.wifi(Networking.wifiEnabled, root.activeWifi !== null, root.activeWifi ? root.activeWifi.signalStrength : 0)
                size: Style.font.icon
                color: root.online ? Commons.Color.lock.text : Commons.Color.lock.placeholder
            }

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.btOn
                name: Glyphs.bluetooth(true, root.btConnected)
                size: Style.font.icon
                color: root.btConnected ? Commons.Color.lock.text : Commons.Color.lock.placeholder
            }

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: Audio.sinkReady
                name: Glyphs.volume(Audio.muted, Audio.volume)
                size: Style.font.icon
                color: Audio.muted ? Commons.Color.lock.placeholder : Commons.Color.lock.text
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.hairline
            height: Style.font.icon
            color: Util.alpha(Commons.Color.lock.text, 0.25)
            visible: power.visible
        }

        // Red when it is about to run out, the accent while it charges --
        // DMS's colouring, and the only part of this row worth a colour.
        Row {
            id: power

            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasBattery
            spacing: Style.spacing.sm

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Glyphs.battery(root.batteryPercent, root.charging)
                size: Style.font.icon
                color: root.batteryLow ? Commons.Color.lock.textError : (root.charging ? Commons.Color.lock.borderActive : Commons.Color.lock.text)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.batteryPercent + "%"
                color: root.batteryLow ? Commons.Color.lock.textError : Commons.Color.lock.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }
        }
    }
}
