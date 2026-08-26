import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Ui

// Everything drawn on a locked screen, and nothing that knows how to unlock
// one.
//
// This is the piece the real lock surface and `pshell.lock preview` both
// instantiate. That is the whole point of it existing separately: a preview
// that rendered its own copy of this layout would drift from the real one,
// and the first time you noticed would be while locked out.
//
// State arrives as properties and leaves as `submitted`. Nothing here calls
// PAM, and nothing here can unlock anything.
Item {
    id: root

    property string authState: "idle"   // idle | checking | failed
    property string message: ""
    property int attempts: 0
    property string keyboardLayout: ""
    property bool capsLock: false
    // Draws the badge, and nothing else. The stub auth lives in the service.
    property bool preview: false

    signal submitted(string password)
    signal edited

    function focusField() {
        field.take();
    }

    function clearField() {
        field.clear();
    }

    // Minutes, not seconds: a ticking seconds field on a lockscreen wakes
    // the GPU once a second for a digit nobody is reading.
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    LockBackground {
        anchors.fill: parent
    }

    LockStatus {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.spacing.huge * 2
        anchors.rightMargin: Style.spacing.huge * 2

        visible: Config.lock.showStatus
        keyboardLayout: root.keyboardLayout
    }

    // The centred column. Every part is optional, and Column leaves
    // invisible children out of its layout, so switching all of them off
    // collapses this to Omarchy's bare centred field rather than to a field
    // floating below a stack of gaps.
    Column {
        anchors.centerIn: parent
        spacing: Style.spacing.huge

        LockAvatar {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: Config.lock.showAvatar && User.hasAvatar
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: Config.lock.showAvatar && text !== ""
            text: User.displayName
            color: Color.lock.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: Config.lock.showClock
            text: Qt.formatDateTime(clock.date, Config.lock.clockFormat)
            color: Color.lock.text
            font.family: Style.font.family
            // The largest thing on the screen, and the only one readable
            // from across a room -- which is the whole job of a lockscreen
            // clock. Derived from the token rather than fixed so it still
            // tracks a changed base font size.
            font.pixelSize: Style.font.displayLarge * 2
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: Config.lock.showClock
            text: Qt.formatDateTime(clock.date, Config.lock.dateFormat)
            color: Color.lock.placeholder
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }

        LockField {
            id: field

            anchors.horizontalCenter: parent.horizontalCenter

            placeholder: Config.lock.placeholder
            busy: root.authState === "checking"
            failed: root.authState === "failed"
            capsLock: root.capsLock

            onSubmitted: password => root.submitted(password)
            onEdited: root.edited()
        }

        // Whatever PAM said, rather than something invented here. An
        // attempt count is appended the way hyprlock's `$FAIL ($ATTEMPTS)`
        // does, because "wrong password" on its own does not tell you
        // whether the last three tries registered at all.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            visible: root.message !== ""
            text: root.attempts > 1 ? root.message + " (" + root.attempts + ")" : root.message
            color: Color.lock.textError
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
    }

    // Unmissable, and deliberately ugly. A preview screenshot must never be
    // mistakable for a real lock in a bug report.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.huge * 2

        visible: root.preview
        width: badge.implicitWidth + Style.spacing.huge * 2
        height: badge.implicitHeight + Style.spacing.xxl
        radius: Style.cornerRadius
        color: Color.lock.textError

        Text {
            id: badge

            anchors.centerIn: parent
            text: "PREVIEW - Esc to close"
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }
    }
}
