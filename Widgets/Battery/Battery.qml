import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Components
import qs.Services
import qs.Commons

BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property var device: UPower.displayDevice

    // displayDevice aggregates every battery and reports no health, so health
    // has to come from the physical one behind it. Charge and rate stay on the
    // aggregate, which is the right answer on a machine with two batteries.
    readonly property var physical: {
        const devices = UPower.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].isLaptopBattery)
                return devices[i];
        }
        return null;
    }

    readonly property real health: {
        if (physical && physical.healthSupported)
            return physical.healthPercentage;
        if (device && device.healthSupported)
            return device.healthPercentage;
        return -1;
    }
    readonly property bool present: device && device.isPresent
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged)
    readonly property bool low: present && percent <= (cfg.lowThreshold || 20) && !charging

    readonly property string themedIcon: Icons.battery(percent, charging)

    readonly property string stateLabel: {
        if (!present)
            return "";
        switch (device.state) {
        case UPowerDeviceState.Charging:
            return "Charging";
        case UPowerDeviceState.FullyCharged:
            return "Full";
        case UPowerDeviceState.Empty:
            return "Empty";
        case UPowerDeviceState.PendingCharge:
            return "Pending charge";
        case UPowerDeviceState.PendingDischarge:
            return "Pending discharge";
        default:
            return "Discharging";
        }
    }

    // changeRate is always positive, so the sign has to come from the state.
    readonly property string powerLabel: {
        if (!present || !device.changeRate)
            return "";
        const rate = device.changeRate;
        if (rate < 0.05)
            return "";
        return (charging ? "+" : "-") + rate.toFixed(1) + "W";
    }

    readonly property string timeLabel: {
        if (!present)
            return "";
        const secs = charging ? device.timeToFull : device.timeToEmpty;
        if (!secs || secs <= 0)
            return "";
        // Round to minutes first, then split, so 59m59s reads as 1h 0m
        // rather than 60m.
        const total = Math.round(secs / 60);
        const hours = Math.floor(total / 60);
        const mins = total % 60;
        const rest = hours > 0 ? hours + "h " + mins + "m" : mins + "m";
        return (charging ? "Time until full: " : "Time remaining: ") + rest;
    }

    shown: present
    iconSource: themedIcon
    text: cfg.showPercent === false ? "" : percent + "%"
    iconColor: low ? Color.urgent : Color.foreground
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button === Qt.RightButton) {
            cfg.showPercent = cfg.showPercent === false;
            return;
        }
        panel.toggle(root);
    }

    Popout {
        id: panel
        bar: root.bar

        Column {
            width: root.cfg.panelWidth || 360
            spacing: 12

            // Headline: charge, state, draw and time remaining.
            Item {
                width: parent.width
                height: headline.implicitHeight

                Row {
                    id: headline
                    spacing: 12

                    BarIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: root.themedIcon
                        size: Math.round(Style.font.body * 2.8)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Row {
                            spacing: 8

                            Text {
                                anchors.baseline: stateText.baseline
                                text: root.percent + "%"
                                color: Color.accent
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 1.9)
                                font.bold: true
                            }

                            Text {
                                id: stateText
                                text: root.stateLabel
                                color: Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 1.35)
                            }
                        }

                        Row {
                            spacing: 10

                            Text {
                                visible: root.powerLabel !== ""
                                text: root.powerLabel
                                color: Color.accent
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 0.9)
                            }

                            Text {
                                visible: root.timeLabel !== ""
                                text: root.timeLabel
                                color: Color.foreground
                                opacity: 0.6
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 0.9)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: Math.round(Style.font.body * 1.9)
                    height: width
                    radius: 4
                    color: closeHover.containsMouse ? Style.selectedFill : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Color.foreground
                        opacity: 0.7
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }

                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.close()
                    }
                }
            }

            // Health and capacity, side by side.
            Row {
                width: parent.width
                spacing: 10
                visible: cards.length > 0

                readonly property var cards: {
                    const list = [];
                    if (root.health >= 0)
                        list.push({
                            label: "Health",
                            value: Math.round(root.health) + "%",
                            warn: root.health < 70
                        });
                    if (root.device && root.device.energyCapacity > 0)
                        list.push({
                            label: "Capacity",
                            value: root.device.energyCapacity.toFixed(1) + " Wh",
                            warn: false
                        });
                    return list;
                }
                readonly property int cellWidth: cards.length > 0 ? (width - spacing * (cards.length - 1)) / cards.length : width

                Repeater {
                    model: parent.cards

                    Rectangle {
                        required property var modelData

                        width: parent.cellWidth
                        height: Math.round(Style.font.body * 4)
                        radius: 8
                        color: Util.alpha(Color.foreground, 0.05)

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.parent.modelData.label
                                color: Color.foreground
                                opacity: 0.6
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 0.9)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.parent.modelData.value
                                color: parent.parent.modelData.warn ? Color.urgent : Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 1.35)
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // Power profiles. Performance is absent on hardware that cannot
            // do it, so the row is built from what the daemon reports.
            Row {
                id: profiles
                width: parent.width
                spacing: 10

                readonly property var options: {
                    const list = [
                        {
                            label: "Power Saver",
                            value: PowerProfile.PowerSaver
                        },
                        {
                            label: "Balanced",
                            value: PowerProfile.Balanced
                        }
                    ];
                    if (PowerProfiles.hasPerformanceProfile)
                        list.push({
                            label: "Performance",
                            value: PowerProfile.Performance
                        });
                    return list;
                }
                readonly property int cellWidth: (width - spacing * (options.length - 1)) / options.length

                Repeater {
                    model: profiles.options

                    Rectangle {
                        required property var modelData

                        readonly property bool current: PowerProfiles.profile === modelData.value

                        width: profiles.cellWidth
                        height: Math.round(Style.font.body * 2.9)
                        radius: 6
                        color: current ? Color.foreground : (profileHover.containsMouse ? Style.selectedFill : Style.normalFill)

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.parent.current
                                text: "✓"
                                color: Color.background
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 0.95)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.label
                                color: parent.parent.current ? Color.background : Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                            }
                        }

                        MouseArea {
                            id: profileHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PowerProfiles.profile = parent.modelData.value
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                text: {
                    switch (PowerProfiles.degradationReason) {
                    case PerformanceDegradationReason.LapDetected:
                        return "Performance limited: lap detected";
                    case PerformanceDegradationReason.HighTemperature:
                        return "Performance limited: running hot";
                    default:
                        return "";
                    }
                }
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.9)
            }
        }
    }
}
