pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The one thing pshell still needs nmcli for: turning an SSID into a profile
// uuid, so nm-connection-editor can be opened on it.
//
// This file used to be a data layer -- stored profiles, devices, IP
// configuration, VPN, a `nmcli monitor` subscription behind a refcount --
// feeding the settings app's network pages. Those pages are gone, and the
// state went with them rather than staying on as a model nobody reads. What
// is left is a launcher.
//
// The queue survives the cut, though. One Process drains one command at a
// time, so two clicks in quick succession are two lookups rather than one
// Process having its `command` rewritten out from under a run in flight.
Singleton {
    id: root

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

        // An nmcli that cannot be started -- not installed, or removed by an
        // upgrade -- never exits. Quickshell drops the process and reports
        // only that it is not running, so without this `_busy` would stay
        // set and every command queued after it would wait for an exit that
        // is never coming. The job is failed the way a non-zero exit fails
        // it, and the queue moves on. A normal exit has cleared `_busy` by
        // now, and one that started the next job has `running` back to true.
        onRunningChanged: {
            if (!worker.running && root._busy)
                root._finish(-1, "", "nmcli could not be started; is NetworkManager installed?");
        }

        onExited: code => root._finish(code, String(workerOut.text || ""), String(workerErr.text || "").trim())
    }

    function _finish(code, out, err) {
        const job = root._queue.shift();
        root._busy = false;

        // nmcli's own words, kept verbatim and logged rather than
        // stored: there is no error banner left to read a lastError
        // property, and a lookup that fails silently is exactly how
        // "nothing happens when I click edit" gets hard to explain.
        if (code !== 0)
            console.warn("pshell.nm:", JSON.stringify(job ? job.argv : []), "failed:", err !== "" ? err : "nmcli exited " + code);

        // A callback that throws must not take the queue with it: the
        // throw would abort this handler before _pump() and leave the
        // next command sitting in the queue until something unrelated
        // pushed another one. It is still a bug at the call site, so it
        // is reported rather than swallowed; the queue just keeps moving.
        if (job && job.cb) {
            try {
                job.cb(code, out, err);
            } catch (e) {
                console.warn("pshell.nm: callback for", JSON.stringify(job.argv), "threw:", e);
            }
        }

        root._pump();
    }

    // ----------------------------------------------------------- editor

    // NetworkManager's own editor, opened on one profile.
    //
    // pshell does not carry a connection editor of its own. nm-connection-editor
    // already round trips every property NetworkManager holds -- including the
    // 802.1X and per-plugin `vpn.data` fields a hand-written form has to
    // reimplement exactly or silently corrupt -- and it is installed wherever
    // NetworkManager is.
    function openEditor(uuid) {
        if (!uuid)
            return;
        Quickshell.execDetached(["nm-connection-editor", "-e", String(uuid)]);
    }

    // The Wi-Fi rows in the bar and the control centre carry an SSID, because
    // Quickshell.Networking models access points rather than saved profiles.
    // The lookup goes through the same queue as every other read rather than
    // through a shell interpolation, so an SSID containing a quote or a space
    // cannot turn into argv.
    function openEditorForSsid(ssid) {
        if (!ssid)
            return;
        run(["-g", "connection.uuid", "connection", "show", "id", String(ssid)], function (code, out) {
            if (code !== 0)
                return;
            const uuid = String(out).trim().split("\n")[0];
            if (uuid !== "")
                root.openEditor(uuid);
        });
    }
}
