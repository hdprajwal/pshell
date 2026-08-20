import QtQuick
import Quickshell
import qs.Components
import qs.Services
import qs.Commons

// A clock in the bar that opens a month. The plain `clock` widget stays for
// anyone who wants text and nothing else.
BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property string format: cfg.format || "ddd dd MMM  HH:mm"
    readonly property string timeFormat: cfg.timeFormat || "HH:mm"
    readonly property string dateFormat: cfg.dateFormat || "dddd, d MMMM yyyy"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    text: Qt.formatDateTime(clock.date, root.format)
    // Off the coordinator rather than this panel's own flag, so exactly one
    // widget in the bar can look active.
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button !== Qt.LeftButton)
            return;
        panel.toggle(root);
        // Opening always lands on the current month. Reopening to whatever you
        // paged to last week is never what you wanted.
        if (panel.opened)
            month.reset();
    }

    Popout {
        id: panel
        bar: root.bar

        Column {
            spacing: 16

            Column {
                spacing: 4
                width: month.width

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(clock.date, root.timeFormat)
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 4.2)
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(clock.date, root.dateFormat)
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 1.15)
                }
            }

            Rectangle {
                width: month.width
                height: 1
                color: Util.alpha(Color.foreground, 0.12)
            }

            MonthGrid {
                id: month
                today: clock.date
                firstDay: String(root.cfg.firstDayOfWeek || "")
            }
        }
    }
}
