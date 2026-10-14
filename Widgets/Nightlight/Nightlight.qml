import QtQuick
import qs.Services
import qs.Commons
import qs.Ui

// The bar's toggle for the nightlight. Only the view lives here, for the
// idle inhibitor's reason: the state, hyprsunset and the schedule are in
// Services/Nightlight.qml, so the indicators on every monitor agree with
// each other and with `pshell nightlight isOn`.
//
// Hides itself where hyprsunset is not installed, as aiUsage does without
// pshell-agents: a toggle that can only fail is not worth a slot, and
// `pshell nightlight on` says what to install.
BarIndicator {
    id: root

    property var cfg: ({})

    active: Nightlight.active
    activeTooltipText: "Nightlight on, " + Nightlight.temperature + "K. Click for normal colour"
    inactiveTooltipText: "Warm the screen to " + Nightlight.temperature + "K"

    iconName: Glyphs.nightMode
    iconColor: Nightlight.active ? Color.accent : Color.foreground

    // State, never visibility: Section sizes the slot from this, and a
    // binding to `visible` would feed back into itself.
    concealed: !Nightlight.available || (!effectiveActive && !inactiveRevealed)
    interactive: Nightlight.available && belongsInBlock && (effectiveActive || indicatorBlock === "inactive" || inactiveRevealed)

    onPressed: b => {
        if (b === Qt.LeftButton)
            Nightlight.toggle();
    }
}
