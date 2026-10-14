import QtQuick
import qs.Services
// Qualified as well, for the singleton -- Toast.qml explains the collision
// with this directory's own Notifications type.
import qs.Services as Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Services/NotificationHistory.js" as History

// One history entry in the panel: icon, app, summary, body, a relative
// timestamp, and action buttons for as long as the notification behind the
// record is still alive to invoke them.
Item {
    id: row

    // A plain history record, never the live notification -- records
    // outlive their notification and half of these rows describe ones that
    // are long gone.
    property var record: ({})
    // Injected by the panel, which ticks it while open, so fifty rows share
    // one clock instead of holding fifty timers.
    property real now: Date.now()

    // The live notification behind this record, when there still is one.
    // Only records from this session can have one: server ids restart with
    // the shell, so an id match against last week's record would pick up
    // whatever notification happens to wear that number now.
    readonly property var liveN: record && record.time >= Services.Notifications.sessionStart ? Services.Notifications.liveById(record.id) : null

    readonly property string iconSource: {
        const fromApp = Icons.fromEntry(record ? record.appIcon : "");
        if (fromApp !== "")
            return fromApp;
        return Icons.path(record ? record.desktopEntry : "");
    }

    implicitHeight: content.implicitHeight + Style.spacing.md

    Row {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.md

        Image {
            id: icon

            width: Style.space(24)
            height: Style.space(24)
            visible: row.iconSource !== ""
            source: row.iconSource
            sourceSize.width: Style.space(24)
            sourceSize.height: Style.space(24)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Column {
            width: parent.width - (icon.visible ? icon.width + parent.spacing : 0)
            spacing: Style.spacing.xxs

            Item {
                width: parent.width
                height: appLabel.implicitHeight

                Text {
                    id: appLabel

                    anchors.left: parent.left
                    anchors.right: timeLabel.left
                    anchors.rightMargin: Style.spacing.md
                    text: row.record ? row.record.appName : ""
                    color: Commons.Color.muted
                    elide: Text.ElideRight
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }

                Text {
                    id: timeLabel

                    anchors.right: parent.right
                    text: row.record ? History.relativeTime(row.record.time, row.now) : ""
                    color: Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: row.record ? row.record.summary : ""
                color: Commons.Color.popups.text
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: row.record ? row.record.body : ""
                color: Commons.Color.muted
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                linkColor: Commons.Color.accent
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Row {
                visible: row.liveN !== null && row.liveN.actions.length > 0
                spacing: Style.spacing.sm

                Repeater {
                    model: row.liveN ? row.liveN.actions : []

                    Button {
                        required property var modelData

                        text: modelData.text !== "" ? modelData.text : modelData.identifier
                        fontSize: Style.font.caption
                        bordered: true
                        foreground: Commons.Color.popups.text
                        onClicked: Services.Notifications.invokeAction(row.liveN, modelData)
                    }
                }
            }
        }
    }
}
