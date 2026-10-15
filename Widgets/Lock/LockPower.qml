import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Services
import qs.Ui

// Suspend, restart and power off, in the bottom-left corner where DMS keeps
// its power button.
//
// Three keys rather than DMS's one-button menu: a menu is a second click and
// a popup to dismiss, for a row that only ever has these three in it. Lock
// and log out are left out -- the first is what is already on screen, and
// the second would end the session from a screen that has not asked who you
// are.
//
// The actions and their icons are the power menu's, so the lock cannot come
// to disagree with it about what "restart" runs. Whether one asks first is
// its policy too; the asking itself happens in LockContent, which owns the
// dialog.
Row {
    id: root

    readonly property var ids: ["suspend", "reboot", "poweroff"]
    readonly property int keySize: Math.round(Style.font.body * 3.4)

    // Which key the pointer is on, named beside the row. A tooltip would
    // need a popup window, and a lock surface is not somewhere to open one.
    property string hovered: ""

    signal requested(string id)

    spacing: Style.spacing.lg

    Repeater {
        model: root.ids

        Rectangle {
            id: key

            required property string modelData
            readonly property var action: PowerMenu.actionFor(modelData)
            // The ones that end something go red under the pointer, the way
            // the power menu draws them in the urgent colour.
            readonly property bool destructive: action !== null && action.confirms

            width: root.keySize
            height: root.keySize
            radius: Style.cornerRadius
            color: hover.containsMouse ? Util.alpha(key.destructive ? Commons.Color.lock.textError : Commons.Color.lock.text, 0.22) : Commons.Color.lock.background

            Behavior on color {
                ColorAnimation {
                    duration: 100
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                name: key.action ? key.action.icon : ""
                size: Style.font.iconLarge
                color: hover.containsMouse && key.destructive ? Commons.Color.lock.textError : Commons.Color.lock.text
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requested(key.modelData)
                onContainsMouseChanged: {
                    if (containsMouse)
                        root.hovered = key.action ? key.action.label : "";
                    else if (root.hovered === (key.action ? key.action.label : ""))
                        root.hovered = "";
                }
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: Style.spacing.sm
        text: root.hovered
        color: Commons.Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
    }
}
