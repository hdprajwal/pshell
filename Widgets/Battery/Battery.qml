import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Components
import qs.Services
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "qsbar.battery"
    ipcTarget: "qsbar.battery"

    property var cfg: ({})

    // Keyboard cursor over the power-profile row. Off until the panel opens
    // or an arrow key moves it, so a fresh open never highlights a profile
    // the user hasn't touched yet.
    property int profileIndex: 0
    property bool cursorActive: false

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
    readonly property bool showPercent: cfg.showPercent !== false

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

    // Performance is absent on hardware that cannot do it, so the row is
    // built from what the daemon reports.
    readonly property var profileOptions: {
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

    function selectProfileByDelta(delta) {
        if (profileOptions.length === 0)
            return;
        cursorActive = true;
        profileIndex = (profileIndex + delta + profileOptions.length) % profileOptions.length;
    }

    function activateSelectedProfile() {
        if (!cursorActive || profileIndex < 0 || profileIndex >= profileOptions.length)
            return;
        PowerProfiles.profile = profileOptions[profileIndex].value;
    }

    // No battery on a desktop; the widget takes no bar space rather than
    // sitting there showing nothing.
    visible: present
    implicitWidth: present ? button.implicitWidth : 0
    implicitHeight: present ? button.implicitHeight : 0

    // A percentage sits well past an icon's width, so the open-panel mark
    // should track what's painted rather than the whole (widened) slot.
    readonly property real openPanelIndicatorWidth: showPercent && !button.vertical ? button.width : 0

    onOpenedChanged: {
        if (opened) {
            const idx = profileOptions.findIndex(o => o.value === PowerProfiles.profile);
            profileIndex = idx >= 0 ? idx : 0;
            cursorActive = false;
        }
    }
    onPresentChanged: if (!present) close()

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // Percentage-in-the-bar widens the slot to fit the label; matched by
        // opticalSize so the icon+label pair centers as one unit instead of
        // the icon alone centering in the wider slot and stranding the text.
        slotSize: root.showPercent && !vertical ? Style.bar.iconSlot + percentMetrics.width + Style.spacing.sm : Style.bar.iconSlot
        opticalSize: root.showPercent && !vertical ? slotSize : Style.bar.iconCanvas
        iconComponent: Component {
            Row {
                anchors.centerIn: parent
                spacing: Style.spacing.sm

                BarIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSource: root.themedIcon
                    size: Style.bar.iconCanvas
                    color: root.low ? Color.urgent : Color.foreground
                }

                Text {
                    visible: root.showPercent && !button.vertical
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.percent + "%"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
            }
        }

        onPressed: b => {
            if (b === Qt.RightButton) {
                root.cfg.showPercent = root.cfg.showPercent === false;
                return;
            }
            root.toggle();
        }
    }

    // Off-screen measurement of the percent label so slotSize/opticalSize
    // can widen to fit it without depending on an id inside the Component
    // above, whose scope is private to its own instance.
    TextMetrics {
        id: percentMetrics
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        text: root.percent + "%"
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth((root.cfg.panelWidth || 360) + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            onMoveRequested: (dx, dy) => {
                const delta = dx !== 0 ? dx : dy;
                if (delta !== 0)
                    root.selectProfileByDelta(delta);
            }
            onActivateRequested: root.activateSelectedProfile()
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                // Headline: icon, state, and the big percentage.
                Item {
                    width: parent.width
                    implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

                    BarIcon {
                        id: heroIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: root.themedIcon
                        size: Style.font.display
                        color: root.low ? Color.urgent : Color.popups.text
                    }

                    Column {
                        id: heroLabels
                        anchors.left: heroIcon.right
                        anchors.leftMargin: Style.space(14)
                        anchors.right: heroPercent.left
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                            width: parent.width
                            text: "Battery"
                            color: Color.popups.text
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.stateLabel.toUpperCase()
                            color: Color.muted
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 1.2
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: heroPercent
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.percent + "%"
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.displayLarge
                        font.bold: true
                    }
                }

                // Draw rate and time remaining, when the daemon has them.
                Row {
                    width: parent.width
                    spacing: Style.spacing.xl
                    visible: root.powerLabel !== "" || root.timeLabel !== ""

                    Text {
                        visible: root.powerLabel !== ""
                        text: root.powerLabel
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                        visible: root.timeLabel !== ""
                        text: root.timeLabel
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }
                }

                // Health and capacity, side by side.
                Row {
                    width: parent.width
                    spacing: Style.spacing.xl
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
                            height: Style.space(64)
                            radius: Style.cornerRadius
                            color: Util.alpha(Color.popups.text, 0.05)

                            Column {
                                anchors.centerIn: parent
                                spacing: Style.spacing.xxs

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: parent.parent.modelData.label
                                    color: Color.muted
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: parent.parent.modelData.value
                                    color: parent.parent.modelData.warn ? Color.urgent : Color.popups.text
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.subtitle
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                PanelSeparator {
                    visible: root.profileOptions.length > 0
                }

                Column {
                    width: parent.width
                    spacing: Style.spacing.lg
                    visible: root.profileOptions.length > 0

                    PanelSectionHeader {
                        text: "POWER PROFILE"
                    }

                    Row {
                        id: profileRow
                        width: parent.width
                        spacing: Style.spacing.md

                        readonly property real cellWidth: root.profileOptions.length > 0 ? (width - spacing * (root.profileOptions.length - 1)) / root.profileOptions.length : 0

                        Repeater {
                            model: root.profileOptions

                            Button {
                                required property var modelData
                                required property int index

                                width: profileRow.cellWidth
                                text: modelData.label
                                fontSize: Style.font.bodySmall
                                bordered: true
                                active: PowerProfiles.profile === modelData.value
                                hasCursor: root.cursorActive && root.profileIndex === index
                                onClicked: PowerProfiles.profile = modelData.value
                                onHovered: h => {
                                    if (h) {
                                        root.cursorActive = true;
                                        root.profileIndex = index;
                                    }
                                }
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
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
