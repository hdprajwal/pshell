// For the Component attached property below. The surface itself draws
// nothing directly -- LockContent does that -- so QtQuick is not needed.
import QtQml
import Quickshell.Wayland
import qs.Commons
import qs.Services

// One locked screen.
//
// WlSessionLock instantiates this once per monitor and hands each copy its
// own `screen`, so multi-monitor needs no code here -- every display gets a
// full-size surface with its own centred stack rather than one screen
// holding the prompt and the rest going black.
//
// Opaque, deliberately. A lock surface that let anything show through would
// be a lock surface that leaks what was on the desktop.
WlSessionLockSurface {
    id: surface

    color: Color.background

    LockContent {
        anchors.fill: parent

        authState: Lock.authState
        message: Lock.message
        attempts: Lock.attempts
        keyboardLayout: Lock.keyboardLayout
        capsLock: Lock.capsLock

        onSubmitted: password => Lock.submit(password)
        onEdited: Lock.clearMessage()

        // The compositor hands keyboard focus to the lock surface, but not
        // to any particular item inside it. Without this the first thing
        // typed on a freshly locked screen goes nowhere, which reads as a
        // frozen machine.
        //
        // Every monitor's surface asks; the last one to be created wins, and
        // any of them is a correct answer -- they all submit to the same
        // service.
        Component.onCompleted: focusField()
    }
}
