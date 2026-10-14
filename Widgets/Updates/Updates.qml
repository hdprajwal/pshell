import QtQuick
import qs.Services
// Qualified for the collision Widgets/Keybinds describes: this directory's
// own Updates -- this widget -- wins the unqualified name, so a bare
// `Updates` here would be the widget and not the service. The .js library
// below is imported by path and claims no name at all.
import qs.Services as Services
import qs.Commons
import qs.Ui
import "../../Services/Updates.js" as Model

// The bar's update indicator: an icon and how many updates are pending,
// there only while some are. Click to run the updater in a terminal, right
// click to check again now rather than waiting for the timer.
//
// Only the view lives here, for the idle inhibitor's reason: the watch on
// arch-update's state files, the check and the terminal are in
// Services/Updates.qml, so every monitor's indicator shows the same number
// as `pshell updates count`.
//
// Hidden at zero, as Omarchy's is: a bar that says "0 updates" all day is
// saying nothing. Hidden too where neither cachy-update nor arch-update is
// installed, and `pshell updates open` says what to install.
BarIconButton {
    id: root

    property var cfg: ({})

    readonly property var summary: Services.Updates.summary

    // The clock the tooltip's "checked 2 hours ago" reads. Ticked once a
    // minute, and only while the widget is showing: the tooltip text is
    // read when the pointer arrives, so it has to be current already.
    property real now: Date.now() / 1000

    Timer {
        interval: 60000
        repeat: true
        running: !root.concealed
        onTriggered: root.now = Date.now() / 1000
    }

    iconName: Glyphs.updates
    label: root.vertical ? "" : String(root.summary.total)
    // Quiet while a check pshell started is running: the number is still
    // the last check's, and may be about to change.
    dimmed: Services.Updates.checking

    tooltipText: {
        const s = root.summary;
        const lines = [(s.total === 1 ? "1 update: " : s.total + " updates: ") + Model.breakdown(s)];
        if (Services.Updates.updating)
            lines.push("Updating now");
        else if (Services.Updates.checking)
            lines.push("Checking now");
        else if (Services.Updates.checkedAt > 0)
            lines.push("Checked " + Model.formatAge(root.now, Services.Updates.checkedAt));
        if (Services.Updates.fetchFailed)
            lines.push("The last check could not reach the mirrors");
        lines.push("Click to update, right click to check again");
        return lines.join("\n");
    }

    // State, never visibility: Section sizes the slot from this, and a
    // binding to `visible` would feed back into itself.
    concealed: !Services.Updates.available || root.summary.total === 0
    interactive: !concealed

    onPressed: b => {
        if (b === Qt.LeftButton)
            Services.Updates.open();
        else if (b === Qt.RightButton)
            Services.Updates.refresh();
    }
}
