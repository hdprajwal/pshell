pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "BatteryAlert.js" as Steps

// Warn when the battery runs low: a notification at 20%, then again at 15%,
// 10% and 5%, each sent once. Plugging in the charger starts it over.
//
// A singleton rather than part of the battery widget: widgets are built once
// per monitor, which would send one warning per screen, and a bar without the
// battery widget should still warn.
//
// Nothing polls: UPower pushes every change in charge, and the bindings below
// re-run on each one.
Singleton {
    id: root

    readonly property int threshold: 20
    readonly property int step: 5

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent
    readonly property int percent: present ? Math.round(device.percentage * 100) : -1
    readonly property bool discharging: present && device.state === UPowerDeviceState.Discharging
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged)

    // The step already warned for since the last charge; -1 for none.
    property int lastLevel: -1

    function check() {
        if (root.charging) {
            root.lastLevel = -1;
            return;
        }
        if (!root.discharging || root.percent < 0)
            return;
        const level = Steps.nextAlert(root.percent, root.lastLevel, root.threshold, root.step);
        if (level < 0)
            return;
        root.lastLevel = level;
        // Critical from 10% down, so it stays up until dismissed rather than
        // timing out while you are looking elsewhere.
        const critical = level <= 10;
        Quickshell.execDetached(["notify-send", "-a", "pshell", "-u", critical ? "critical" : "normal", "-i", critical ? "battery-caution" : "battery-low", "Battery low", root.percent + "% left. Plug in the charger."]);
    }

    onPercentChanged: check()
    onDischargingChanged: check()
    onChargingChanged: check()
    Component.onCompleted: check()
}
