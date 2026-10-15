import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Services

// The lockscreen in an ordinary window, so it can be worked on.
//
// A native lock is the one part of a shell you cannot iterate on safely: get
// it wrong and ext-session-lock does exactly what it promises -- the session
// stays locked and blank, and the way back is a TTY. So every visual change
// is made here first.
//
// It renders the same LockContent the real surface does, which is the only
// thing that makes it worth having. Auth is stubbed in the service, not
// here, so this window physically cannot unlock anything.
FloatingWindow {
    id: win

    title: "pshell lockscreen preview"
    color: Commons.Color.background
    // Not bound to Lock.previewing: the LazyLoader holding this window is
    // already bound to it, so this only exists while a preview is wanted.
    visible: true

    implicitWidth: 1280
    implicitHeight: 800

    onClosed: Lock.closePreview()

    LockContent {
        id: content

        anchors.fill: parent

        preview: true
        authState: Lock.authState
        message: Lock.message
        notice: Lock.notice
        attempts: Lock.attempts
        keyboardLayout: Lock.keyboardLayout
        capsLock: Lock.capsLock

        onSubmitted: password => Lock.submit(password)
        onEdited: Lock.clearMessage()
        onPowerRequested: id => Lock.power(id)
        onLayoutClicked: Lock.cycleLayout()
    }

    // The real lock has no such key, on purpose. This one does, because the
    // alternative while developing is reaching for the mouse.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: Lock.closePreview()
    }

    Component.onCompleted: content.focusField()
}
