import QtQuick
import qs.Services
// Qualified as well, for the collision Widgets/Keybinds describes: this
// directory's own Nightlight -- this widget -- wins the unqualified name, so
// a bare `Nightlight` here would be the widget and not the service.
import qs.Services as Services
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

    active: Services.Nightlight.active
    activeTooltipText: "Nightlight on, " + Services.Nightlight.temperature + "K. Click for normal colour"
    inactiveTooltipText: "Warm the screen to " + Services.Nightlight.temperature + "K"

    iconName: Glyphs.nightMode
    iconColor: Services.Nightlight.active ? Color.accent : Color.foreground

    // State, never visibility: Section sizes the slot from this, and a
    // binding to `visible` would feed back into itself.
    concealed: !Services.Nightlight.available || (!effectiveActive && !inactiveRevealed)
    interactive: Services.Nightlight.available && belongsInBlock && (effectiveActive || indicatorBlock === "inactive" || inactiveRevealed)

    onPressed: b => {
        if (b === Qt.LeftButton)
            Services.Nightlight.toggle();
    }
}
