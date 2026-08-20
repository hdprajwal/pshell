import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// A clock in the bar that opens a month. The plain `clock` widget stays for
// anyone who wants text and nothing else.
//
// Shaped the way Omarchy builds a panel widget: a qs.Ui.Panel owns the
// open/close lifecycle and the IPC route, a WidgetButton paints the bar
// slot, and a KeyboardPanel is the surface. Panel already gives this
// open()/close()/toggle()/opened, so there is no state of its own to keep.
Panel {
    id: root
    moduleName: "qsbar.calendar"
    ipcTarget: "qsbar.calendar"

    property var cfg: ({})

    readonly property string format: cfg.format || "ddd dd MMM  HH:mm"
    readonly property string timeFormat: cfg.timeFormat || "HH:mm"
    readonly property string dateFormat: cfg.dateFormat || "dddd, d MMMM yyyy"

    // The bar sizes its slot from the widget; the widget is its button.
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: Qt.formatDateTime(clock.date, root.format)

        onPressed: b => {
            if (b !== Qt.LeftButton)
                return;
            root.toggle();
            // Opening always lands on the current month. Reopening to
            // whatever you paged to last week is never what you wanted.
            if (root.opened)
                month.reset();
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        // Sized from the month, which has a width of its own from its cell
        // size. Omarchy pins its panels to one width instead; a calendar is
        // the case where that would either crop the grid or pad around it.
        contentWidth: panel.fittedContentWidth(column.implicitWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            // Left/right steps a month, the way the chevrons do.
            onMoveRequested: (dx, dy) => {
                const delta = dx !== 0 ? dx : dy;
                if (delta !== 0)
                    month.step(delta);
            }
            onActivateRequested: month.reset()
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacing.xxl

                Column {
                    spacing: Style.spacing.sm
                    width: month.width

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(clock.date, root.timeFormat)
                        color: Color.popups.text
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

                PanelSeparator {
                    width: month.width
                }

                MonthGrid {
                    id: month
                    today: clock.date
                    firstDay: String(root.cfg.firstDayOfWeek || "")
                }
            }
        }
    }
}
