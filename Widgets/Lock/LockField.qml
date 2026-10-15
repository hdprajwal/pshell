import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Services
import qs.Ui

// The avatar and the password field beside it, with what PAM said and the
// Caps Lock warning hanging underneath.
//
// DMS's arrangement -- face on the left, field filling the rest, a lock
// symbol inside the field's leading edge and the reveal and submit keys at
// its trailing one -- drawn in pshell's language: one flat filled card at
// Style.cornerRadius instead of a pill, and a border that only appears when
// it has something to say.
//
// A bare TextInput rather than qs.Ui's TextField because the lock speaks a
// different visual language to the panels: TextField draws itself from
// Border.controlSpec, the kit's hover/focus/selected vocabulary, and none of
// those states mean anything on a surface with exactly one focusable thing.
// What the lock has instead is Omarchy's three: waiting, checking, wrong.
// Those are the Color.lock.border* tokens.
//
// State comes in as properties and leaves as signals. Nothing here writes
// its own inputs -- `failed` is cleared by whoever set it, told to do so by
// `edited()` -- because a component that assigns to a property its parent
// bound would silently break that binding the first time it did so.
Item {
    id: root

    property string placeholder: "Enter Password"
    // True while PAM has the password and has not answered yet. PAM takes
    // about a second to reject on purpose, and a field that looks identical
    // for that second reads as a dropped keystroke.
    property bool busy: false
    property bool failed: false
    property bool capsLock: false
    property bool showAvatar: true
    // Below the field: PAM's words on a failure, or a notice that is not one.
    property string message: ""
    property bool messageIsError: true

    readonly property int fieldHeight: Math.round(Style.font.body * 4.4)
    readonly property int rowWidth: Math.round(Style.font.body * 36)

    signal submitted(string password)
    signal edited

    // Guards `edited` while clearing. Without it, wiping the field after a
    // rejection looks exactly like the user typing over the error, so the
    // error the wipe was announcing would be erased in the same frame.
    property bool _clearing: false
    property bool _revealed: false

    function clear() {
        root._clearing = true;
        input.text = "";
        root._clearing = false;
    }

    function take() {
        input.forceActiveFocus();
    }

    // DMS's three-beat shake on a rejection. Motion says "no" where a
    // colour change alone is easy to miss on a screen you are not looking
    // at closely -- you are looking at your fingers.
    function shake() {
        root._revealed = false;
        shaker.restart();
    }

    implicitWidth: rowWidth
    // The feedback lines hang below the row without adding to the height, so
    // centring this item centres the field itself and a message appearing
    // never nudges the field up the screen.
    implicitHeight: fieldHeight

    Row {
        id: row

        width: parent.width
        height: root.fieldHeight
        spacing: Style.spacing.xxl

        transform: Translate {
            id: offset
        }

        LockAvatar {
            id: avatar

            anchors.verticalCenter: parent.verticalCenter
            visible: root.showAvatar
            diameter: root.fieldHeight
        }

        Rectangle {
            id: frame

            width: parent.width - (avatar.visible ? avatar.width + parent.spacing : 0)
            height: root.fieldHeight
            radius: Style.cornerRadius
            color: Commons.Color.lock.background

            // Wrong beats busy beats focused: a failure stays red while the
            // user starts typing over it, and only clears once the parent
            // says so. At rest there is no border at all -- a filled card
            // with an outline is a form control, and this is the one thing
            // on screen; it does not need fencing in.
            border.color: root.failed ? Commons.Color.lock.borderError : (root.busy ? Commons.Color.lock.borderActive : Util.alpha(Commons.Color.lock.borderActive, 0.55))
            border.width: root.failed || root.busy || input.activeFocus ? 2 : 0

            Behavior on border.color {
                ColorAnimation {
                    duration: 120
                }
            }

            MaterialIcon {
                id: lockGlyph

                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.huge
                anchors.verticalCenter: parent.verticalCenter
                name: Glyphs.lock
                filled: true
                size: Style.font.iconLarge
                color: root.failed ? Commons.Color.lock.textError : (root.busy || input.activeFocus ? Commons.Color.lock.borderActive : Commons.Color.lock.placeholder)
            }

            TextInput {
                id: input

                anchors.left: lockGlyph.right
                anchors.leftMargin: Style.spacing.xxl
                anchors.right: keys.left
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter

                // Read-only rather than disabled while checking: disabling
                // drops focus, and getting it back after a failed attempt
                // would need a round trip through the surface.
                readOnly: root.busy

                echoMode: root._revealed ? TextInput.Normal : TextInput.Password
                // Long enough to see you hit the right key, short enough that
                // a shoulder cannot read the word.
                passwordMaskDelay: 500

                color: Commons.Color.lock.text
                selectionColor: Commons.Color.lock.selection
                selectedTextColor: Commons.Color.lock.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.letterSpacing: root._revealed ? 0 : 2
                clip: true

                onAccepted: {
                    // Omarchy sets ignore_empty_input, and it is right to: an
                    // empty submit costs a real PAM round trip and a real
                    // failure delay for a keystroke that said nothing.
                    if (input.text !== "" && !root.busy)
                        root.submitted(input.text);
                }

                onTextChanged: {
                    if (!root._clearing)
                        root.edited();
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    visible: input.text === ""
                    text: root.busy ? "Checking..." : root.placeholder
                    color: Commons.Color.lock.placeholder
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    elide: Text.ElideRight
                }
            }

            // The trailing keys: reveal, then submit. Only there once there
            // is something to reveal or submit, so the empty field is a
            // clean bar with a lock at one end, the way DMS's is.
            Row {
                id: keys

                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                LockKey {
                    width: root.fieldHeight - Style.spacing.lg * 2
                    height: width
                    glyphSize: Style.font.iconLarge
                    visible: input.text !== "" && !root.busy
                    glyph: root._revealed ? Glyphs.conceal : Glyphs.reveal
                    onClicked: {
                        root._revealed = !root._revealed;
                        root.take();
                    }
                }

                LockKey {
                    width: root.fieldHeight - Style.spacing.lg * 2
                    height: width
                    glyphSize: Style.font.iconLarge
                    visible: input.text !== "" && !root.busy
                    glyph: Glyphs.submit
                    lit: true
                    onClicked: {
                        if (input.text !== "")
                            root.submitted(input.text);
                        root.take();
                    }
                }
            }

            // A click anywhere on the field puts the caret back, which is
            // what a click on a lockscreen almost always means.
            MouseArea {
                anchors.fill: parent
                z: -1
                cursorShape: Qt.IBeamCursor
                onClicked: root.take()
            }
        }
    }

    // Hung below the row, outside its height, for the reason implicitHeight
    // gives. Centred on the field rather than on the row, so it lines up
    // under the thing it is about and not under the avatar.
    Column {
        anchors.top: row.bottom
        anchors.topMargin: Style.spacing.xl
        x: frame.x
        width: frame.width
        spacing: Style.spacing.md

        // Whatever PAM said, rather than something invented here.
        Text {
            width: parent.width
            visible: root.message !== ""
            text: root.message
            color: root.messageIsError ? Commons.Color.lock.textError : Commons.Color.lock.placeholder
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        // Caps Lock is the most common reason a password typed correctly
        // does not work, and the one thing a lockscreen can notice on your
        // behalf.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.capsLock
            spacing: Style.spacing.sm

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Glyphs.capsLock
                size: Style.font.icon
                color: Commons.Color.lock.textError
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Caps Lock is on"
                color: Commons.Color.lock.textError
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }
        }
    }

    SequentialAnimation {
        id: shaker

        NumberAnimation {
            target: offset
            property: "x"
            to: 14
            duration: 60
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: offset
            property: "x"
            to: -14
            duration: 90
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: offset
            property: "x"
            to: 7
            duration: 70
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: offset
            property: "x"
            to: 0
            duration: 60
            easing.type: Easing.OutQuad
        }
    }
}
