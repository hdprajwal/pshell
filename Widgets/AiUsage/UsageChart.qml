import QtQuick
import qs.Services
import qs.Commons

// Seven days of tokens as seven columns, oldest first, today last. The record
// calls the field `messageCount`; it counts tokens, and calling it anything
// else here would only pass the lie on.
//
// Columns are sized against the tallest day in the window rather than any
// absolute figure. A week is the comparison anyone actually makes -- was
// today heavy for me, not was today heavy in general.
Column {
    id: root

    property var days: []
    property real columnHeight: Style.space(74)

    readonly property int count: days ? days.length : 0
    readonly property real columnWidth: count > 0 ? (width - Style.spacing.sm * (count - 1)) / count : 0

    function tokensAt(index) {
        const day = days && index >= 0 && index < count ? days[index] : null;
        return day ? Number(day.messageCount) || 0 : 0;
    }

    readonly property real peak: {
        var best = 0;
        for (var i = 0; i < count; i++)
            best = Math.max(best, tokensAt(i));
        return best;
    }

    readonly property real total: {
        var sum = 0;
        for (var i = 0; i < count; i++)
            sum += tokensAt(i);
        return sum;
    }

    // A bare date has no time in it, so it is built from its parts rather
    // than parsed: reading "2026-08-14" as an instant puts it at UTC
    // midnight, and west of Greenwich that is the day before.
    function initialOf(date) {
        const parts = String(date || "").split("-");
        if (parts.length !== 3)
            return "";
        return Qt.formatDateTime(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])), "ddd").charAt(0);
    }

    spacing: Style.spacing.md

    Row {
        width: parent.width
        height: root.columnHeight
        spacing: Style.spacing.sm

        Repeater {
            model: root.days

            Item {
                id: dayColumn

                required property var modelData
                required property int index

                readonly property real tokens: Number(modelData.messageCount) || 0
                readonly property bool today: index === root.count - 1

                width: root.columnWidth
                height: root.columnHeight

                // Today carries the accent and nothing else. It marks a
                // column that is still filling without drawing a box that,
                // on a provider with a quiet week, is the loudest thing in
                // an otherwise empty chart.
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    // Two pixels for a day with nothing in it: a column that
                    // is not there reads as a gap in the week rather than a
                    // day off.
                    height: Math.max(2, Math.round(parent.height * (root.peak > 0 ? dayColumn.tokens / root.peak : 0)))
                    radius: Style.space(2)
                    color: dayColumn.today ? Color.accent : (dayColumn.tokens > 0 ? Style.selectedFill : Style.normalFill)

                    Behavior on height {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
            model: root.days

            Text {
                required property var modelData
                required property int index

                width: root.columnWidth
                horizontalAlignment: Text.AlignHCenter
                text: root.initialOf(modelData.date)
                color: index === root.count - 1 ? Color.popups.text : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }

    Item {
        width: parent.width
        height: weekTotal.implicitHeight

        Text {
            id: weekTotal
            anchors.left: parent.left
            text: AgentUsage.formatTokens(root.total) + " this week"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }

        Text {
            anchors.right: parent.right
            text: "avg " + AgentUsage.formatTokens(root.count > 0 ? root.total / root.count : 0) + "/day"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
}
