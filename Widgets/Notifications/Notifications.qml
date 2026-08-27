import QtQuick
import qs.Services
// Qualified as well, for the singleton -- this file is itself the sibling
// named Notifications that shadows it. Toast.qml explains the collision.
import qs.Services as Services
import qs.Commons
import qs.Ui
import "../../Services/NotificationHistory.js" as History

// The bar's bell and the history panel behind it. The view half only, like
// the idle inhibitor's widget: the server, the history, DND and even
// whether this panel is open live in Services/Notifications.qml, because
// this widget exists once per monitor and the panel must not.
//
// No ipcTarget and manageIpc off: pshell.notifications is registered by the
// service, which holds the wanted-open state -- a second handler here would
// fight it over the same name, once per monitor. The lifecycle functions
// are overridden to route through the service instead, so the panel opens
// on whichever monitor's bell was clicked and IPC opens it on the focused
// one, and both agree afterwards.
Panel {
    id: root

    moduleName: "pshell.notifications"
    manageIpc: false

    property var cfg: ({})

    readonly property string screenName: bar && bar.screen ? bar.screen.name : ""
    // Only the widget on the service's chosen screen raises the panel;
    // every other monitor's widget stays a bell. Without the host check,
    // one `toggle` opened a panel per monitor and the popout coordinator
    // closed them against each other.
    readonly property bool hostsPanel: Services.Notifications.panelOpen && Services.Notifications.panelScreen === root.screenName

    function open() {
        Services.Notifications.openPanel(root.screenName);
    }

    function close() {
        Services.Notifications.closePanel();
    }

    function toggle() {
        Services.Notifications.togglePanel(root.screenName);
    }

    readonly property int unread: Services.Notifications.unreadCount
    readonly property var groups: History.groupByApp(Services.Notifications.history)

    // Which groups are folded out, by app key. Per-widget state on purpose:
    // what you have unfolded on one monitor's panel is browsing state, not
    // notification state.
    property var expandedKeys: ({})

    function toggleGroup(key) {
        const next = Object.assign({}, expandedKeys);
        if (next[key])
            delete next[key];
        else
            next[key] = true;
        expandedKeys = next;
    }

    // The clock the relative timestamps read. Ticking only while the panel
    // is up: a hidden panel does not need to know it is a minute older.
    property real now: Date.now()

    Timer {
        interval: 30000
        repeat: true
        running: root.hostsPanel
        onTriggered: root.now = Date.now()
    }

    onHostsPanelChanged: if (hostsPanel)
        root.now = Date.now()

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        // The struck-out bell wins over the ringing one: "you asked for
        // silence" matters more than "there is something waiting", and the
        // count label still says the second thing.
        iconName: Services.Notifications.dnd ? Glyphs.notificationsOff : (root.unread > 0 ? Glyphs.notificationsActive : Glyphs.notifications)
        iconColor: root.unread > 0 && !Services.Notifications.dnd ? Color.accent : Color.foreground
        label: root.unread > 0 && !vertical ? String(root.unread) : ""

        onPressed: b => {
            // Right-click flips DND without opening anything, the same
            // shortcut shape as the battery's percent toggle.
            if (b === Qt.RightButton) {
                Services.Notifications.setDnd("toggle");
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
        open: root.hostsPanel
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth((root.cfg.panelWidth || 400) + panel.horizontalContentInset)
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
                spacing: Style.spacing.lg

                Toggle {
                    width: parent.width
                    label: "Do not disturb"
                    description: "Toasts stop; history still records everything"
                    checked: Services.Notifications.dnd
                    onClicked: Services.Notifications.setDnd("toggle")
                }

                Button {
                    text: "Clear all"
                    bordered: true
                    visible: root.groups.length > 0
                    fontSize: Style.font.bodySmall
                    foreground: Color.popups.text
                    onClicked: Services.Notifications.clearHistory()
                }

                PanelSeparator {}

                // A sentence, not a blank panel -- the wallpaper grid's
                // rule. Without it an empty history looks like the panel is
                // broken rather than the machine being quiet.
                Text {
                    width: parent.width
                    visible: root.groups.length === 0
                    text: "No notifications. New ones land here as they arrive."
                    color: Color.muted
                    wrapMode: Text.WordWrap
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                Flickable {
                    width: parent.width
                    height: Math.min(Style.space(440), groupColumn.implicitHeight)
                    visible: root.groups.length > 0
                    contentWidth: width
                    contentHeight: groupColumn.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: groupColumn

                        width: parent.width
                        spacing: Style.spacing.md

                        Repeater {
                            model: root.groups

                            Column {
                                id: group

                                required property var modelData

                                readonly property bool expanded: root.expandedKeys[modelData.key] === true

                                width: groupColumn.width
                                spacing: Style.spacing.sm

                                Item {
                                    width: parent.width
                                    height: Style.space(30)

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.spacing.md

                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: Glyphs.expandMore
                                            size: Style.font.body
                                            color: Color.muted
                                            // Pointing right while folded, down while open --
                                            // the file-manager convention, animated because it
                                            // is a state change.
                                            rotation: group.expanded ? 0 : -90

                                            Behavior on rotation {
                                                NumberAnimation {
                                                    duration: 100
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: group.modelData.appName + "  (" + group.modelData.entries.length + ")"
                                            color: Color.popups.text
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.body
                                            font.bold: true
                                        }
                                    }

                                    Button {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Clear"
                                        fontSize: Style.font.caption
                                        foreground: Color.muted
                                        onClicked: Services.Notifications.clearApp(group.modelData.key)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        // Stops short of the Clear button so it keeps its
                                        // own click.
                                        anchors.rightMargin: Style.space(70)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleGroup(group.modelData.key)
                                    }
                                }

                                Column {
                                    width: parent.width
                                    visible: group.expanded
                                    spacing: Style.spacing.sm

                                    Repeater {
                                        model: group.expanded ? group.modelData.entries : []

                                        NotificationRow {
                                            required property var modelData

                                            width: parent.width
                                            record: modelData
                                            now: root.now
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
