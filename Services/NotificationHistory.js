.pragma library

// The notification centre's actual logic: the history ring, the grouping the
// panel draws, the mute check and the one-line form `pshell notifications
// history` prints. Kept out of Services/Notifications.qml so `node --test`
// can load it the way tests/load-qml-js.mjs loads ConfigPath.js -- the ring
// arithmetic is exactly the kind of thing that breaks off-by-one and exactly
// the kind of thing a test catches for free.
//
// A history record is a plain serialisable object, never the live
// Quickshell Notification: records outlive the notification they describe
// and get written to notifications.json as-is. Fields used here: `appName`,
// `desktopEntry`, `summary`, `body`, `time` (epoch milliseconds).

// Newest first, capped. Returns a NEW array and never touches its input --
// QML only re-evaluates bindings on Notifications.history when the property
// is *reassigned*, so mutating in place would write the file correctly and
// leave every panel showing the old list. ConfigPath.js records the same
// trap for Config.data.
function append(history, record, cap) {
    var limit = Number(cap);
    if (!isFinite(limit) || limit < 0)
        limit = 0;
    var out = [record];
    var source = Array.isArray(history) ? history : [];
    for (var i = 0; i < source.length; i++)
        out.push(source[i]);
    return out.slice(0, limit);
}

// What makes two records the same notification: the arrival stamp plus the
// server id and the text. id alone restarts from 1 with every session, and
// time alone collides when a burst lands inside one millisecond; together
// they only match a record against a copy of itself.
function recordKey(record) {
    return [Number(record.time) || 0, String(record.id === undefined ? "" : record.id), appKey(record), String(record.summary || "")].join("\u0001");
}

// The file's history joined with records it has not caught up on: ones that
// arrived before it finished loading, and ones a reload carried over from
// the previous generation before they were written. `extra` wins a
// duplicate, because it is the newer copy -- a record's closeReason is
// filled in after it was first saved. The result is newest first by
// arrival and capped, a NEW array for the reason append gives, and keeps
// the record objects themselves: a live notification's closed handler finds
// its record in history by identity.
function merge(history, extra, cap) {
    var limit = Number(cap);
    if (!isFinite(limit) || limit < 0)
        limit = 0;
    var byKey = {};
    var out = [];
    var add = function (list, replace) {
        var source = Array.isArray(list) ? list : [];
        for (var i = 0; i < source.length; i++) {
            var record = source[i];
            if (!record || typeof record !== "object")
                continue;
            var key = recordKey(record);
            if (byKey.hasOwnProperty(key)) {
                if (replace)
                    out[byKey[key]] = record;
                continue;
            }
            byKey[key] = out.length;
            out.push(record);
        }
    };
    add(history, false);
    add(extra, true);
    // Ties broken by position rather than trusting the engine's sort to be
    // stable, so records stamped the same millisecond keep the order they
    // were already in.
    var order = out.map(function (record, index) {
        return { record: record, index: index, time: Number(record.time) || 0 };
    });
    order.sort(function (a, b) {
        return b.time - a.time || a.index - b.index;
    });
    return order.slice(0, limit).map(function (entry) {
        return entry.record;
    });
}

// The key two apps are the same under. desktopEntry is the honest identity
// -- appName is whatever the app felt like sending and can be localised --
// but plenty of senders (notify-send included) leave desktopEntry empty, and
// those fall back to appName so they still group rather than landing in one
// anonymous pile.
function appKey(record) {
    var entry = String((record && record.desktopEntry) || "");
    if (entry !== "")
        return entry.toLowerCase();
    return String((record && record.appName) || "").toLowerCase();
}

// Groups for the panel: [{ key, appName, entries }], newest-first inside
// each group, groups ordered by their newest member. With `history` already
// newest-first both orderings are one walk in order of first appearance --
// the first record seen for an app is also its newest.
function groupByApp(history) {
    var source = Array.isArray(history) ? history : [];
    var groups = [];
    var byKey = {};
    for (var i = 0; i < source.length; i++) {
        var record = source[i];
        var key = appKey(record);
        var group = byKey[key];
        if (!group) {
            group = {
                key: key,
                appName: String((record && record.appName) || (record && record.desktopEntry) || "unknown"),
                entries: []
            };
            byKey[key] = group;
            groups.push(group);
        }
        group.entries.push(record);
    }
    return groups;
}

// Case-insensitive on both sides, because desktopEntry casing is whatever
// the sender's .desktop file used ("Firefox" and "firefox" are the same
// app) and the muted list is typed by hand on the settings page.
function isMuted(record, mutedList) {
    if (!Array.isArray(mutedList) || mutedList.length === 0)
        return false;
    var key = appKey(record);
    if (key === "")
        return false;
    for (var i = 0; i < mutedList.length; i++) {
        if (String(mutedList[i] || "").toLowerCase() === key)
            return true;
    }
    return false;
}

// The one-line form `history()` returns over IPC: "app: summary — body".
// Bodies keep their newlines when apps send them, and one record must stay
// one line, so all whitespace collapses to single spaces. A record with no
// summary and no body still prints its app name -- a blank line in a
// terminal listing reads as a bug, not as an empty notification.
function summarise(record) {
    var app = String((record && record.appName) || (record && record.desktopEntry) || "unknown");
    var flat = function (s) {
        return String(s || "").replace(/\s+/g, " ").trim();
    };
    var parts = [];
    var summary = flat(record && record.summary);
    var body = flat(record && record.body);
    if (summary !== "")
        parts.push(summary);
    if (body !== "")
        parts.push(body);
    if (parts.length === 0)
        return app;
    return app + ": " + parts.join(" — ");
}

// "3m", "2h", "yesterday" for the history rows. Pure epoch-millisecond
// arithmetic rather than Qt.formatDateTime so node can test the boundaries;
// the caller passes `now` for the same reason AgentUsage.resetText takes
// one. Beyond yesterday it counts days -- a notification centre capped at a
// hundred entries does not need calendar dates.
function relativeTime(thenMs, nowMs) {
    var then = Number(thenMs);
    var now = Number(nowMs);
    if (!isFinite(then) || !isFinite(now))
        return "";
    var seconds = Math.floor((now - then) / 1000);
    if (seconds < 60)
        return "now";
    if (seconds < 3600)
        return Math.floor(seconds / 60) + "m";
    if (seconds < 86400)
        return Math.floor(seconds / 3600) + "h";
    if (seconds < 172800)
        return "yesterday";
    return Math.floor(seconds / 86400) + "d";
}
