pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Coding-agent usage, read off the files `omarchy-agent-usage-update` leaves
// in the state directory. Nothing here extracts anything: that tool already
// walks Claude Code's session logs, Codex's rollouts and the Fireworks
// billing API and writes one JSON record per provider. qsbar discovers those
// records, watches them, and runs the updater on a timer -- no daemon, no
// socket, no parser of its own.
//
// Which providers exist is whatever is on disk. A hardcoded list would mean
// a provider the updater learns about next month stays invisible until qsbar
// is taught about it too, and the record format already carries everything a
// panel needs to draw one.
//
// A singleton because the bar is built once per monitor. Three screens would
// otherwise mean three copies of every FileView and three updaters racing
// each other over the same files.
Singleton {
    id: root

    readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state") + "/omarchy/agents/usage"

    // Provider ids found in the usage directory, sorted so the tab strip
    // keeps its order between rescans.
    property var providerIds: []
    // The parsed records themselves, in discovery order. Views sort.
    property var records: []
    readonly property bool available: records.length > 0

    // Seconds between updater runs. The widget pushes its configured value
    // in; the floor is here because the updater talks to three network
    // endpoints and nobody wants that on a tight loop.
    property int refreshIntervalSec: 900

    // ------------------------------------------------------------ discovery

    function rescan() {
        if (!lister.running)
            lister.running = true;
    }

    Process {
        id: lister
        running: false
        // Through sh so a missing directory -- Omarchy's tooling not
        // installed at all -- is silence rather than a line of find's
        // complaint on the shell's stderr.
        command: ["sh", "-c", "find \"$1\" -maxdepth 1 -name '*.json' -printf '%f\\n' 2>/dev/null", "sh", root.usageDir]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyListing(text)
        }
    }

    function applyListing(output) {
        const ids = [];
        const lines = String(output || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            const name = lines[i].trim();
            if (name.length > 5 && name.slice(-5) === ".json")
                ids.push(name.slice(0, -5));
        }
        ids.sort();
        // Same list, same objects: reassigning the model would tear down
        // every FileView only to build identical ones, and each rebuild
        // blanks the panel for a frame.
        if (JSON.stringify(ids) !== JSON.stringify(root.providerIds))
            root.providerIds = ids;
    }

    // One watcher per record. `watchChanges` is what makes the panel live:
    // an updater run rewrites the file and the UI follows without anything
    // here polling it.
    Instantiator {
        id: watchers
        model: root.providerIds

        delegate: FileView {
            required property var modelData
            property var record: null

            path: root.usageDir + "/" + modelData + ".json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: record = root.parseRecord(text(), modelData)
            onLoadFailed: record = null
            onRecordChanged: root.rebuild()
        }

        onObjectAdded: root.rebuild()
        onObjectRemoved: root.rebuild()
    }

    function parseRecord(content, id) {
        try {
            const parsed = JSON.parse(String(content || ""));
            if (!parsed || typeof parsed !== "object")
                return null;
            // The file name is the id the widget addresses a provider by, so
            // a record that forgot to name itself still resolves an icon.
            if (!parsed.id)
                parsed.id = String(id);
            return parsed;
        } catch (e) {
            console.warn("qsbar: ignoring unreadable usage record", id, e);
            return null;
        }
    }

    function rebuild() {
        const list = [];
        for (var i = 0; i < watchers.count; i++) {
            const watcher = watchers.objectAt(i);
            if (watcher && watcher.record)
                list.push(watcher.record);
        }
        root.records = list;
    }

    // -------------------------------------------------------------- refresh

    function refresh() {
        // A run already in flight is left alone. Opening the panel three
        // times in a row must not mean three overlapping updaters.
        if (!updater.running)
            updater.running = true;
    }

    Process {
        id: updater
        running: false
        // Guarded by `command -v` so a machine without Omarchy's tooling gets
        // an empty widget rather than a failed spawn every fifteen minutes.
        command: ["sh", "-c", "command -v omarchy-agent-usage-update >/dev/null 2>&1 && exec omarchy-agent-usage-update"]
        onExited: root.rescan()

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const message = String(text || "").trim();
                if (message !== "")
                    console.warn("qsbar: agent usage update:", message);
            }
        }
    }

    Timer {
        interval: Math.max(60, root.refreshIntervalSec) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.rescan()

    // ----------------------------------------------------------- the model

    function limitsOf(record) {
        return record && record.limits ? record.limits : [];
    }

    // The highest fraction any of a provider's windows has burned, or -1 when
    // it reports no windows at all. Fireworks is the second case and it is a
    // real state, not a failure.
    function topPercent(record) {
        const limits = limitsOf(record);
        var best = -1;
        for (var i = 0; i < limits.length; i++) {
            const value = Number(limits[i].percent);
            if (isFinite(value) && value > best)
                best = value;
        }
        return best;
    }

    // The window a provider is closest to running out of, which is the one
    // worth a slot in the bar when only one of them fits.
    function peakLimit(record) {
        const limits = limitsOf(record);
        var best = null;
        for (var i = 0; i < limits.length; i++) {
            const value = Number(limits[i].percent);
            if (!isFinite(value))
                continue;
            if (!best || value > Number(best.percent))
                best = limits[i];
        }
        return best;
    }

    // Whatever is closest to exhausted goes first: the panel opens on the
    // thing that is about to stop you.
    readonly property var sorted: {
        const list = records.slice();
        list.sort((a, b) => root.topPercent(b) - root.topPercent(a));
        return list;
    }

    function recordFor(id) {
        for (var i = 0; i < records.length; i++) {
            if (String(records[i].id) === String(id))
                return records[i];
        }
        return null;
    }

    // The single tightest window across every provider, as the bar wears it.
    readonly property var peak: {
        var best = null;
        for (var i = 0; i < records.length; i++) {
            const limits = limitsOf(records[i]);
            for (var j = 0; j < limits.length; j++) {
                const value = Number(limits[j].percent);
                if (!isFinite(value))
                    continue;
                if (!best || value > best.percent)
                    best = {
                        record: records[i],
                        limit: limits[j],
                        percent: value
                    };
            }
        }
        return best;
    }

    readonly property real tokensToday: {
        var total = 0;
        for (var i = 0; i < records.length; i++)
            total += Number(records[i].todayTotalTokens) || 0;
        return total;
    }

    readonly property int sessionsToday: {
        var total = 0;
        for (var i = 0; i < records.length; i++)
            total += Number(records[i].todaySessions) || 0;
        return total;
    }

    // ------------------------------------------------------------ shaping

    // The updater writes Python's isoformat, which carries six digits of
    // fractional seconds. ECMAScript only defines three, and Qt's engine
    // takes the definition literally and returns NaN for the rest, so trim
    // before parsing rather than after finding out.
    function parseTime(iso) {
        const text = String(iso || "");
        if (text === "")
            return null;
        const stamp = Date.parse(text.replace(/\.(\d{3})\d+/, ".$1"));
        return isFinite(stamp) ? new Date(stamp) : null;
    }

    // A reset inside the day is a countdown, because that is the question
    // being asked -- how long until I can work again. Further out it is a
    // date, because "in 4d 7h" is not something anyone plans around.
    function resetText(iso, now) {
        const when = parseTime(iso);
        if (!when)
            return "";
        const then = now || new Date();
        const seconds = Math.floor((when.getTime() - then.getTime()) / 1000);
        if (seconds <= 0)
            return "now";
        if (seconds < 86400) {
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            if (hours > 0)
                return hours + "h " + minutes + "m";
            return Math.max(1, minutes) + "m";
        }
        return Qt.formatDateTime(when, "ddd HH:mm");
    }

    // The same answer as a sentence, for the views with room for one. A
    // countdown takes "in", a clock time does not: "resets in Tue 05:00" is
    // what one prefix for both reads like.
    function resetPhrase(iso, now) {
        const text = resetText(iso, now);
        if (text === "")
            return "";
        if (text === "now")
            return "resets now";
        return /^[0-9]/.test(text) ? "resets in " + text : "resets " + text;
    }

    // Two labels the collectors always write, shortened so three gauges fit
    // across a panel. Anything else is a provider's own wording and is left
    // exactly as it wrote it -- Claude's "Fable Weekly" is not the weekly.
    function windowLabel(limit) {
        if (!limit)
            return "";
        const label = String(limit.label || "");
        if (label === "Session (5-hour)")
            return "5h";
        if (label === "Weekly (7-day)")
            return "weekly";
        return String(limit.title || label);
    }

    function formatTokens(value) {
        const count = Number(value) || 0;
        if (count >= 1e9)
            return (count / 1e9).toFixed(2) + "B";
        if (count >= 1e6)
            return (count / 1e6).toFixed(2) + "M";
        if (count >= 1e3)
            return Math.round(count / 1e3) + "K";
        return String(Math.round(count));
    }

    // Everything the four token buckets add up to. The record splits input,
    // output and both cache buckets; what a "by model" list is ranking is the
    // total that model moved.
    function modelTotal(entry) {
        if (!entry)
            return 0;
        return (Number(entry.inputTokens) || 0) + (Number(entry.outputTokens) || 0) + (Number(entry.cacheReadInputTokens) || 0) + (Number(entry.cacheCreationInputTokens) || 0);
    }

    function modelRanking(record) {
        const usage = record && record.modelUsage ? record.modelUsage : ({});
        const list = [];
        for (var name in usage)
            list.push({
                name: name,
                total: modelTotal(usage[name])
            });
        list.sort((a, b) => b.total - a.total);
        return list;
    }
}
