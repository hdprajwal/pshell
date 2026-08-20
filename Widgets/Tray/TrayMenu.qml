import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The menu a tray icon opens on right click, drawn by qsbar rather than
// handed to QsMenuAnchor, so it picks up the bar's colours and font.
//
// Submenus drill in and out in place instead of flying out sideways. A
// flyout has to guess which way it can grow without leaving the screen;
// drilling in never has that problem.
//
// A tray menu is a menu, not a panel: built on PopupCard like every other
// popup, but coloured from Color.menu.* rather than Color.popups.*.
PopupCard {
    id: popup

    property var trayItem: null
    // Null until an icon is right-clicked; PopupCard falls back on its own
    // when it has nothing to anchor against.
    property Item activeAnchor: null
    // Width of whichever tray icon owns the open menu, so the bar's
    // open-panel mark can underline just that icon instead of the whole row.
    readonly property real activeAnchorWidth: popup.open && popup.activeAnchor ? popup.activeAnchor.width : 0

    readonly property int rowHeight: Math.round(Style.font.body * 2.2)
    readonly property int menuWidth: Style.space(230)
    readonly property int maxHeight: Style.space(460)

    anchorItem: popup.activeAnchor
    padding: Style.spacing.popupPadding
    backgroundColor: Color.menu.background
    borderColor: Color.menu.border
    contentWidth: popup.fittedContentWidth(popup.menuWidth)
    contentHeight: popup.fittedContentHeight(column.implicitHeight, popup.maxHeight)

    function openFor(item, anchor) {
        const reopening = popup.open && popup.activeAnchor === anchor;
        popup.trayItem = item;
        if (!reopening)
            stack.clear();
        if (reopening) {
            popup.close();
            return;
        }
        popup.activeAnchor = anchor || null;
        popup.open = true;
    }

    // The card fades out over 140ms (PopupCard keeps `visible` true for that
    // whole time), so resetting on close would swap the root menu in for a
    // live submenu mid-fade: a visible flash, and a resize if the two have
    // different geometry. Wait for the fade to actually finish.
    onVisibleChanged: if (!popup.visible) {
        popup.trayItem = null;
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

    // Named properties rather than default children: the default property is
    // the card's content item list, which takes Items only.
    property ListModel stack: ListModel {
        id: stack
    }

    property QsMenuOpener rootOpener: QsMenuOpener {
        id: rootOpener
        menu: popup.trayItem ? popup.trayItem.menu : null
    }

    property QsMenuOpener subOpener: QsMenuOpener {
        id: subOpener
        menu: popup.topHandle()
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: popup.menuWidth
            spacing: 1

            // Header doubles as the way back out of a submenu.
            Item {
                width: popup.menuWidth
                height: popup.rowHeight
                visible: stack.count > 0

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹  " + (stack.count > 0 ? stack.get(stack.count - 1).label : "")
                    color: Color.menu.text
                    opacity: 0.7
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.goBack()
                }
            }

            Rectangle {
                width: popup.menuWidth
                height: 1
                visible: stack.count > 0
                color: Util.alpha(Color.menu.border, 0.5)
            }

            Repeater {
                model: stack.count > 0 ? subOpener.children : rootOpener.children

                Rectangle {
                    id: row

                    required property var modelData
                    readonly property bool separator: modelData ? modelData.isSeparator : false
                    readonly property bool usable: modelData && !separator && modelData.enabled !== false

                    width: popup.menuWidth
                    height: separator ? 1 : popup.rowHeight
                    radius: separator ? 0 : Math.max(2, Style.cornerRadius)
                    color: {
                        if (separator)
                            return Util.alpha(Color.menu.border, 0.5);
                        return hover.containsMouse && usable ? Color.menu.selectedBackground : "transparent";
                    }
                    border.width: !separator && hover.containsMouse && usable ? Style.spacing.hairline : 0
                    border.color: Color.menu.selectedBorder

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
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        visible: !row.separator

                        // Checkbox for a toggle, circle for a radio.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Style.font.body
                            height: Style.font.body
                            visible: row.modelData && row.modelData.buttonType !== undefined && row.modelData.buttonType !== 0
                            radius: row.modelData && row.modelData.buttonType === 2 ? width / 2 : 2
                            color: "transparent"
                            border.width: 1
                            border.color: Util.alpha(Color.menu.text, 0.4)

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 6
                                height: parent.height - 6
                                radius: parent.radius > 2 ? parent.radius - 3 : 1
                                color: Color.menu.selectedText
                                visible: row.modelData && row.modelData.checkState === 2
                            }
                        }

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Style.font.body
                            height: Style.font.body
                            visible: row.modelData && (row.modelData.icon || "") !== ""
                            source: row.modelData ? (row.modelData.icon || "") : ""
                            sourceSize.width: Style.font.body
                            sourceSize.height: Style.font.body
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData ? (row.modelData.text || "") : ""
                            color: hover.containsMouse && row.usable ? Color.menu.selectedText : Color.menu.text
                            opacity: row.usable ? 1 : 0.45
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.separator && row.modelData && row.modelData.hasChildren
                        text: "›"
                        color: Color.menu.text
                        opacity: 0.6
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }
            }
        }
    }
}
