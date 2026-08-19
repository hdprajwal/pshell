//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow

            required property var modelData

            // The contract QML widgets read. Names match Omarchy's bar object
            // so a widget written for it works here without edits.
            readonly property bool vertical: Config.position === "left" || Config.position === "right"
            readonly property string position: Config.position
            readonly property int barSize: Config.size
            readonly property color foreground: Config.fg
            readonly property color barForeground: Config.fg
            readonly property color background: Config.bg
            readonly property color urgent: Config.urgent
            readonly property string fontFamily: Config.fontFamily

            property var moduleWidgetMap: ({})
            property var activePopout: null

            function run(command) {
                Quickshell.execDetached(["bash", "-lc", String(command)]);
            }

            function showTooltip(target, text) {
                if (!text)
                    return;
                tooltip.target = target;
                tooltip.text = String(text);
            }

            function hideTooltip(target) {
                if (tooltip.target === target)
                    tooltip.target = null;
            }

            // One popup at a time. A widget opening its panel closes whatever
            // was open before.
            function requestPopout(owner) {
                if (activePopout && activePopout !== owner && activePopout.close)
                    activePopout.close();
                activePopout = owner;
            }

            function releasePopout(owner) {
                if (activePopout === owner)
                    activePopout = null;
            }

            function registerModuleWidget(name, item) {
                const map = moduleWidgetMap;
                const list = map[name] || [];
                if (list.indexOf(item) < 0)
                    list.push(item);
                map[name] = list;
                moduleWidgetMap = map;
            }

            function unregisterModuleWidget(name, item) {
                const map = moduleWidgetMap;
                const list = map[name] || [];
                const at = list.indexOf(item);
                if (at >= 0)
                    list.splice(at, 1);
                map[name] = list;
                moduleWidgetMap = map;
            }

            function moduleWidgets(name) {
                return moduleWidgetMap[name] || [];
            }

            screen: modelData
            color: Config.bg

            anchors {
                top: Config.position === "top" || barWindow.vertical
                bottom: Config.position === "bottom" || barWindow.vertical
                left: Config.position === "left" || !barWindow.vertical
                right: Config.position === "right" || !barWindow.vertical
            }

            implicitHeight: barWindow.vertical ? 0 : Config.size
            implicitWidth: barWindow.vertical ? Config.size : 0

            WlrLayershell.namespace: "qsbar"
            WlrLayershell.layer: WlrLayer.Top

            Section {
                entries: Config.left
                bar: barWindow
                anchors.left: parent.left
                anchors.leftMargin: Config.gap
                anchors.verticalCenter: parent.verticalCenter
            }

            Section {
                entries: Config.center
                bar: barWindow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            Section {
                entries: Config.right
                bar: barWindow
                anchors.right: parent.right
                anchors.rightMargin: Config.gap
                anchors.verticalCenter: parent.verticalCenter
            }

            PopupWindow {
                id: tooltip

                property var target: null
                property string text: ""

                visible: target !== null && text !== ""
                color: "transparent"
                implicitWidth: tooltipLabel.implicitWidth + 16
                implicitHeight: tooltipLabel.implicitHeight + 10

                anchor.window: barWindow
                anchor.rect.x: tooltip.target ? tooltip.target.mapToItem(null, 0, 0).x + tooltip.target.width / 2 - tooltip.implicitWidth / 2 : 0
                anchor.rect.y: Config.position === "bottom" ? -tooltip.implicitHeight : Config.size

                Rectangle {
                    anchors.fill: parent
                    color: Config.bg
                    radius: Config.cornerRadius
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)

                    Text {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        text: tooltip.text
                        color: Config.fg
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }
                }
            }
        }
    }
}
