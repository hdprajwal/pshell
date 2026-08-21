import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// How much of your coding agents' allowances you have spent. The bar carries
// the single tightest window; the panel carries all of them, a week of
// history and where the tokens went.
//
// Shaped like Calendar: a qs.Ui.Panel owns the open/close lifecycle and the
// IPC route, a WidgetButton paints the bar slot, and a KeyboardPanel is the
// surface. All the reading of files happens in Services/AgentUsage.
Panel {
    id: root
    moduleName: "qsbar.aiusage"
    ipcTarget: "qsbar.aiusage"

    property var cfg: ({})

    readonly property int refreshIntervalSec: Number(cfg.refreshIntervalSec || 900)
    // "max" is the tightest window anywhere, "all" is every provider, and
    // anything else is a provider id to pin to.
    readonly property string barSource: cfg.barSource || "max"
    readonly property real warnThreshold: Number(cfg.warnThreshold || 85)
    // A provider id to open on. Left unset, the panel opens on whichever
    // provider is closest to its limit -- the one the bar is already
    // pointing at, so the click answers the question the bar just raised.
    readonly property string defaultTab: cfg.defaultTab || ""
    readonly property bool hideWhenIdle: cfg.hideWhenIdle === true
    // One width for every tab. See the panel below for why it is a constant
    // rather than something measured off the content.
    readonly property int panelWidth: cfg.width || Style.space(360)

    // Which provider the panel is showing.
    property string tab: ""

    readonly property var tabKeys: {
        const keys = [];
        for (var i = 0; i < AgentUsage.records.length; i++)
            keys.push(String(AgentUsage.records[i].id));
        return keys;
    }
    readonly property var activeRecord: AgentUsage.recordFor(tab)

    // The tab to land on. Falls back down a ladder rather than to a constant,
    // because every rung can be absent: the configured provider may have been
    // dropped from the updater's config, and there may be no usable percent
    // anywhere to pick a peak from.
    function resolvedTab() {
        const keys = root.tabKeys;
        if (keys.length === 0)
            return "";
        if (keys.indexOf(root.defaultTab) >= 0)
            return root.defaultTab;
        const top = AgentUsage.peak;
        if (top && top.record && keys.indexOf(String(top.record.id)) >= 0)
            return String(top.record.id);
        return keys[0];
    }

    // What the bar draws: a mark and a number, once or once per provider.
    readonly property var barEntries: {
        const out = [];
        const source = String(root.barSource);

        function entry(record, limit) {
            const value = Number(limit ? limit.percent : NaN);
            return {
                id: String(record.id),
                name: String(record.name || record.id),
                label: limit ? AgentUsage.windowLabel(limit) : "",
                fullLabel: limit ? String(limit.title || limit.label || "") : "",
                resetsAt: limit ? String(limit.resetsAt || "") : "",
                percent: isFinite(value) ? value : -1
            };
        }

        if (source === "all") {
            const list = AgentUsage.sorted;
            for (var i = 0; i < list.length; i++)
                // Each provider's tightest window, not its first: the bar has
                // room for one number per provider and that is the one worth
                // having.
                out.push(entry(list[i], AgentUsage.peakLimit(list[i])));
            return out;
        }

        if (source === "max") {
            const peak = AgentUsage.peak;
            if (peak)
                out.push(entry(peak.record, peak.limit));
            else if (AgentUsage.records.length > 0)
                // Nothing reports a window yet. Still wear a mark, so the
                // widget reads as waiting rather than broken.
                out.push(entry(AgentUsage.sorted[0], null));
            return out;
        }

        const pinned = AgentUsage.recordFor(source);
        if (pinned) {
            const limits = AgentUsage.limitsOf(pinned);
            out.push(entry(pinned, limits.length > 0 ? limits[0] : null));
        }
        return out;
    }

    function readingFor(entry) {
        return entry.percent < 0 ? "—" : Math.round(entry.percent * 100) + "%";
    }

    readonly property string tooltipText: {
        const lines = [];
        for (var i = 0; i < barEntries.length; i++) {
            const item = barEntries[i];
            var line = item.name + "  " + readingFor(item);
            if (item.fullLabel !== "")
                line += "  " + item.fullLabel;
            const reset = AgentUsage.resetText(item.resetsAt, clock.date);
            if (reset !== "")
                line += reset === "now" ? "  resets now" : "  resets in " + reset;
            lines.push(line);
        }
        return lines.join("\n");
    }

    // No usage directory, or nothing in it, means Omarchy's agent tooling is
    // not installed here. That is not an error worth a slot in the bar, so
    // the widget takes itself out of the row entirely.
    readonly property bool spent: AgentUsage.peak !== null && AgentUsage.peak.percent > 0
    property bool concealed: !AgentUsage.available || barEntries.length === 0 || (hideWhenIdle && !spent)

    // The bar sizes its slot from the widget; the widget is its button.
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // The section injects `cfg` after this widget is built, so the settings
    // it carries are taken when they arrive rather than at completion, when
    // every one of them would still read as its default.
    onCfgChanged: {
        AgentUsage.refreshIntervalSec = root.refreshIntervalSec;
        if (!root.opened)
            root.tab = root.resolvedTab();
    }

    // Reset times are relative, so they need a minute hand. It runs while the
    // panel is closed too: the bar's tooltip counts down as well, and a clock
    // stopped at whenever the panel last shut would have it quoting a time
    // that passed hours ago.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // A provider can disappear between runs -- one disabled in the updater's
    // own config stops being written. Leaving the panel pointed at a tab that
    // no longer exists would show an empty view with no way back.
    Connections {
        target: AgentUsage

        function onRecordsChanged() {
            if (!AgentUsage.recordFor(root.tab))
                root.tab = root.resolvedTab();
        }
    }

    onOpenedChanged: {
        if (!root.opened)
            return;
        // Opening is the one moment the numbers are certainly being looked
        // at, so it is worth a run of the updater on top of the timer.
        AgentUsage.rescan();
        AgentUsage.refresh();
        root.tab = root.resolvedTab();
    }

    // The bar slot is built here rather than from BarIconButton because that
    // draws every icon first and then one label; "all" needs a percentage
    // after each mark. The sizing is BarIconButton's, so a wide slot still
    // sits the same distance from its neighbour as a narrow one.
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        concealed: root.concealed
        hasVisualContent: root.barEntries.length > 0
        tooltipText: root.tooltipText
        fixedWidth: vertical ? -1 : Math.max(Style.bar.iconSlot, content.implicitWidth + slotPadding)
        fixedHeight: vertical ? Math.max(Style.bar.iconSlot, content.implicitHeight + slotPadding) : -1

        readonly property real slotPadding: Style.bar.iconSlot - Style.bar.iconCanvas

        onPressed: b => {
            if (b === Qt.LeftButton)
                root.toggle();
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: Style.spacing.md

            Repeater {
                model: root.barEntries

                Row {
                    required property var modelData

                    readonly property bool warn: modelData.percent >= 0 && Math.round(modelData.percent * 100) >= root.warnThreshold

                    spacing: Style.spacing.sm

                    ProviderMark {
                        anchors.verticalCenter: parent.verticalCenter
                        providerId: modelData.id
                        size: Style.bar.iconCanvas
                        fallbackColor: button.foreground
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.readingFor(modelData)
                        color: parent.warn ? button.activeColor : button.foreground
                        font.family: button.fontFamily
                        font.pixelSize: Style.font.body
                        renderType: Text.NativeRendering

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }
                        }
                    }
                }
            }
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher

        // One width for every tab, deliberately. Sizing from the active tab
        // would make the panel jump sideways under the pointer every time you
        // moved between tabs, and the tab strip itself would change shape as
        // you used it. Only the height follows the content, and it eases so
        // the change reads as the same panel rather than a new one.
        contentWidth: panel.fittedContentWidth(root.panelWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            // Left and right walk the tab strip, the way clicking it does.
            onMoveRequested: (dx, dy) => {
                const delta = dx !== 0 ? dx : dy;
                if (delta === 0)
                    return;
                const keys = root.tabKeys;
                const at = keys.indexOf(root.tab);
                root.tab = keys[(Math.max(0, at) + delta + keys.length) % keys.length];
            }
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                // ---------- Tab strip ----------
                Rectangle {
                    width: parent.width
                    implicitHeight: strip.implicitHeight + Style.spacing.xxs * 2
                    height: implicitHeight
                    radius: Style.cornerRadius
                    color: Style.normalFill

                    Row {
                        id: strip
                        anchors.fill: parent
                        anchors.margins: Style.spacing.xxs
                        spacing: Style.spacing.xxs

                        readonly property int cells: Math.max(1, AgentUsage.records.length)
                        readonly property real cellWidth: (width - spacing * (cells - 1)) / cells

                        Repeater {
                            // Discovery order, not usage order: a tab strip
                            // that reshuffles itself as the day goes on is
                            // one you can never learn.
                            model: AgentUsage.records

                            TabButton {
                                required property var modelData

                                width: strip.cellWidth
                                key: String(modelData.id)
                                providerId: key
                            }
                        }
                    }
                }

                // ---------- The active view ----------
                //
                // Height comes from which tab is selected, never from a
                // child's `visible`: QML propagates visibility down, so a
                // host that hid itself when its content did would take the
                // content's own answer away from it.
                Item {
                    id: viewHost
                    width: parent.width
                    height: providerView.implicitHeight
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }

                    ProviderView {
                        id: providerView
                        width: parent.width
                        record: root.activeRecord
                        warnThreshold: root.warnThreshold
                        now: clock.date
                    }
                }
            }
        }
    }

    // ---- Reusable inline component ----

    // One tab. A provider wears its mark alone, which is what keeps five of
    // them inside a panel narrow enough for the gauges underneath. An id with
    // no shipped mark still gets a glyph, so an unknown provider is nameable
    // rather than blank.
    component TabButton: Rectangle {
        id: tab

        property string key: ""
        property string providerId: ""

        readonly property bool selected: root.tab === tab.key

        height: Math.round(Style.font.body * 2.2)
        radius: Math.max(1, Style.cornerRadius - 1)
        color: tab.selected ? Style.selectedFill : (hover.containsMouse ? Style.hoverFill : "transparent")

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tab = tab.key
        }

        ProviderMark {
            anchors.centerIn: parent
            providerId: tab.providerId
            size: Math.round(Style.font.body * 1.35)
            fallbackColor: tab.selected ? Color.popups.text : Color.muted
            // A dimmed mark on an unselected tab, so the strip reads as one
            // control with one thing chosen rather than five lit buttons.
            opacity: tab.selected || hover.containsMouse ? 1 : 0.55

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }
        }
    }
}
