import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Services
import qs.Ui
import "../../Services/NotificationHistory.js" as History

// What arrived while you were away, under the password field where DMS puts
// it.
//
// "count" is DMS's default, one card with a bell and a number. "apps" is
// its chip row: one card per sending app, with that app's count. Neither
// ever shows a summary or a body -- the people who can see a lockscreen are
// by definition not the people allowed past it.
//
// The number is the bell's own unread count, so the lockscreen and the bar
// agree, and both reset the same way: by opening the notification panel
// once you are back in.
Item {
    id: root

    property string mode: "count"   // count | apps | off

    readonly property int count: Notifications.unreadCount
    // The unread ones are the newest `count` records of history, newest
    // first, so the head of the list is exactly what was missed.
    readonly property var groups: mode === "apps" && count > 0 ? History.groupByApp(Notifications.history.slice(0, count)) : []
    // Five chips and a "+N" card, past which a row of app names stops being
    // a glance and becomes a list.
    readonly property int chipLimit: 5

    implicitWidth: mode === "apps" ? chips.implicitWidth : pill.implicitWidth
    implicitHeight: Math.round(Style.font.body * 3)
    visible: mode !== "off" && count > 0

    LockCard {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.mode === "count"

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: Glyphs.notificationsActive
            filled: true
            size: Style.font.icon
            color: Commons.Color.lock.text
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.count === 1 ? "1 notification" : root.count + " notifications"
            color: Commons.Color.lock.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
        }
    }

    Row {
        id: chips

        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.mode === "apps"
        spacing: Style.spacing.lg

        Repeater {
            model: root.groups.slice(0, root.chipLimit)

            LockCard {
                id: chip

                required property var modelData
                readonly property var latest: modelData.entries[0]
                readonly property string iconSource: {
                    const fromApp = Icons.fromEntry(latest ? latest.appIcon : "");
                    return fromApp !== "" ? fromApp : Icons.path(latest ? latest.desktopEntry : "");
                }

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.font.icon
                    height: width
                    visible: chip.iconSource !== "" && status === Image.Ready
                    source: chip.iconSource
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // App names come from the sender, so shown as typed.
                    textFormat: Text.PlainText
                    text: chip.modelData.appName
                    color: Commons.Color.lock.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                // The count as a small bold muted caption rather than a
                // badge: a filled dot of accent on every chip would make the
                // row shout about nothing in particular.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chip.modelData.entries.length > 1
                    text: chip.modelData.entries.length
                    color: Commons.Color.lock.placeholder
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }
            }
        }

        LockCard {
            visible: root.groups.length > root.chipLimit

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (root.groups.length - root.chipLimit)
                color: Commons.Color.lock.placeholder
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }
        }
    }
}
