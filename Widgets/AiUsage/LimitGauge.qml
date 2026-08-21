import QtQuick
import qs.Services
import qs.Commons
import qs.Ui

// One usage window: how much of it is gone, which window it is, a meter, and
// when it comes back. Providers report anything from three windows to none,
// so this is a unit the layouts repeat rather than a fixed pair.
Column {
    id: root

    property var limit: null
    property real warnThreshold: 85
    // The per-provider tab has the room to say what the number means; the
    // All tab does not and lets the meter above it speak.
    property bool spellOutReset: false
    // Ticks once a minute from the view that owns it, so the countdown moves
    // without every gauge keeping a clock of its own.
    property var now: null

    readonly property real fraction: {
        const value = Number(limit ? limit.percent : NaN);
        // The records carry 0..1, not 0..100. Reading it as a percentage
        // draws every gauge pinned at 1%.
        return isFinite(value) ? Math.max(0, Math.min(1, value)) : -1;
    }
    readonly property bool known: fraction >= 0
    readonly property int percent: Math.round(fraction * 100)
    readonly property bool warn: known && percent >= root.warnThreshold
    readonly property color ink: warn ? Color.urgent : Color.popups.text

    readonly property string resetText: {
        if (!limit)
            return "";
        return root.spellOutReset ? AgentUsage.resetPhrase(limit.resetsAt, root.now) : AgentUsage.resetText(limit.resetsAt, root.now);
    }

    spacing: Style.spacing.xs

    // The window label rides the reading's baseline rather than its box, so
    // two type sizes still sit on one line.
    Item {
        width: parent.width
        height: reading.implicitHeight

        Text {
            id: reading
            anchors.left: parent.left
            anchors.top: parent.top
            text: root.known ? root.percent + "%" : "—"
            color: root.known ? root.ink : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
        }

        Text {
            id: window
            anchors.right: parent.right
            anchors.baseline: reading.baseline
            width: Math.max(0, parent.width - reading.implicitWidth - Style.spacing.md)
            horizontalAlignment: Text.AlignRight
            text: AgentUsage.windowLabel(root.limit)
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: track
        width: parent.width
        height: Math.max(2, Style.space(5))
        radius: height / 2
        color: Style.normalFill

        Rectangle {
            width: Math.round(track.width * Math.max(0, root.fraction))
            height: parent.height
            radius: parent.radius
            color: root.warn ? Color.urgent : Color.accent

            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Text {
        width: parent.width
        text: root.resetText
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
    }
}
