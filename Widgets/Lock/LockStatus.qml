import QtQuick
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Services
import qs.Ui

// The one line of status a locked machine owes you.
//
// Battery, because "is it going to be dead when I come back" is the only
// question you cannot answer by looking at the machine. Network, because a
// laptop that quietly dropped off wifi while locked explains a lot of
// mornings. Keyboard layout, because a password typed on the wrong one
// fails in a way that looks exactly like forgetting it.
//
// MaterialIcon rather than BarIcon throughout: the glyph font is vendored in
// assets/, so these cannot come up empty on a surface where an empty icon
// has no panel to open and no tooltip to explain itself.
Row {
    id: root

    // Passed in rather than read here: the Lock service already polls
    // Hyprland for Caps Lock, and the layout arrives in the same answer.
    property string keyboardLayout: ""

    spacing: Style.spacing.xxl

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int batteryPercent: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)

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

    // One item, one component: each is its own icon-plus-label pair and
    // hides whole rather than leaving a labelled icon with nothing to say.
    component Entry: Row {
        id: entry

        property string glyph: ""
        property string label: ""

        spacing: Style.spacing.md

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: entry.glyph
            size: Style.font.icon
            color: Commons.Color.lock.text
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: entry.label
            color: Commons.Color.lock.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
    }

    Entry {
        visible: root.hasBattery
        glyph: Glyphs.battery(root.batteryPercent, root.charging)
        label: root.batteryPercent + "%"
    }

    Entry {
        // Wired wins when it is up: it is the connection actually carrying
        // traffic, so wifi strength there would be the wrong answer.
        // Matches how the Network widget picks its bar icon.
        glyph: root.wiredUp ? Glyphs.wired(true) : Glyphs.wifi(Networking.wifiEnabled, root.activeWifi !== null, root.activeWifi ? root.activeWifi.signalStrength : 0)
        label: {
            if (root.wiredUp)
                return "Wired";
            if (root.activeWifi)
                return root.activeWifi.name;
            return "Offline";
        }
    }

    Entry {
        visible: root.keyboardLayout !== ""
        glyph: "keyboard"
        label: root.keyboardLayout
    }
}
