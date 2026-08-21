import QtQuick
import qs.Services
import qs.Commons
import qs.Ui

// One provider in full: who it is, what it has left, a week of history, and
// where the tokens went. Every section hides itself when the record has
// nothing for it, which is what lets one view serve a provider reporting
// three windows and one reporting none.
Column {
    id: root

    property var record: null
    property real warnThreshold: 85
    property var now: null

    readonly property var limits: AgentUsage.limitsOf(record)
    readonly property var days: record && record.recentDays ? record.recentDays : []
    // Five is what fits before the list stops being a ranking and starts
    // being an inventory.
    readonly property var models: AgentUsage.modelRanking(record).slice(0, 5)
    readonly property real modelPeak: models.length > 0 ? models[0].total : 0

    // The help line is a standing instruction, not news: Claude ships one
    // while perfectly healthy. Show it only once something has actually gone
    // wrong, or it becomes a permanent scold under a working provider.
    readonly property string status: record ? String(record.usageStatusText || "") : ""
    readonly property string help: record ? String(record.authHelpText || "") : ""
    readonly property bool troubled: !!record && (record.ready === false || status !== "")
    readonly property string footnote: {
        const lines = [];
        if (status !== "")
            lines.push(status);
        if (troubled && help !== "")
            lines.push(help);
        return lines.join("  ");
    }

    spacing: Style.spacing.xxl

    PanelSeparator {
        foreground: Color.popups.text
    }

    PanelHero {
        width: parent.width
        foreground: Color.popups.text
        title: root.record ? String(root.record.name || root.record.id || "") : ""
        meta: root.record ? String(root.record.tierLabel || "") : ""
        detail: root.record && root.record.ready === false ? "offline" : ""

        iconComponent: Component {
            ProviderMark {
                providerId: root.record ? String(root.record.id) : ""
                size: Math.round(Style.font.body * 2.2)
            }
        }
    }

    // ---------- Windows ----------
    Column {
        width: parent.width
        spacing: Style.spacing.md

        PanelSeparator {
            foreground: Color.popups.text
        }

        Row {
            id: gauges
            width: parent.width
            spacing: Style.spacing.xxl
            visible: root.limits.length > 0

            Repeater {
                model: root.limits

                LimitGauge {
                    required property var modelData

                    width: (gauges.width - gauges.spacing * (root.limits.length - 1)) / root.limits.length
                    limit: modelData
                    warnThreshold: root.warnThreshold
                    // The tab has the room the All view does not, so the
                    // reset time can say what it is rather than being a
                    // number under a meter.
                    spellOutReset: true
                    now: root.now
                }
            }
        }

        Text {
            width: parent.width
            visible: root.limits.length === 0
            text: "No usage window reported"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
        }
    }

    // ---------- Seven days ----------
    Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.days.length > 0

        PanelSeparator {
            foreground: Color.popups.text
        }

        PanelSectionHeader {
            text: "LAST 7 DAYS"
            foreground: Color.popups.text
        }

        UsageChart {
            width: parent.width
            days: root.days
        }
    }

    // ---------- Where the tokens went ----------
    Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.models.length > 0

        PanelSeparator {
            foreground: Color.popups.text
        }

        PanelSectionHeader {
            // Lifetime, not today. The record's per-model split is cumulative
            // and only `todayTotalTokens` is scoped to the day, so saying
            // "today" here -- as the mockup did -- would be wrong.
            text: "BY MODEL"
            foreground: Color.popups.text
        }

        Repeater {
            model: root.models

            Column {
                required property var modelData

                width: parent.width
                spacing: Style.spacing.xs

                StatRow {
                    label: String(modelData.name)
                    value: AgentUsage.formatTokens(modelData.total)
                }

                Rectangle {
                    id: track
                    width: parent.width
                    height: Math.max(2, Style.space(3))
                    radius: height / 2
                    color: Style.normalFill

                    Rectangle {
                        width: Math.round(track.width * (root.modelPeak > 0 ? modelData.total / root.modelPeak : 0))
                        height: parent.height
                        radius: parent.radius
                        color: Color.accent
                    }
                }
            }
        }
    }

    // ---------- Today ----------
    Column {
        width: parent.width
        spacing: Style.spacing.md

        PanelSeparator {
            foreground: Color.popups.text
        }

        StatRow {
            label: "Tokens today"
            value: AgentUsage.formatTokens(root.record ? root.record.todayTotalTokens : 0)
        }

        StatRow {
            label: "Sessions today"
            value: String(root.record ? Number(root.record.todaySessions) || 0 : 0)
        }
    }

    Text {
        width: parent.width
        visible: root.footnote !== ""
        text: root.footnote
        color: root.troubled ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
    }
}
