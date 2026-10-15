import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
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
// State arrives as properties and leaves as signals. Nothing here calls
// PAM, nothing here runs a power command, and nothing here can unlock
// anything.
//
// The arrangement is DankMaterialShell's stock one: the clock top-centre,
// the date top-left, the status row top-right, the avatar and password field
// dead centre with what arrived while you were away underneath, and power
// bottom-left. The drawing is pshell's -- flat filled cards at
// Style.cornerRadius on the lock.* tokens, not DMS's pills.
Item {
    id: root

    property string authState: "idle"   // idle | checking | failed
    property string message: ""
    property string notice: ""
    property int attempts: 0
    property string keyboardLayout: ""
    property bool capsLock: false
    // Draws the badge, and nothing else. The stub auth lives in the service.
    property bool preview: false

    signal submitted(string password)
    signal edited
    signal powerRequested(string id)
    signal layoutClicked

    // The gap every corner element keeps to the screen edge.
    readonly property int edge: Math.round(Style.spacing.huge * 2.5)

    function focusField() {
        field.take();
    }

    function clearField() {
        field.clear();
    }

    // A rejected attempt empties the field, the way hyprlock's does, and
    // shakes it, the way DMS's does. Leaving the old text there invites a
    // second Enter on the same wrong password, and makes it ambiguous whether
    // the failure belongs to what is on screen or to the try before it.
    onAuthStateChanged: {
        if (root.authState === "failed") {
            root.clearField();
            field.shake();
        }
    }

    // Restart, power off: the power menu's policy says these ask first, and
    // from a lockscreen more than anywhere -- whoever pressed it has not
    // said who they are. Suspend loses nothing and goes straight through.
    function requestPower(id) {
        const action = PowerMenu.actionFor(id);
        if (action && action.confirms) {
            confirm.pendingId = id;
            confirm.message = action.question;
            // Cancel, not Confirm, for the control centre's reason: Return
            // on a destructive question should not be the thing that does it.
            confirm.selectedIndex = 0;
            confirm.opened = true;
            confirmKeys.forceActiveFocus();
            return;
        }
        root.powerRequested(id);
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

    // DMS's lockDate: top-left, on its own, at the size of a heading rather
    // than the clock's -- it answers a second question, not the first.
    Text {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.edge
        anchors.leftMargin: root.edge
        // Lined up with the status card's text on the other side, which sits
        // inside a card and so starts lower than the card's own edge.
        height: status.height
        verticalAlignment: Text.AlignVCenter

        visible: Config.lock.showClock
        text: Qt.formatDateTime(clock.date, Config.lock.dateFormat)
        color: Commons.Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
    }

    // The largest thing on the screen, and the only one readable from
    // across a room, which is the whole job of a lockscreen clock. DMS puts
    // it top-centre, clear of the field, so the time and the prompt never
    // compete for the middle.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(parent.height * 0.1)

        visible: Config.lock.showClock
        text: Qt.formatDateTime(clock.date, Config.lock.clockFormat)
        color: Commons.Color.lock.text
        font.family: Style.font.family
        // Derived from the token rather than fixed, so it still tracks a
        // changed base font size.
        font.pixelSize: Style.font.displayLarge * 4
        font.bold: true
    }

    LockStatus {
        id: status

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.edge
        anchors.rightMargin: root.edge

        visible: Config.lock.showStatus && implicitWidth > 0
        keyboardLayout: root.keyboardLayout
        showMedia: Config.lock.showMedia

        onLayoutClicked: root.layoutClicked()
    }

    LockField {
        id: field

        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - root.edge * 2)

        showAvatar: Config.lock.showAvatar
        // The preview says so in the field itself, not only on a badge in
        // the corner. It refuses every password, including the right one,
        // and a preview that looks exactly like the real lock while
        // rejecting your actual password is indistinguishable from a
        // lockscreen that is broken.
        placeholder: root.preview ? "Preview - passwords are not checked" : Config.lock.placeholder
        busy: root.authState === "checking"
        failed: root.authState === "failed"
        capsLock: root.capsLock

        // Whatever PAM said, with an attempt count the way hyprlock's
        // `$FAIL ($ATTEMPTS)` does, because "wrong password" on its own
        // does not tell you whether the last three tries registered at all.
        message: root.message !== "" ? (root.attempts > 1 ? root.message + " (" + root.attempts + ")" : root.message) : root.notice
        messageIsError: root.message !== ""

        onSubmitted: password => root.submitted(password)
        onEdited: root.edited()
    }

    // Under the field, past the room its feedback lines need, so a failure
    // message appearing never lands on top of the count.
    LockNotifications {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: field.bottom
        anchors.topMargin: Math.round(Style.font.body * 7)

        mode: Config.lock.notifications
    }

    LockPower {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.edge
        anchors.bottomMargin: root.edge

        visible: Config.lock.showPower
        onRequested: id => root.requestPower(id)
    }

    // Unmissable, and deliberately ugly. A preview screenshot must never be
    // mistakable for a real lock in a bug report.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.edge

        visible: root.preview
        width: badge.implicitWidth + Style.spacing.huge * 2
        height: badge.implicitHeight + Style.spacing.xxl
        radius: Style.cornerRadius
        color: Commons.Color.lock.textError

        Text {
            id: badge

            anchors.centerIn: parent
            text: "PREVIEW - Esc to close"
            color: Commons.Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }
    }

    // Takes the keyboard while the dialog is up, so Left/Right and Return
    // move between its buttons instead of typing into the field behind it.
    Item {
        id: confirmKeys

        Keys.onPressed: event => {
            if (confirm.handleKey(event))
                event.accepted = true;
        }
    }

    ConfirmDialog {
        id: confirm

        property string pendingId: ""

        anchors.fill: parent
        confirmText: "Yes"
        background: Commons.Color.background
        foreground: Commons.Color.lock.text

        onCanceled: {
            confirm.opened = false;
            root.focusField();
        }
        onConfirmed: {
            confirm.opened = false;
            root.powerRequested(confirm.pendingId);
            root.focusField();
        }
    }
}
