import QtQuick
import qs.Commons
import qs.Commons as Commons

// The password input, and the only control on the lockscreen.
//
// A bare TextInput rather than qs.Ui's TextField because the lock speaks a
// different visual language to the panels: TextField draws itself from
// Border.controlSpec, which is the kit's hover/focus/selected vocabulary,
// and none of those states mean anything on a surface with exactly one
// focusable thing and no pointer worth speaking of. What the lock has
// instead is Omarchy's three: waiting, checking, wrong. Those are the
// Color.lock.border* tokens, and they map onto nothing in the control kit.
//
// State comes in as properties and leaves as signals. Nothing here writes
// its own inputs -- `failed` is cleared by whoever set it, told to do so by
// `edited()` -- because a component that assigns to a property its parent
// bound would silently break that binding the first time it did so.
Column {
    id: root

    property string placeholder: "Enter Password"
    // True while PAM has the password and has not answered yet. PAM takes
    // about a second to reject on purpose, and a field that looks identical
    // for that second reads as a dropped keystroke.
    property bool busy: false
    property bool failed: false
    property bool capsLock: false
    property int fieldWidth: 520

    // Frosted glass. LockBackground has already blurred the wallpaper, so a
    // wash of white over it is all frost actually is -- no second blur pass,
    // and nothing for the GPU to redraw as the field changes state.
    //
    // White rather than Color.lock.background, which is the theme's dark
    // surface: the point of frost is that the picture stays visible through
    // it, and a dark fill over a blurred photograph just reads as a hole.
    property color frost: Util.alpha("white", 0.5)
    property color frostBorder: Util.alpha("white", 0.6)

    // Dark text, because the field it sits on is now the lightest thing on
    // the screen -- the same white that makes the frost read as glass makes
    // white text vanish into it.
    //
    // Picked as whichever of the palette's two colours is darker rather than
    // hardcoded: in a dark theme that is the background, in a light theme it
    // is the foreground, and the frost is white either way.
    readonly property color inkOnFrost: Commons.Color.background.hslLightness < Commons.Color.foreground.hslLightness ? Commons.Color.background : Commons.Color.foreground

    signal submitted(string password)
    signal edited

    // Guards `edited` while clearing. Without it, wiping the field after a
    // rejection looks exactly like the user typing over the error, so the
    // error the wipe was announcing would be erased in the same frame.
    property bool _clearing: false

    function clear() {
        root._clearing = true;
        input.text = "";
        root._clearing = false;
    }

    function take() {
        input.forceActiveFocus();
    }

    spacing: Style.spacing.lg

    Rectangle {
        id: frame

        width: root.fieldWidth
        height: 56
        radius: Style.cornerRadius
        color: root.frost

        // Wrong beats busy beats idle: a failure stays red while the user
        // starts typing over it, and only clears once the parent says so.
        // Idle keeps the frost's own edge -- a themed border here would put
        // an accent line around a surface that is deliberately colourless.
        border.color: root.failed ? Commons.Color.lock.borderError : (root.busy ? Commons.Color.lock.borderActive : root.frostBorder)
        border.width: 2

        Behavior on border.color {
            ColorAnimation {
                duration: 120
            }
        }

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: Style.spacing.huge
            anchors.rightMargin: Style.spacing.huge

            // Read-only rather than disabled while checking: disabling drops
            // focus, and getting it back after a failed attempt would need a
            // round trip through the surface.
            readOnly: root.busy

            echoMode: TextInput.Password
            // Long enough to see you hit the right key, short enough that a
            // shoulder cannot read the word.
            passwordMaskDelay: 500

            color: root.inkOnFrost
            selectionColor: Commons.Color.lock.selection
            selectedTextColor: root.inkOnFrost
            font.family: Style.font.family
            font.pixelSize: Style.font.title

            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
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
                anchors.fill: parent
                visible: input.text === ""
                text: root.placeholder
                // Same ink, faded. A separate placeholder token would be a
                // colour picked against the theme's own surface, not
                // against the white this sits on.
                color: Util.alpha(root.inkOnFrost, 0.55)
                font: input.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // Caps Lock is the most common reason a password typed correctly does
    // not work, and the one thing a lockscreen can notice on your behalf.
    //
    // Column leaves invisible children out of its layout, so this costs no
    // space when it is off and the field does not shift when it comes on --
    // it grows downwards from a field that is already above centre.
    Text {
        width: root.fieldWidth
        visible: root.capsLock
        text: "Caps Lock is on"
        color: Commons.Color.lock.textError
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
    }
}
