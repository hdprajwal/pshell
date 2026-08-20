import QtQuick
import qs.Services
import qs.Commons

// One month: a header you can page through, a weekday row, and the days.
//
// The grid is always six rows. A month can start late enough to spill into a
// seventh week, and sizing to the content would make the panel jump height
// between February and August. Fixed rows cost a mostly-empty row sometimes
// and buy a panel that never moves.
Column {
    id: root

    // Which day the highlight sits on. Fed by the clock, so leaving the panel
    // open across midnight moves it.
    property date today: new Date()

    // "monday", "sunday", or empty to follow the locale.
    property string firstDay: ""

    // The month on screen, which is not necessarily the month `today` is in.
    // Deliberately not bound to `today`: paging away must survive the clock
    // ticking, and reset() is how it comes back.
    property int viewYear: 0
    property int viewMonth: 0

    readonly property int cellSize: Math.round(Style.font.body * 2.9)
    // A day cell is wider than it is tall. Square cells put the same padding
    // on every side, but a two-digit number is about twice as wide as it is
    // high, so the leftover space all shows up above and below and the rows
    // read as further apart than the columns even when the gap is identical.
    readonly property int cellHeight: Math.round(Style.font.body * 2.2)
    // Shared by the grid and the weekday row above it, which have to keep the
    // same column pitch or the labels drift off their columns.
    readonly property int cellGap: 4
    readonly property int weekStart: {
        if (root.firstDay === "sunday")
            return 0;
        if (root.firstDay === "monday")
            return 1;
        return Qt.locale().firstDayOfWeek;
    }

    // 42 cells starting on the weekStart before the 1st. Day-of-month 0 and
    // below roll into the previous month on their own, so the leading and
    // trailing days need no special case.
    readonly property var cells: {
        const first = new Date(root.viewYear, root.viewMonth, 1);
        const offset = (first.getDay() - root.weekStart + 7) % 7;
        const out = [];
        for (var i = 0; i < 42; i++) {
            const d = new Date(root.viewYear, root.viewMonth, 1 - offset + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === root.viewMonth,
                isToday: d.getDate() === root.today.getDate() && d.getMonth() === root.today.getMonth() && d.getFullYear() === root.today.getFullYear()
            });
        }
        return out;
    }

    function step(delta) {
        // Through a Date rather than by hand, so December + 1 becomes January
        // of the next year without a wrap check.
        const d = new Date(root.viewYear, root.viewMonth + delta, 1);
        root.viewYear = d.getFullYear();
        root.viewMonth = d.getMonth();
    }

    function reset() {
        root.viewYear = root.today.getFullYear();
        root.viewMonth = root.today.getMonth();
    }

    Component.onCompleted: reset()

    spacing: 14

    component NavButton: Rectangle {
        id: nav

        property string glyph: ""

        signal activated

        width: root.cellSize
        height: root.cellSize
        radius: 4
        color: pointer.containsMouse ? Style.hoverFill : "transparent"

        Text {
            anchors.centerIn: parent
            text: nav.glyph
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.body * 1.6)
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.activated()
        }
    }

    Row {
        spacing: 0

        NavButton {
            glyph: "‹"
            onActivated: root.step(-1)
        }

        // Click the title to come back to the current month, which is the only
        // way back once you have paged off somewhere.
        Rectangle {
            width: grid.width - root.cellSize * 2
            height: root.cellSize
            radius: 4
            color: titlePointer.containsMouse ? Style.hoverFill : "transparent"

            Text {
                anchors.centerIn: parent
                text: Qt.locale().standaloneMonthName(root.viewMonth) + " " + root.viewYear
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 1.15)
            }

            MouseArea {
                id: titlePointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reset()
            }
        }

        NavButton {
            glyph: "›"
            onActivated: root.step(1)
        }
    }

    Row {
        spacing: root.cellGap

        Repeater {
            model: 7

            Text {
                required property int index

                width: root.cellSize
                horizontalAlignment: Text.AlignHCenter
                // Two letters rather than the narrow form, which is one letter
                // and gives you T and T, S and S.
                text: Qt.locale().dayName((root.weekStart + index) % 7, Locale.ShortFormat).substring(0, 2)
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.8)
            }
        }
    }

    // The wrapper exists to carry the wheel handler over the days only. Over
    // the header it would sit on top of the nav buttons and replace their
    // cursor, and there is nothing to scroll there anyway.
    Item {
        width: grid.width
        height: grid.height

        Grid {
            id: grid
            columns: 7
            rows: 6
            spacing: root.cellGap

            Repeater {
                model: root.cells

                Item {
                    required property var modelData

                    width: root.cellSize
                    height: root.cellHeight

                    Rectangle {
                        anchors.centerIn: parent
                        // Off the short side, so the pill stays a circle and
                        // does not touch the row above.
                        width: Math.min(root.cellSize, root.cellHeight) - 4
                        height: width
                        radius: width / 2
                        visible: parent.modelData.isToday
                        color: Color.accent
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.day
                        // Against the filled pill the text has to flip to the
                        // panel background to stay readable.
                        color: parent.modelData.isToday ? Color.background : Color.foreground
                        opacity: parent.modelData.inMonth ? 1 : 0.3
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }
            }
        }

        // NoButton so presses fall through to whatever is underneath, leaving
        // only the wheel handled here.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: w => root.step(w.angleDelta.y > 0 ? -1 : 1)
        }
    }
}
