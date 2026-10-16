import QtQuick
import Quickshell.Services.Notifications
import qs.Services
// Qualified as well, for the singleton: once this directory gained a sibling
// named Notifications -- the bar widget -- the unqualified name resolves to
// that sibling, not to qs.Services' singleton. The same collision shell.qml
// records for Wallpaper, answered the same way.
import qs.Services as Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Services/NotificationMarkup.js" as Markup

// One notification in the toast stack. The view half only: whether this
// toast is up, and for how long, is Services/Notifications.qml's call --
// this file renders the notification it was handed and reports hover so the
// service can hold the countdown.
//
// Designed as a ListView delegate over the tracked model, which is why
// "gone" is a zero height rather than not existing: a tracked notification
// whose toast has timed out keeps its delegate, collapsed, so the stack
// animates closed instead of snapping and the remaining toasts slide rather
// than jump.
Item {
    id: toast

    property var notification: null

    // Where this notification sits in the popup list, newest first. Not a
    // popup at all is -1; past maxVisible is on screen only as part of the
    // "+N more" count the stack draws.
    readonly property int popupSlot: notification ? Services.Notifications.popupIds.indexOf(notification.id) : -1
    readonly property bool shown: popupSlot >= 0 && popupSlot < Config.notifications.maxVisible

    readonly property bool critical: notification !== null && notification.urgency === NotificationUrgency.Critical
    readonly property bool low: notification !== null && notification.urgency === NotificationUrgency.Low

    // The notification's own picture first -- an album cover, a contact
    // photo -- then the application's icon through the icon theme, then the
    // desktop entry's icon, then nothing. `image` is an image:// provider
    // URL that Image loads directly; the other two are names or paths and
    // go through Icons so a missing name comes back empty instead of as the
    // provider's magenta placeholder.
    readonly property string iconSource: {
        if (!notification)
            return "";
        if (notification.image !== "")
            return notification.image;
        const fromApp = Icons.fromEntry(notification.appIcon);
        if (fromApp !== "")
            return fromApp;
        return Icons.path(notification.desktopEntry);
    }

    // Buttons for everything except "default", which is what clicking the
    // toast body invokes and would be a redundant button.
    readonly property var buttonActions: notification ? notification.actions.filter(a => a.identifier !== "default") : []

    // Enter and leave are the same 400ms/InOutQuad the wallpaper crossfade
    // uses -- no better reason for a different figure. Height and opacity
    // together: opacity alone leaves a hole in the stack, height alone
    // slides a fully-lit card under its neighbour.
    implicitHeight: shown && loader.item ? loader.item.implicitHeight + Style.spacing.md : 0
    height: implicitHeight
    visible: height > 0
    clip: true
    opacity: shown ? 1 : 0

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }

    // Content exists only while the toast shows or is still animating away.
    // The stack's delegate list is every tracked notification -- most of
    // them long past their toast -- and building cards for all of them
    // would spend real memory on invisible things.
    Loader {
        id: loader

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        active: toast.shown || toast.height > 0

        sourceComponent: BorderSurface {
            id: card

            implicitHeight: content.implicitHeight + Style.spacing.lg * 2
            radius: Style.cornerRadius
            color: Commons.Color.popups.background
            // Urgency wears the border: critical is the bar's urgent
            // colour, everything else the popup chrome every panel uses.
            borderSpec: toast.critical ? Border.flat(Commons.Color.urgent, 2) : Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.spacing.hairline))

            // Under the interactive children, so buttons and the reply
            // field take their clicks first and this sees the rest.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: mouse => {
                    const n = toast.notification;
                    if (!n)
                        return;
                    if (mouse.button === Qt.MiddleButton) {
                        n.dismiss();
                        return;
                    }
                    // Left click: the spec's "default" action when the
                    // sender declared one, otherwise the click means "seen
                    // it, go away".
                    const def = Services.Notifications.defaultActionOf(n);
                    if (def)
                        Services.Notifications.invokeAction(n, def);
                    else
                        n.dismiss();
                }
            }

            // Reading a notification should not race its countdown; the
            // hold lives in the service so this toast's twin on another
            // monitor pauses with it.
            HoverHandler {
                onHoveredChanged: {
                    const n = toast.notification;
                    if (!n)
                        return;
                    if (hovered)
                        Services.Notifications.holdPopup(n.id);
                    else
                        Services.Notifications.resumePopup(n.id);
                }
            }

            Column {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.lg
                spacing: Style.spacing.md

                Row {
                    width: parent.width
                    spacing: Style.spacing.lg

                    Image {
                        id: icon

                        width: Style.space(36)
                        height: Style.space(36)
                        visible: toast.iconSource !== ""
                        source: toast.iconSource
                        sourceSize.width: Style.space(36)
                        sourceSize.height: Style.space(36)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Column {
                        width: parent.width - (icon.visible ? icon.width + parent.spacing : 0)
                        spacing: Style.spacing.xs

                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: toast.notification ? toast.notification.appName : ""
                            color: Commons.Color.muted
                            elide: Text.ElideRight
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: toast.notification ? toast.notification.summary : ""
                            // Low urgency reads quieter than normal; the
                            // body below is muted for everyone already.
                            color: toast.low ? Commons.Color.muted : Commons.Color.popups.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            // Sanitised first: StyledText would otherwise
                            // fetch any <img src> a sender embeds --
                            // NotificationMarkup.js has the why.
                            text: toast.notification ? Markup.sanitize(toast.notification.body) : ""
                            color: Commons.Color.muted
                            // StyledText is the markup the server
                            // advertises: bold, italic, underline and
                            // clickable links, without RichText's appetite
                            // for arbitrary HTML.
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            linkColor: Commons.Color.accent
                            // Sanitize already drops other schemes; checked
                            // again here because this is the line that acts.
                            onLinkActivated: link => {
                                if (Markup.isSafeLink(link))
                                    Qt.openUrlExternally(link);
                            }
                        }
                    }
                }

                Row {
                    visible: toast.buttonActions.length > 0
                    spacing: Style.spacing.md

                    Repeater {
                        model: toast.buttonActions

                        Button {
                            required property var modelData

                            text: modelData.text !== "" ? modelData.text : modelData.identifier
                            fontSize: Style.font.bodySmall
                            bordered: true
                            foreground: Commons.Color.popups.text
                            onClicked: Services.Notifications.invokeAction(toast.notification, modelData)
                        }
                    }
                }

                TextField {
                    width: parent.width
                    visible: toast.notification && toast.notification.hasInlineReply
                    placeholderText: toast.notification && toast.notification.inlineReplyPlaceholder !== "" ? toast.notification.inlineReplyPlaceholder : "Reply"
                    onAccepted: {
                        const n = toast.notification;
                        if (!n || text === "")
                            return;
                        n.sendInlineReply(text);
                        // Replied is dealt with, same rule as an invoked
                        // action: gone unless the sender asked to stay.
                        if (!n.resident)
                            n.dismiss();
                    }
                }
            }
        }
    }
}
