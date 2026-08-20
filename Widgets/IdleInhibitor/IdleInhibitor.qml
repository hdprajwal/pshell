import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Components
import qs.Commons

// Keep the screen awake.
//
// Wayland's idle inhibitor is attached to a surface and is only meant to count
// while that surface is visible. A bar gets occluded the moment anything goes
// fullscreen, which is exactly when you want this on, so the protocol alone is
// not enough to trust.
//
// So the inhibitor here is held by its own surface rather than the bar's: a
// one-pixel transparent window on the overlay layer, which sits above
// fullscreen windows and is never occluded. It is created only while the
// toggle is on, so nothing is on screen the rest of the time.
BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    // Off after a restart, always. A machine that silently refuses to sleep
    // because of something you turned on last week is a bad surprise.
    property bool inhibited: false

    iconSource: Icons.first(root.inhibited ? ["my-caffeine-on-symbolic", "caffeine-cup-full", "preferences-desktop-screensaver-symbolic"] : ["my-caffeine-off-symbolic", "caffeine-cup-empty", "preferences-desktop-screensaver-symbolic"])
    icon: root.inhibited ? "●" : "○"
    iconColor: root.inhibited ? Color.accent : Color.foreground
    active: root.inhibited

    onClicked: button => {
        if (button === Qt.LeftButton)
            root.inhibited = !root.inhibited;
    }

    Loader {
        active: root.inhibited

        sourceComponent: PanelWindow {
            // Anchored to one corner at one pixel so the compositor gives it a
            // real surface to hang the inhibitor on without anything visible.
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"

            // No exclusive zone, or this would push every other window over by
            // a pixel each time it was switched on.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "qsbar:idle-inhibit"
            // Overlay rather than Top: it has to stay unoccluded above a
            // fullscreen window for the inhibitor to keep counting.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            IdleInhibitor {
                enabled: true
            }
        }
    }
}
