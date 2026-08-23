pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "NmParse.js" as NmParse

// Everything Quickshell.Networking cannot reach, which is most of
// NetworkManager: the stored profiles, IP configuration, VPN, hidden SSIDs.
// Quickshell.Networking keeps its job -- live state for the bar -- and this
// singleton is only for the parts it has no API for.
//
// The hard rule this whole file is shaped by: qsbar has no backend daemon,
// and it is not getting one. Every read here is a short-lived `nmcli` child
// process, exactly like a streaming script widget, and the single long-lived
// process is `nmcli monitor` -- a reader, not a server, holding no state.
//
// Two things are deliberate and easy to undo by accident:
//
//   The queue. One Process drains one command at a time. Save needs `modify`
//   to have finished before `connection up` runs, and two concurrent nmcli
//   invocations against the same profile is how you get a half-applied one.
//
//   The refcount. `nmcli monitor` and the periodic re-reads only run while
//   something has called addRef(). The settings window is closed almost all
//   the time, and a bar that spawns nmcli on every NetworkManager event for a
//   window nobody is looking at is a daemon in all but name. This is the same
//   bargain Widgets/Network/Network.qml already makes with wifi scanning.
Singleton {
    id: root

    // ------------------------------------------------------------- state

    property var connections: []
    property var devices: []
    property var general: ({})
    property string lastError: ""

    signal changed

    // --------------------------------------------------------- refcount

    property int refs: 0
    readonly property bool active: refs > 0

    function addRef() {
        refs = refs + 1;
    }

    function removeRef() {
        refs = Math.max(0, refs - 1);
    }

    onActiveChanged: {
        if (active)
            refresh();
    }

    // ------------------------------------------------------------ queue

    // Plain array mutation is fine here: nothing binds to _queue, so there is
    // no binding to re-evaluate and no reason to pay for a copy per push.
    property var _queue: []
    property bool _busy: false

    function run(argv, callback) {
        root._queue.push({
            argv: argv,
            cb: callback || null
        });
        root._pump();
    }

    function _pump() {
        if (root._busy || root._queue.length === 0)
            return;
        root._busy = true;
        worker.command = ["nmcli"].concat(root._queue[0].argv);
        worker.running = true;
    }

    Process {
        id: worker
        running: false

        // waitForEnd holds the exited signal until the stream is done, so
        // both collectors are readable in onExited. Verified rather than
        // assumed: onStreamFinished fires first, and the collectors reset
        // between runs, which is what makes reusing one Process for a queue
        // safe.
        stdout: StdioCollector {
            id: workerOut
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: workerErr
            waitForEnd: true
        }

        onExited: code => {
            const job = root._queue.shift();
            root._busy = false;

            const out = String(workerOut.text || "");
            const err = String(workerErr.text || "").trim();

            // nmcli's own words, kept verbatim. A paraphrase of
            // "Error: 802-11-wireless-security.psk: property is invalid" is
            // always worse than the sentence NetworkManager wrote.
            if (code !== 0)
                root.lastError = err !== "" ? err : "nmcli exited " + code;

            if (job && job.cb)
                job.cb(code, out, err);

            root._pump();
        }
    }

    // ------------------------------------------------------------ reads

    readonly property var connectionFields: ["name", "uuid", "type", "device", "active", "autoconnect", "state"]
    readonly property var deviceFields: ["device", "type", "state", "connection", "conUuid"]
    readonly property var generalFields: ["state", "connectivity", "wifi", "wwan"]
    readonly property var wifiFields: ["inUse", "bssid", "ssid", "mode", "chan", "freq", "rate", "signal", "security"]

    function refresh() {
        run(["-t", "-f", "NAME,UUID,TYPE,DEVICE,ACTIVE,AUTOCONNECT,STATE", "connection", "show"], function (code, out) {
            if (code === 0)
                root.connections = NmParse.parseTable(out, root.connectionFields);
        });

        run(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION,CON-UUID", "device", "status"], function (code, out) {
            if (code === 0)
                root.devices = NmParse.parseTable(out, root.deviceFields);
        });

        run(["-t", "-f", "STATE,CONNECTIVITY,WIFI,WWAN", "general", "status"], function (code, out) {
            if (code === 0) {
                const rows = NmParse.parseTable(out, root.generalFields);
                root.general = rows.length > 0 ? rows[0] : ({});
            }
            // Emitted from the last of the three so a consumer redraws once
            // rather than three times per event.
            root.changed();
        });
    }

    // The whole stored profile, settings and current activation together.
    // `withSecrets` is only ever true on an explicit reveal: without it every
    // secret reads as the literal string "<hidden>", which is exactly what we
    // want the editor to hold until the user asks otherwise.
    function showProfile(uuid, withSecrets, callback) {
        const argv = withSecrets ? ["-t", "--show-secrets", "connection", "show", uuid] : ["-t", "connection", "show", uuid];
        run(argv, function (code, out, err) {
            if (code !== 0) {
                callback(null, err);
                return;
            }
            callback(NmParse.parseProfile(out), "");
        });
    }

    function deviceDetail(device, callback) {
        run(["-t", "device", "show", device], function (code, out, err) {
            if (code !== 0) {
                callback(null, err);
                return;
            }
            callback(NmParse.parseProfile(out), "");
        });
    }

    // Quickshell.Networking's WifiNetwork carries a name, a signal strength
    // and a security type, and nothing else -- no BSSID, no band, no channel,
    // no rate. Those come from here and are merged onto the live list by
    // SSID, which is why the scan list is two sources rather than one.
    //
    // --rescan no because Quickshell already has a scanner running while the
    // Wi-Fi tab is open; asking nmcli to trigger a second one makes the list
    // flicker for no new information.
    function wifiScan(device, callback) {
        const argv = ["-t", "-f", "IN-USE,BSSID,SSID,MODE,CHAN,FREQ,RATE,SIGNAL,SECURITY", "device", "wifi", "list", "ifname", device, "--rescan", "no"];
        run(argv, function (code, out, err) {
            if (code !== 0) {
                callback([], err);
                return;
            }
            callback(NmParse.parseTable(out, root.wifiFields), "");
        });
    }

    // nmcli reports a frequency as "2462 MHz". The band is what a person
    // reads, so the conversion happens here rather than at four call sites.
    function bandOf(freqText) {
        const mhz = parseInt(String(freqText), 10);
        if (!isFinite(mhz) || mhz <= 0)
            return "";
        if (mhz >= 5925)
            return "6 GHz";
        if (mhz >= 4900)
            return "5 GHz";
        return "2.4 GHz";
    }

    // ---------------------------------------------------------- watching

    // Event-driven, not polled. `nmcli monitor` prints a line whenever
    // anything changes; a poll timer would either be too slow to feel live or
    // fast enough to be a background load on a laptop.
    Process {
        id: monitor
        running: root.active
        command: ["nmcli", "monitor"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => debounce.restart()
        }

        // One user action produces a burst of monitor lines -- a device
        // changes state four times on the way to "connected". Respawning is
        // for the other case: nmcli monitor exits when NetworkManager itself
        // restarts, and staying dead through that is the one moment watching
        // would have mattered most.
        //
        // Recorded because it looks like a bug in the refcount and is not:
        // dropping the last ref does stop this process, verified. But SIGTERM
        // to the shell while a ref is held leaves `nmcli monitor` alive and
        // reparented to init. That is Quickshell's behaviour for any
        // long-lived Process, not something this file causes -- killing the
        // bar orphans Services/SystemTheme.qml's `gsettings monitor` in
        // exactly the same way. Do not try to fix it here; if it is ever
        // worth fixing it belongs wherever both of them can be fixed at once.
        onExited: {
            if (root.active)
                respawn.restart();
        }
    }

    Timer {
        id: debounce
        interval: 300
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: respawn
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.active)
                monitor.running = true;
        }
    }

    // -------------------------------------------------------------- ipc

    // The data layer's only window before there is any UI, and it stays
    // afterwards: when a profile looks wrong in the settings app, this is how
    // you diff qsbar's view of NetworkManager against nmcli's own without
    // guessing which of the two is lying.
    IpcHandler {
        target: "qsbar.nm"

        function refresh(): void {
            root.refresh();
        }

        function dump(): void {
            console.log("qsbar.nm general:", JSON.stringify(root.general));
            console.log("qsbar.nm devices:", JSON.stringify(root.devices));
            console.log("qsbar.nm connections:", JSON.stringify(root.connections));
            console.log("qsbar.nm refs:", root.refs, "lastError:", JSON.stringify(root.lastError));
        }
    }
}
