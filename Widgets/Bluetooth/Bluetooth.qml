import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Components
import qs.Services
import qs.Commons
import qs.Ui

// Bluetooth status in the bar with a paired/nearby device list panel. Shaped
// the way Calendar is: a qs.Ui.Panel owns open/close/IPC, a BarIconButton
// paints the bar slot, and a KeyboardPanel is the popup surface.
Panel {
    id: root
    moduleName: "qsbar.bluetooth"
    ipcTarget: "qsbar.bluetooth"

    property var cfg: ({})

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter && adapter.enabled

    readonly property var connectedDevices: {
        if (!root.enabled)
            return [];
        return Bluetooth.devices.values.filter(d => d.connected);
    }

    readonly property bool showCount: cfg.showCount === true && connectedDevices.length > 0

    // No adapter at all means there is nothing this widget can ever do, so
    // it drops out of the bar rather than sitting there permanently dimmed.
    // Deriving this from `adapter` rather than from the button's own
    // visibility keeps it out of the zero-width feedback loop BarIndicator
    // has to guard against.
    implicitWidth: root.adapter ? button.implicitWidth : 0
    implicitHeight: button.implicitHeight

    // Discovery costs power, so it only runs while the panel is open.
    onOpenedChanged: deviceList.discover(root.opened)

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // An adapter sitting off is the one state actually worth flagging.
        active: root.adapter !== null && !root.enabled
        slotSize: root.showCount ? Style.bar.iconSlot + countLabel.implicitWidth + Style.spacing.xs : Style.bar.iconSlot

        iconComponent: Component {
            BarIcon {
                anchors.fill: parent
                iconSource: Icons.bluetooth(root.enabled, root.connectedDevices.length > 0)
                size: Style.bar.iconCanvas
                color: button.active ? button.activeColor : button.foreground
            }
        }

        Text {
            id: countLabel
            visible: root.showCount
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            text: String(root.connectedDevices.length)
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
        }

        onPressed: b => {
            if (b === Qt.RightButton) {
                if (root.adapter)
                    root.adapter.enabled = !root.adapter.enabled;
                return;
            }
            root.toggle();
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(280))
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

                Row {
                    spacing: Style.spacing.lg

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.subtitle
                    }

                    ToggleSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.enabled
                        onToggled: if (root.adapter)
                            root.adapter.enabled = !root.adapter.enabled
                    }
                }

                BluetoothList {
                    id: deviceList
                    maxDevices: root.cfg.maxDevices || 8
                }

                Text {
                    visible: deviceList.children.length > 0
                    text: "Right click a device to forget it"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }
}
