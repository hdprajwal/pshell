import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar's toggle for the idle inhibitor. Only the view lives here: the
// state and the overlay surface that holds the actual inhibitor are in
// Services/IdleInhibit.qml, because this widget exists once per monitor and
// per-monitor copies of a whole-session toggle could disagree with each
// other. Every instance reads and flips the same singleton, so the
// indicators on every bar agree, and so does `pshell idle isInhibited`.
BarIndicator {
    id: root

    property var cfg: ({})

    active: IdleInhibit.inhibited
    activeTooltipText: "Allow the screen to sleep"
    inactiveTooltipText: "Keep the screen awake"

    iconSource: Icons.first(IdleInhibit.inhibited ? ["my-caffeine-on-symbolic", "caffeine-cup-full", "preferences-desktop-screensaver-symbolic"] : ["my-caffeine-off-symbolic", "caffeine-cup-empty", "preferences-desktop-screensaver-symbolic"])
    iconColor: IdleInhibit.inhibited ? Commons.Color.accent : Commons.Color.foreground

    onPressed: b => {
        if (b === Qt.LeftButton)
            IdleInhibit.toggle();
    }
}
