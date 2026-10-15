import QtQuick
import Quickshell
import qs.Services
// Qualified for Weather's collision: qs.Services exports a SystemMonitor
// too -- the singleton that polls -- and this directory's own type wins the
// unqualified name.
import qs.Services as Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Services/SystemMonitor.js" as Model

// CPU, memory and CPU temperature as glyph-and-number pills, DMS's layout,
// with disk and network speed to add. Click any of them for the panel.
//
// The view half only, for Weather's reason: the reads, the clock and the
// panel's wanted-open state are in Services/SystemMonitor.qml, so two bars
// show the same numbers and poll once between them.
//
// `metrics` picks the pills, `diskPath` the filesystem the disk pill and
// panel row measure.
Panel {
    id: root

    moduleName: "pshell.sysmon"
    manageIpc: false

    property var cfg: ({})

    readonly property var metrics: Model.parseMetrics(cfg.metrics)
    readonly property string diskPath: metrics.indexOf("disk") >= 0 ? String(cfg.diskPath || "/") : ""
    readonly property int panelWidth: cfg.panelWidth || Style.space(300)

    readonly property var mon: Services.SystemMonitor
    readonly property var disk: root.mon.disks[diskPath || "/"] || null

    readonly property string screenName: bar && bar.screen ? bar.screen.name : ""
    readonly property bool hostsPanel: root.mon.panelOpen && root.mon.panelScreen === root.screenName

    // On a bar that is up. Hiding the bar stops the clock, as DMS's Ref does.
    readonly property bool onScreen: visible && !!root.QsWindow.window && root.QsWindow.window.visible

    onOnScreenChanged: root.mon.setShowing(root, onScreen)
    Component.onCompleted: {
        root.mon.attach(root);
        root.mon.setShowing(root, onScreen);
    }
    Component.onDestruction: root.mon.detach(root)

    function open() {
        root.mon.openPanel(root.screenName);
    }

    function close() {
        root.mon.closePanel();
    }

    function toggle() {
        root.mon.togglePanel(root.screenName);
    }

    function memoryLine() {
        const m = root.mon.memory;
        return m ? Model.formatSize(m.used) + " of " + Model.formatSize(m.total) : "";
    }

    function diskLine() {
        const d = root.disk;
        return d ? Model.formatSize(d.used) + " of " + Model.formatSize(d.size) + " on " + d.mount : "";
    }

    // What each pill says, keyed by metric. `reserve` is the widest the
    // value gets, so the pill holds its width while the number moves.
    readonly property var pills: ({
            cpu: {
                icon: Glyphs.cpu,
                value: Model.formatPercent(root.mon.cpu),
                reserve: "100%",
                level: Model.level("cpu", root.mon.cpu),
                tip: "CPU " + Model.formatPercent(root.mon.cpu)
            },
            ram: {
                icon: Glyphs.ram,
                value: Model.formatPercent(root.mon.memory ? root.mon.memory.percent : -1),
                reserve: "100%",
                level: Model.level("ram", root.mon.memory ? root.mon.memory.percent : -1),
                tip: "Memory " + root.memoryLine()
            },
            temp: {
                icon: Glyphs.temperature,
                value: Model.formatTemperature(root.mon.hasTemperature ? root.mon.temperature : null),
                reserve: "100°",
                level: Model.level("temp", root.mon.hasTemperature ? root.mon.temperature : null),
                tip: root.mon.sensorName !== "" ? root.mon.sensorName : "No CPU sensor found"
            },
            disk: {
                icon: Glyphs.disk,
                value: Model.formatPercent(root.disk ? root.disk.percent : -1),
                reserve: "100%",
                level: Model.level("disk", root.disk ? root.disk.percent : -1),
                tip: "Disk " + root.diskLine()
            },
            net: {
                icon: Glyphs.netSpeed,
                value: "↓" + Model.formatRate(root.mon.rx, true) + " ↑" + Model.formatRate(root.mon.tx, true),
                reserve: "↓8.8M ↑8.8M",
                level: 0,
                tip: "Down " + Model.formatRate(root.mon.rx, false) + "\nUp " + Model.formatRate(root.mon.tx, false)
            }
        })

    implicitWidth: pillRow.implicitWidth
    implicitHeight: pillRow.implicitHeight

    // A row on a top or bottom bar, a column on a side one.
    Grid {
        id: pillRow

        anchors.centerIn: parent
        columns: root.bar && root.bar.vertical ? 1 : Math.max(1, root.metrics.length)
        spacing: 0

        Repeater {
            model: root.metrics

            BarIconButton {
                id: pill

                required property string modelData
                readonly property var p: root.pills[modelData]

                bar: root.bar
                iconName: p.icon
                label: vertical ? "" : p.value
                tooltipText: p.tip
                // Accent past the warning line, urgent past the danger one.
                active: p.level > 0
                activeColor: p.level >= 2 ? (root.bar ? root.bar.urgent : Commons.Color.urgent) : Commons.Color.accent
                fixedWidth: vertical ? -1 : Math.max(slotSize, opticalSize + Style.spacing.sm + reserve.advanceWidth + slotPadding)

                TextMetrics {
                    id: reserve
                    text: pill.p.reserve
                    font.family: pill.fontFamily
                    font.pixelSize: Style.font.body
                }

                onPressed: b => {
                    if (b === Qt.LeftButton)
                        root.toggle();
                }
            }
        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: pillRow
        owner: root
        bar: root.bar
        open: root.hostsPanel
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(root.panelWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                PanelHero {
                    foreground: Commons.Color.popups.text
                    iconComponent: Component {
                        MaterialIcon {
                            name: Glyphs.sysmon
                            size: Style.font.display
                            color: Commons.Color.popups.text
                        }
                    }
                    title: "System"
                    meta: root.mon.cores.length > 0 ? root.mon.cores.length + " threads" : ""
                }

                MeterRow {
                    icon: Glyphs.cpu
                    title: "CPU"
                    value: Model.formatPercent(root.mon.cpu)
                    percent: root.mon.cpu
                    level: Model.level("cpu", root.mon.cpu)
                }

                // One bar per thread, DMS's per-core strip in miniature.
                Row {
                    id: coreStrip

                    visible: root.mon.cores.length > 1
                    width: parent.width
                    height: Style.space(24)
                    spacing: Math.max(1, Style.spacing.xxs)

                    readonly property real cellWidth: root.mon.cores.length > 0 ? (width - spacing * (root.mon.cores.length - 1)) / root.mon.cores.length : 0

                    // By count, not by array: the array is new every tick, and
                    // a new model would rebuild every bar instead of moving it.
                    Repeater {
                        model: root.mon.cores.length

                        Rectangle {
                            required property int index
                            readonly property real load: root.mon.cores[index] === undefined ? 0 : root.mon.cores[index]

                            width: coreStrip.cellWidth
                            height: coreStrip.height
                            radius: Math.min(width / 2, Style.space(2))
                            color: Style.normalFill

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.round(parent.height * Math.max(0, parent.load) / 100)
                                radius: parent.radius
                                color: Model.level("cpu", parent.load) >= 2 ? Commons.Color.urgent : Commons.Color.accent

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

                MeterRow {
                    icon: Glyphs.ram
                    title: "Memory"
                    value: Model.formatPercent(root.mon.memory ? root.mon.memory.percent : -1)
                    percent: root.mon.memory ? root.mon.memory.percent : -1
                    level: Model.level("ram", percent)
                    detail: {
                        const m = root.mon.memory;
                        if (!m)
                            return "";
                        const swap = m.swapTotal > 0 ? "  ·  swap " + Model.formatSize(m.swapUsed) : "";
                        return root.memoryLine() + swap;
                    }
                }

                MeterRow {
                    icon: Glyphs.temperature
                    title: "Temperature"
                    value: Model.formatTemperature(root.mon.hasTemperature ? root.mon.temperature : null)
                    percent: root.mon.hasTemperature ? root.mon.temperature : -1
                    level: Model.level("temp", percent)
                    detail: root.mon.sensorName
                }

                MeterRow {
                    icon: Glyphs.disk
                    title: "Disk"
                    value: Model.formatPercent(root.disk ? root.disk.percent : -1)
                    percent: root.disk ? root.disk.percent : -1
                    level: Model.level("disk", percent)
                    detail: root.diskLine()
                }

                MeterRow {
                    icon: Glyphs.netSpeed
                    title: "Network"
                    meter: false
                    value: "↓ " + Model.formatRate(root.mon.rx, false)
                    detail: "↑ " + Model.formatRate(root.mon.tx, false)
                }
            }
        }
    }
}
