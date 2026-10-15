pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "SystemMonitor.js" as Model

// CPU, memory, CPU temperature, disk and network, read straight from /proc,
// /sys and df.
//
// One poller for every system monitor on every bar: the widget exists once
// per monitor, and two of them reading /proc/stat on their own clocks would
// also disagree about the CPU, since a percentage depends on when the last
// sample was taken.
//
// It polls only while somebody is looking -- a widget on a visible bar, the
// panel, or a script that asked within the last minute -- and every two
// seconds while it does. A tick is four small synchronous reads; df, the one
// thing that is a process, runs every thirty seconds, since a disk does not
// fill between two looks at the bar.
Singleton {
    id: root

    readonly property int interval: 2000
    readonly property int diskEvery: 15

    // ---------------------------------------------------------------- state

    // -1 / null until there are two samples to compare, or a sensor to read.
    property real cpu: -1
    property var cores: []
    property var memory: null
    property real temperature: NaN
    readonly property bool hasTemperature: isFinite(temperature)
    property string sensorName: ""
    // Bytes per second, summed over the physical interfaces.
    property real rx: 0
    property real tx: 0
    // path -> parseDfLine result, for every path some widget asked for.
    property var disks: ({})

    readonly property var disk: disks["/"] || null

    // --------------------------------------------------------- who is looking

    // Widgets register themselves, and say whether they are on screen. A
    // widget on a hidden bar keeps its slot but stops the clock.
    property var _widgets: []
    property var _showing: []

    readonly property bool polling: _showing.length > 0 || panelOpen || ipcHold.running

    function attach(item) {
        if (root._widgets.indexOf(item) < 0)
            root._widgets = root._widgets.concat([item]);
    }

    function detach(item) {
        root._widgets = root._widgets.filter(w => w !== item);
        root.setShowing(item, false);
    }

    function setShowing(item, showing) {
        const rest = root._showing.filter(w => w !== item);
        root._showing = showing ? rest.concat([item]) : rest;
    }

    // Root always, so the panel and `pshell sysmon status` have a disk to
    // talk about, then whatever else a widget's `diskPath` names.
    readonly property var diskPaths: {
        const paths = ["/"];
        for (let i = 0; i < root._widgets.length; i++) {
            const p = root._widgets[i].diskPath;
            if (p && paths.indexOf(p) < 0)
                paths.push(p);
        }
        return paths;
    }
    onDiskPathsChanged: if (root.polling)
        root._readDisks()

    // ------------------------------------------------------------- sampling

    property var _cpuPrev: null
    property var _netPrev: null
    property real _sampledAt: 0
    property int _tick: 0

    // Synchronous, so an IPC call can sample and answer in the same breath.
    // reload() alone is not: text() straight after it hands back the
    // previous read, which made every CPU percentage one tick late and the
    // first answer after an idle stretch "--". The files are a few hundred
    // bytes of kernel text.
    function _read(view) {
        view.reload();
        view.waitForJob();
        return view.text();
    }

    function sample() {
        const now = Date.now();

        const cpuNow = Model.parseCpuStat(root._read(statFile));
        const usage = Model.cpuUsage(root._cpuPrev, cpuNow);
        root._cpuPrev = cpuNow;
        if (usage.length > 0 && usage[0] >= 0) {
            root.cpu = usage[0];
            root.cores = usage.slice(1);
        }

        root.memory = Model.parseMeminfo(root._read(memFile));

        const net = Model.parseNetDev(root._read(netFile));
        const ms = now - root._sampledAt;
        if (root._netPrev && ms > 0) {
            root.rx = Model.rate(root._netPrev.rx, net.rx, ms);
            root.tx = Model.rate(root._netPrev.tx, net.tx, ms);
        }
        root._netPrev = net;
        root._sampledAt = now;

        root._readTemperature();

        if (root._tick % root.diskEvery === 0)
            root._readDisks();
        root._tick++;
    }

    function _readTemperature() {
        if (tempFile.path === "")
            return;
        const t = Model.parseTemperature(root._read(tempFile));
        root.temperature = t === null ? NaN : t;
    }

    function _readDisks() {
        if (disker.running)
            return;
        disker.paths = root.diskPaths;
        disker.command = ["sh", "-c", 'for p; do df -P -B1 -- "$p" 2>/dev/null | sed -n 2p | grep . || echo; done', "sh"].concat(disker.paths);
        disker.running = true;
    }

    // A baseline at start, so the first answer after an idle stretch is the
    // average over that stretch rather than nothing: the CPU and network
    // counters, the sensor lookup and one df. Then nothing until somebody
    // looks.
    Component.onCompleted: {
        root._cpuPrev = Model.parseCpuStat(root._read(statFile));
        root._netPrev = Model.parseNetDev(root._read(netFile));
        root._sampledAt = Date.now();
        sensorProbe.running = true;
        root._readDisks();
    }

    onPollingChanged: {
        if (!root.polling)
            return;
        root._tick = 0;
        root.sample();
    }

    Timer {
        interval: root.interval
        repeat: true
        running: root.polling
        onTriggered: root.sample()
    }

    // An IPC call keeps the poller going for a minute, so a script asking in
    // a loop gets two-second numbers rather than one long average.
    Timer {
        id: ipcHold
        interval: 60000
    }

    // Starting the hold starts the poller, and starting the poller samples,
    // so an idle shell still answers with a reading taken just now.
    function _forScript() {
        ipcHold.restart();
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: netFile
        path: "/proc/net/dev"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: tempFile
        path: ""
        blockLoading: true
        printErrors: false
    }

    // Which file is the CPU temperature. hwmon numbers move between boots,
    // so it is looked up once per run rather than configured.
    Process {
        id: sensorProbe

        command: ["sh", "-c", 'for i in /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$i" ] || continue; d=${i%/*}; l=${i%_input}_label; printf "%s\\t%s\\t%s\\n" "$(cat "$d/name" 2>/dev/null)" "$(cat "$l" 2>/dev/null)" "$i"; done; for z in /sys/class/thermal/thermal_zone*; do [ -r "$z/temp" ] && printf "zone:%s\\t\\t%s\\n" "$(cat "$z/type" 2>/dev/null)" "$z/temp"; done; true']

        stdout: StdioCollector {
            onStreamFinished: {
                const s = Model.pickCpuSensor(Model.parseSensorList(text));
                if (!s)
                    return;
                root.sensorName = s.label !== "" ? s.chip + " " + s.label : s.chip.replace(/^zone:/, "");
                tempFile.path = s.path;
                root._readTemperature();
            }
        }
    }

    Process {
        id: disker

        property var paths: []

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split("\n");
                const found = {};
                for (let i = 0; i < disker.paths.length; i++) {
                    const d = Model.parseDfLine(lines[i]);
                    if (d)
                        found[disker.paths[i]] = d;
                }
                root.disks = found;
            }
        }
    }

    // ---------------------------------------------------------------- panel
    //
    // Weather's arrangement, for Weather's reason: the widget exists once per
    // monitor, so the wanted-open state lives here and the widgets follow it.

    property bool panelOpen: false
    property string panelScreen: ""

    function openPanel(screenName) {
        if (root._widgets.length === 0) {
            console.warn("pshell: no system monitor in the bar, so there is no panel to open");
            return;
        }
        root.panelScreen = screenName !== undefined && String(screenName) !== "" ? String(screenName) : root._focusedScreenName();
        root.panelOpen = true;
    }

    function closePanel() {
        root.panelOpen = false;
    }

    function togglePanel(screenName) {
        if (root.panelOpen)
            closePanel();
        else
            openPanel(screenName);
    }

    function _focusedScreenName() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            return mon.name;
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    function snapshot() {
        return {
            cpu: root.cpu,
            cores: root.cores,
            memory: root.memory,
            temperature: root.hasTemperature ? root.temperature : null,
            sensor: root.sensorName,
            disk: root.disk,
            rx: root.rx,
            tx: root.tx
        };
    }

    // ------------------------------------------------------------------ IPC

    IpcHandler {
        target: "pshell.sysmon"

        // One line, fixed order: cpu, ram, temp, disk, net.
        function status(): string {
            root._forScript();
            return Model.statusLine(root.snapshot());
        }

        // Everything the panel shows, for a script that wants numbers
        // rather than words. Bytes and percents, never formatted.
        function json(): string {
            root._forScript();
            return JSON.stringify(root.snapshot());
        }

        // Whole percents and degrees; -1 where there is no reading.
        function cpu(): int {
            root._forScript();
            return root.cpu < 0 ? -1 : Math.round(root.cpu);
        }

        function memory(): int {
            root._forScript();
            return root.memory ? Math.round(root.memory.percent) : -1;
        }

        function temperature(): int {
            root._forScript();
            return root.hasTemperature ? Math.round(root.temperature) : -1;
        }

        function toggle(): void {
            root.togglePanel();
        }

        function open(): void {
            root.openPanel();
        }

        function close(): void {
            root.closePanel();
        }
    }
}
