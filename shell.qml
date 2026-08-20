// Without a platform theme, Qt does not know which icon theme is in use and
// resolves almost nothing: only hicolor icons are found, so battery, network
// and bluetooth all come back empty. gtk3 makes it read the GTK icon theme,
// which is where Papirus and friends are configured.
//@ pragma Env QT_QPA_PLATFORMTHEME=gtk3
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Services
import qs.Commons

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
            readonly property int barSize: Style.bar.sizeHorizontal
            readonly property color foreground: Color.foreground
            readonly property color barForeground: Color.foreground
            readonly property color background: Color.background
            readonly property color urgent: Color.urgent
            readonly property string fontFamily: Style.font.family
            // Omarchy's widgets animate their foreground unless the bar says
            // not to. qsbar has no setting for it, so it is simply on.
            readonly property bool foregroundAnimationEnabled: true

            // Which way a panel should open, given the edge the bar is on.
            readonly property int popoutEdge: {
                switch (Config.position) {
                case "bottom":
                    return Edges.Top;
                case "left":
                    return Edges.Right;
                case "right":
                    return Edges.Left;
                default:
                    return Edges.Bottom;
                }
            }

            property var moduleWidgetMap: ({})
            readonly property var activePopout: PopoutManager.current

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

            // Part of the contract Omarchy widgets expect. Both defer to the
            // same coordinator the built-in panels use, so a third-party
            // widget's popup closes the battery panel and vice versa.
            function requestPopout(owner) {
                PopoutManager.open(owner);
            }

            function releasePopout(owner) {
                PopoutManager.release(owner);
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
            // The surface is transparent and the bar is a rectangle inside
            // it, because a detached bar wants rounded corners and a window
            // cannot have them.
            color: "transparent"

            anchors {
                top: Config.position === "top" || barWindow.vertical
                bottom: Config.position === "bottom" || barWindow.vertical
                left: Config.position === "left" || !barWindow.vertical
                right: Config.position === "right" || !barWindow.vertical
            }

            // Lifts the bar off the screen edges. The compositor still
            // reserves the space, so a maximised window stops outside the
            // margin rather than sliding under it.
            margins {
                top: Style.spacing.barMarginTop
                bottom: Style.spacing.barMarginBottom
                left: Style.spacing.barMarginLeft
                right: Style.spacing.barMarginRight
            }

            implicitHeight: barWindow.vertical ? 0 : Style.bar.sizeHorizontal
            implicitWidth: barWindow.vertical ? Style.bar.sizeVertical : 0

            WlrLayershell.namespace: "qsbar"
            WlrLayershell.layer: WlrLayer.Top

            // Clicking the bar itself dismisses whatever panel is open.
            //
            // A popout covers the screen so a click anywhere lands on its
            // own dismiss layer, but it honours exclusive zones, so it never
            // covers the bar. That is what keeps the widgets clickable while
            // a panel is open, and it leaves this as the handler for the one
            // strip the dismiss layer cannot reach.
            //
            // Declared before the sections so they sit above it: a widget's
            // own handler takes the press first and this only ever sees the
            // gaps between them.
            // Square while the bar is flush with the screen: rounding a
            // corner that has nothing behind it just eats the background.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                radius: Style.spacing.barDetached ? Style.cornerRadius : 0
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: PopoutManager.closeAll()
            }

            Section {
                entries: Config.left
                bar: barWindow
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.barPadding
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
                anchors.rightMargin: Style.spacing.barPadding
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
                anchor.rect.y: Config.position === "bottom" ? -tooltip.implicitHeight : Style.bar.sizeHorizontal

                Rectangle {
                    anchors.fill: parent
                    color: Color.tooltip.background
                    radius: Style.cornerRadius
                    border.width: Style.spacing.hairline
                    border.color: Color.tooltip.border

                    Text {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        text: tooltip.text
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }
            }
        }
    }
}
