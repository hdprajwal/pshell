import QtQuick
import qs.Services
// Qualified for the collision this file is one half of: qs.Services exports a
// PowerMenu too -- the singleton -- and a directory's own types win the
// unqualified name, so `PowerMenu` here would mean this widget. The same
// answer Widgets/Weather and Widgets/Notifications give.
import qs.Services as Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar's power button and the five session actions behind it.
//
// The view half only. What each action runs, which of them confirm, and the
// panel's wanted-open state all live in Services/PowerMenu.qml, because this
// widget exists once per monitor and neither the menu nor the answer to
// "what does log out run" may.
//
// No ipcTarget and manageIpc off: pshell.power is registered by the service,
// which is where lock/logout/suspend/reboot/poweroff have to live anyway. A
// second handler here would fight it over the same name, once per monitor.
Panel {
    id: root

    moduleName: "pshell.power"
    manageIpc: false

    property var cfg: ({})

    readonly property int panelWidth: cfg.panelWidth || Style.space(220)

    readonly property string screenName: bar && bar.screen ? bar.screen.name : ""
    readonly property bool hostsPanel: Services.PowerMenu.panelOpen && Services.PowerMenu.panelScreen === root.screenName

    function open() {
        Services.PowerMenu.openPanel(root.screenName);
    }

    function close() {
        Services.PowerMenu.closePanel();
    }

    function toggle() {
        Services.PowerMenu.togglePanel(root.screenName);
    }

    readonly property var actions: Services.PowerMenu.actions

    // Which row the keyboard is on, and whether the keyboard has been used at
    // all. Battery's model: no row is lit until an arrow is pressed, so the
    // panel does not open with a highlight sitting on something you did not
    // ask for.
    property int cursorIndex: 0
    property bool cursorActive: false

    // What the dialog is holding, while it is open.
    property string pendingId: ""

    function moveCursor(delta) {
        if (delta === 0 || root.actions.length === 0)
            return;
        root.cursorActive = true;
        root.cursorIndex = (root.cursorIndex + delta + root.actions.length) % root.actions.length;
    }

    // The confirmation lives here rather than in the service: the service is
    // asked the same question by a script, which must not be shown a dialog.
    // What confirms is still the service's call -- this only draws it.
    function activate(id) {
        const action = Services.PowerMenu.actionFor(id);
        if (!action)
            return;
        if (action.confirms) {
            root.pendingId = id;
            confirm.message = action.question;
            // Cancel, not Confirm. The dialog defaults to its right-hand
            // button, which on a destructive question means Return powers the
            // machine off without anyone reading the sentence.
            confirm.selectedIndex = 0;
            confirm.opened = true;
            Qt.callLater(function () {
                if (confirm.opened)
                    confirm.forceActiveFocus();
            });
            return;
        }
        Services.PowerMenu.invoke(id);
        root.close();
    }

    function activateCursor() {
        if (!root.cursorActive || root.cursorIndex < 0 || root.cursorIndex >= root.actions.length)
            return;
        root.activate(root.actions[root.cursorIndex].id);
    }

    onHostsPanelChanged: {
        if (!root.hostsPanel) {
            confirm.opened = false;
            root.cursorActive = false;
            root.cursorIndex = 0;
        }
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        iconName: Glyphs.powerOff
        tooltipText: "Session"

        onPressed: b => {
            if (b === Qt.LeftButton)
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
        contentWidth: panel.fittedContentWidth(root.panelWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            // The dialog wants Left/Right and Return for its two buttons, not
            // this panel's cursor movement -- the same rule the panels with a
            // search field follow.
            blocked: confirm.opened
            onMoveRequested: (dx, dy) => root.moveCursor(dy !== 0 ? dy : dx)
            onActivateRequested: root.activateCursor()
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.sm

                Repeater {
                    model: root.actions

                    // A row rather than a Ui/Button: Button draws its icon in
                    // the button's own text font, and these are Material
                    // Symbols, which that font does not have. CursorSurface is
                    // the kit's shared keyboard-cursor chrome, so the row
                    // still lights the way every other panel row does.
                    CursorSurface {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        implicitHeight: Math.round(Style.font.body * 2.4)
                        foreground: Commons.Color.popups.text
                        hasCursor: root.cursorActive && root.cursorIndex === index

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: row.borderLeft + Style.spacing.rowPaddingX
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.spacing.lg

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: row.modelData.icon
                                size: Style.font.icon
                                // Red on the three that end something, so the
                                // destructive half of the menu is obvious
                                // before the dialog says it in words.
                                color: row.modelData.confirms ? Commons.Color.urgent : Commons.Color.popups.text
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.label
                                color: Commons.Color.popups.text
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                root.cursorActive = true;
                                root.cursorIndex = row.index;
                            }
                            onClicked: root.activate(row.modelData.id)
                        }
                    }
                }
            }

            // Declared after the Column so it stacks above it, and outside it
            // so the Column does not lay it out as one more row.
            ConfirmDialog {
                id: confirm

                anchors.fill: parent
                background: Commons.Color.popups.background
                foreground: Commons.Color.popups.text
                confirmText: Services.PowerMenu.actionFor(root.pendingId) ? Services.PowerMenu.actionFor(root.pendingId).label : "Confirm"

                Keys.onPressed: function (event) {
                    if (confirm.handleKey(event))
                        event.accepted = true;
                }

                onCanceled: {
                    confirm.opened = false;
                    keyCatcher.forceActiveFocus();
                }

                onConfirmed: {
                    confirm.opened = false;
                    Services.PowerMenu.invoke(root.pendingId);
                    root.close();
                }
            }
        }
    }
}
