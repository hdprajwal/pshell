import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A caps lock light on the bar, there only while caps lock is on. Only the
// view lives here, for the idle inhibitor's reason: the LED reads are in
// Services/CapsLock.qml, so every monitor's indicator agrees with the
// others and with `pshell capslock status`.
//
// Nothing to click: the key is the switch, and pressing it on someone's
// behalf is not the bar's business. Named after DMS's widget rather than
// `CapsLock`, which qs.Services already exports as the singleton.
BarIndicator {
    id: root

    property var cfg: ({})

    active: CapsLock.on
    // "active", Privacy's reason: a hover over the bar reveals the
    // indicators you can act on, and this is not one of them. Caps lock off
    // means nothing to show.
    indicatorBlock: "active"
    activeTooltipText: "Caps Lock is on"

    iconName: Glyphs.capsLock
    iconColor: Commons.Color.accent
}
