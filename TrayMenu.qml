import QtQuick
import Quickshell
import Quickshell.Hyprland

// The menu a tray icon opens on right click, drawn by qsbar rather than
// handed to QsMenuAnchor, so it picks up the bar's colours and font.
//
// Submenus drill in and out in place instead of flying out sideways. A
// flyout has to guess which way it can grow without leaving the screen;
// drilling in never has that problem.
PopupWindow {
    id: popup

    property var trayItem: null
    property var anchorItem: null
    property int menuEdge: Edges.Bottom

    readonly property int rowHeight: Math.round(Config.fontSize * 2.2)
    readonly property int padding: 6
    readonly property int maxHeight: 480

    function openFor(item, anchor, edge) {
        stack.clear();
        popup.trayItem = item;
        popup.anchorItem = anchor;
        popup.menuEdge = edge;
    }

    function close() {
        popup.trayItem = null;
        popup.anchorItem = null;
        stack.clear();
    }

    function topHandle() {
        return stack.count > 0 ? stack.get(stack.count - 1).handle : null;
    }

    function enterSubMenu(entry) {
        if (!entry || !entry.hasChildren)
            return;
        stack.append({
            handle: entry.menu || entry,
            label: entry.text || ""
        });
    }

    function goBack() {
        if (stack.count > 0)
            stack.remove(stack.count - 1);
    }

    // An entry can expose either name depending on the app behind it.
    function trigger(entry) {
        if (typeof entry.triggered === "function")
            entry.triggered();
        else if (typeof entry.activate === "function")
            entry.activate();
        popup.close();
    }

    visible: trayItem !== null && anchorItem !== null
    color: "transparent"

    anchor.item: popup.anchorItem
    anchor.edges: popup.menuEdge
    anchor.gravity: popup.menuEdge

    implicitWidth: Math.max(180, column.implicitWidth + padding * 2)
    implicitHeight: Math.min(maxHeight, column.implicitHeight + padding * 2)

    ListModel {
        id: stack
    }

    QsMenuOpener {
        id: rootOpener
        menu: popup.trayItem ? popup.trayItem.menu : null
    }

    QsMenuOpener {
        id: subOpener
        menu: popup.topHandle()
    }

    HyprlandFocusGrab {
        active: popup.visible
        windows: [popup]
        onCleared: popup.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Config.bg
        radius: Config.cornerRadius > 0 ? Config.cornerRadius : 6
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.15)

        Flickable {
            anchors.fill: parent
            anchors.margins: popup.padding
            contentWidth: width
            contentHeight: column.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: column
                width: parent.width
                spacing: 1

                // Header doubles as the way back out of a submenu.
                Item {
                    width: parent.width
                    height: popup.rowHeight
                    visible: stack.count > 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "‹  " + (stack.count > 0 ? stack.get(stack.count - 1).label : "")
                        color: Config.fg
                        opacity: 0.7
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.goBack()
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    visible: stack.count > 0
                    color: Qt.rgba(1, 1, 1, 0.12)
                }

                Repeater {
                    model: stack.count > 0 ? subOpener.children : rootOpener.children

                    Rectangle {
                        id: row

                        required property var modelData
                        readonly property bool separator: modelData ? modelData.isSeparator : false
                        readonly property bool usable: modelData && !separator && modelData.enabled !== false

                        width: column.width
                        height: separator ? 1 : popup.rowHeight
                        radius: separator ? 0 : 4
                        color: {
                            if (separator)
                                return Qt.rgba(1, 1, 1, 0.12);
                            return hover.containsMouse && usable ? Qt.rgba(1, 1, 1, 0.1) : "transparent";
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: row.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.modelData.hasChildren)
                                    popup.enterSubMenu(row.modelData);
                                else
                                    popup.trigger(row.modelData);
                            }
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: !row.separator

                            // Checkbox for a toggle, circle for a radio.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Config.fontSize
                                height: Config.fontSize
                                visible: row.modelData && row.modelData.buttonType !== undefined && row.modelData.buttonType !== 0
                                radius: row.modelData && row.modelData.buttonType === 2 ? width / 2 : 2
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.4)

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 6
                                    height: parent.height - 6
                                    radius: parent.radius > 2 ? parent.radius - 3 : 1
                                    color: Config.accent
                                    visible: row.modelData && row.modelData.checkState === 2
                                }
                            }

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Config.fontSize
                                height: Config.fontSize
                                visible: row.modelData && (row.modelData.icon || "") !== ""
                                source: row.modelData ? (row.modelData.icon || "") : ""
                                sourceSize.width: Config.fontSize
                                sourceSize.height: Config.fontSize
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData ? (row.modelData.text || "") : ""
                                color: Config.fg
                                opacity: row.usable ? 1 : 0.45
                                font.family: Config.fontFamily
                                font.pixelSize: Config.fontSize
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.separator && row.modelData && row.modelData.hasChildren
                            text: "›"
                            color: Config.fg
                            opacity: 0.6
                            font.family: Config.fontFamily
                            font.pixelSize: Config.fontSize
                        }
                    }
                }
            }
        }
    }
}
