.pragma library

// The clipboard history's actual logic: what an entry is, the deduped ring
// the shell keeps, the search, and the rows the panel draws. Kept out of
// Services/Clipboard.qml for the reason NotificationHistory.js gives -- node
// can load it through tests/load-qml-js.mjs, and dedupe-then-cap is exactly
// the arithmetic that goes wrong by one.
//
// Adapted from Omarchy's shell/plugins/clipboard/ClipboardHistory.js (MIT,
// see NOTICE.md). The shapes and the rules are theirs; what changed is that
// an entry carries an epoch `time` rather than a preformatted string, there
// is no translation layer, and the image files an edit leaves unreferenced
// are named so the shell can delete them.
//
// An entry is a plain serialisable object, written to history.json as-is:
//   { type: "text",  text, time }
//   { type: "image", path, mime, time }
// `path` is the content-addressed copy capture wrote under the state
// directory, never wherever the image came from.
//
// Either shape may also carry `pinned: true`. Pinned entries sit at the
// front of the history, in the order they were pinned, and the rolling
// history follows them newest first. The cap counts only the rolling part,
// so nothing that is copied afterwards can push a pinned entry off the end.
// The field is left out rather than written false, so a history from before
// pins existed is already in the current format.

// Newest first, as the history itself is. The default the shell falls back
// to when config.json does not say.
var defaultLimit = 500;

// The panel only ever searches and draws the start of an entry, so that is
// all it scans. One huge paste would otherwise cost hundreds of megabytes of
// string work on every keystroke in the filter. Pasting reads the full entry
// back out of history, so nothing is lost by it.
var displayTextLimit = 8192;

// Anything else on disk -- a hand edit, an older format -- comes back as one
// of the two shapes or not at all. A whitespace-only text is dropped: there
// is nothing to show for it and nothing anyone would want pasted back.
function normalizeEntry(value) {
    var entry = normalizeShape(value);
    if (entry && value.pinned === true)
        entry.pinned = true;
    return entry;
}

function normalizeShape(value) {
    if (typeof value === "string")
        return value.trim().length > 0 ? {
            type: "text",
            text: value,
            time: 0
        } : null;

    if (!value || typeof value !== "object")
        return null;

    var time = Number(value.time);
    if (!isFinite(time) || time < 0)
        time = 0;

    var type = String(value.type || "");
    if (type === "text") {
        var text = String(value.text || "");
        if (text.trim().length === 0)
            return null;
        return {
            type: "text",
            text: text,
            time: time
        };
    }

    if (type === "image") {
        var path = String(value.path || "");
        if (path === "")
            return null;
        return {
            type: "image",
            path: path,
            mime: String(value.mime || "image/png"),
            time: time
        };
    }

    return null;
}

// What two entries are "the same copy" under. An image's path is its sha256,
// so the same picture copied twice is the same key without comparing bytes.
function entryKey(entry) {
    if (!entry)
        return "";
    if (entry.type === "image")
        return "image:" + String(entry.path || "");
    return "text:" + String(entry.text || "");
}

function clampLimit(limit) {
    if (limit === undefined || limit === null)
        return defaultLimit;
    var n = Number(limit);
    if (!isFinite(n))
        return defaultLimit;
    return Math.max(0, Math.floor(n));
}

function isPinned(entry) {
    return !!entry && entry.pinned === true;
}

// Any history into the shape the shell keeps: every entry normalised,
// pinned ones first in the order they came, then the rolling ones, of which
// at most `limit` are kept. A cap of zero keeps the pins and nothing else.
function capHistory(history, limit) {
    var max = limit === Infinity ? Infinity : clampLimit(limit);
    var values = Array.isArray(history) ? history : [];
    var pinned = [];
    var rolling = [];
    for (var i = 0; i < values.length; i++) {
        var entry = normalizeEntry(values[i]);
        if (!entry)
            continue;
        if (entry.pinned)
            pinned.push(entry);
        else if (rolling.length < max)
            rolling.push(entry);
    }
    return pinned.concat(rolling);
}

// The pinned entries alone: what clearing the history leaves behind.
function pinnedOnly(history) {
    return capHistory(history, 0);
}

function pinnedCount(history) {
    var values = Array.isArray(history) ? history : [];
    var n = 0;
    for (var i = 0; i < values.length; i++) {
        if (isPinned(values[i]))
            n++;
    }
    return n;
}

// history.json's text into a history. Anything unreadable is an empty
// history rather than an exception: a corrupt file must not take the
// watchers down with it, and the next copy rewrites it whole.
//
// A limit of Infinity reads every entry. The shell loads that way, so a file
// holding more than the cap is noticed -- and cut down, images and all --
// rather than quietly read short and left on disk as it was. Pinned entries
// are always read, whatever the limit, and come back first.
function parseHistory(raw, limit) {
    var parsed;
    try {
        parsed = JSON.parse(String(raw || "[]"));
    } catch (e) {
        return [];
    }
    if (!Array.isArray(parsed))
        return [];
    return capHistory(parsed, limit === Infinity ? Infinity : clampLimit(limit));
}

// One JSON line from capture into an entry, or null for anything else --
// the watcher's stdout is the only input, but a stray line from a broken
// wl-paste should be a no-op, not a crash in a signal handler.
function parseEntryJson(line) {
    var raw = String(line || "").trim();
    if (raw === "")
        return null;
    try {
        return normalizeEntry(JSON.parse(raw));
    } catch (e) {
        return null;
    }
}

// The new entry first, any older copy of the same thing gone, capped.
// Copying something already in history moves it to the top rather than
// adding a second row, which is what makes "copy it again" the way to keep
// something near the top.
//
// Copying something that is pinned does neither: the pinned entry stays
// where it is, still pinned, and only its time moves, so it is still known
// to be the copy on the clipboard now. A second, unpinned row of it would
// be the duplicate pins exist to avoid.
//
// Returns a NEW array and never touches its input, for the reason
// NotificationHistory.append gives: QML re-evaluates bindings on a property
// only when it is reassigned.
function addEntry(history, entry, limit) {
    var max = clampLimit(limit);
    var values = Array.isArray(history) ? history : [];
    var normalized = normalizeEntry(entry);
    if (!normalized)
        return capHistory(values, max);
    // A copy arrives unpinned; only the panel or IPC pins anything.
    delete normalized.pinned;

    var key = entryKey(normalized);
    var pinned = [];
    var rolling = [normalized];
    var alreadyPinned = false;
    for (var i = 0; i < values.length; i++) {
        var existing = normalizeEntry(values[i]);
        if (!existing)
            continue;
        var same = entryKey(existing) === key;
        if (existing.pinned) {
            if (same && !alreadyPinned) {
                existing.time = normalized.time;
                alreadyPinned = true;
            }
            pinned.push(existing);
        } else if (!same) {
            rolling.push(existing);
        }
    }
    if (alreadyPinned)
        rolling.shift();
    return pinned.concat(rolling.slice(0, max));
}

// Pin or unpin the entry at `index`. A pin goes to the end of the pinned
// entries, so the ones already there keep their places. An unpinned entry
// goes back to the top of the rolling history, where it ages out like a
// fresh copy rather than vanishing at once for being old -- unless the cap
// is zero, which keeps nothing that is not pinned. The shell never unpins
// through here at zero: it forgets the entry the way Delete does, so the
// newest-copy rule in Clipboard.remove() still runs.
//
// Anything that changes nothing -- a bad index, pinning a pin -- returns the
// history as it was.
function setPinned(history, index, pinned, limit) {
    var values = capHistory(history, Infinity);
    var at = Number(index);
    if (!isFinite(at) || at < 0 || at >= values.length || Math.floor(at) !== at)
        return values;
    var entry = values[at];
    if (isPinned(entry) === !!pinned)
        return values;

    values.splice(at, 1);
    if (pinned)
        entry.pinned = true;
    else
        delete entry.pinned;
    values.splice(pinnedCount(values), 0, entry);
    return capHistory(values, limit);
}

// Where the copy that is on the clipboard now sits: the entry with the
// latest time. Usually the first rolling entry, but a pinned one copied
// again is newer than all of them. On a tie -- entries from before times
// were kept all read zero -- the rolling history's own order wins, since
// its first entry is the last thing copied. -1 for an empty history.
function newestIndex(history) {
    var values = Array.isArray(history) ? history : [];
    var best = -1;
    var bestTime = -1;
    for (var i = 0; i < values.length; i++) {
        var e = values[i];
        if (!e)
            continue;
        var time = Number(e.time) || 0;
        if (best < 0 || time > bestTime || (time === bestTime && isPinned(values[best]) && !isPinned(e))) {
            best = i;
            bestTime = time;
        }
    }
    return best;
}

function removeEntryAt(history, index) {
    var values = Array.isArray(history) ? history : [];
    var at = Number(index);
    if (!isFinite(at) || at < 0 || at >= values.length || Math.floor(at) !== at)
        return values.slice();
    var out = values.slice();
    out.splice(at, 1);
    return out;
}

// Image files that `before` referenced and `after` does not, limited to the
// shell's own image directory. Deleting an entry, clearing history and the
// cap pushing the oldest off the end all leave a file behind otherwise, and
// nothing else would ever clean it up.
//
// The directory check is the guard, not a detail: a hand-edited
// history.json naming /home/you/photo.png must never get that file
// deleted because its row was removed.
function orphanedImages(before, after, imageDir) {
    var dir = String(imageDir || "");
    if (dir === "")
        return [];
    if (dir.charAt(dir.length - 1) !== "/")
        dir += "/";

    var kept = {};
    var later = Array.isArray(after) ? after : [];
    for (var i = 0; i < later.length; i++) {
        if (later[i] && later[i].type === "image")
            kept[String(later[i].path)] = true;
    }

    var out = [];
    var seen = {};
    var earlier = Array.isArray(before) ? before : [];
    for (var j = 0; j < earlier.length; j++) {
        var e = earlier[j];
        if (!e || e.type !== "image")
            continue;
        var path = String(e.path || "");
        if (kept[path] || seen[path])
            continue;
        // Inside the directory, and not escaping it with a `..` segment.
        if (path.indexOf(dir) !== 0 || path.indexOf("/../") >= 0)
            continue;
        seen[path] = true;
        out.push(path);
    }
    return out;
}

// ---------------------------------------------------------------- files

// A file manager copies files as text/uri-list: one file:// URI per line.
// Shown raw, that is a row of percent-escapes; the panel shows file names.
function decodeFileUri(uri) {
    var value = String(uri || "").trim();
    if (value.indexOf("file://") !== 0)
        return "";
    var path = value.substring(7);
    if (path.indexOf("localhost/") === 0)
        path = path.substring(9);
    if (path.charAt(0) !== "/")
        return "";
    try {
        return decodeURIComponent(path);
    } catch (e) {
        return path;
    }
}

// Every line must be a file URI for the entry to count as files. One URI
// inside a paragraph of prose is a paragraph that mentions a file.
function filePaths(entry) {
    if (!entry || entry.type !== "text")
        return [];
    var lines = String(entry.text || "").split(/\r?\n/);
    var paths = [];
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim() === "")
            continue;
        var path = decodeFileUri(lines[i]);
        if (path === "")
            return [];
        paths.push(path);
    }
    return paths;
}

function fileName(path) {
    var parts = String(path || "").split("/");
    return parts[parts.length - 1] || String(path || "");
}

function isImagePath(path) {
    return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""));
}

// ---------------------------------------------------------------- rows

// The one-line form a row shows, and what `pshell clipboard history` prints.
// `formatTime` is optional -- Qt.formatDateTime on the QML side -- so the
// node tests read plain text without a clock in it.
function previewText(entry, formatTime) {
    if (!entry)
        return "";
    if (entry.type === "image") {
        var when = entry.time > 0 && typeof formatTime === "function" ? formatTime(entry.time) : "";
        var kind = String(entry.mime || "") === "image/png" ? "Image" : String(entry.mime || "image").replace("image/", "").toUpperCase() + " image";
        return when !== "" ? kind + " from " + when : kind;
    }
    var paths = filePaths(entry);
    if (paths.length === 1)
        return fileName(paths[0]);
    if (paths.length > 1)
        return paths.length + " files";
    return String(entry.text || "").replace(/\s+/g, " ").trim();
}

// Cut on a line break where there is one, so a list of file:// URIs never
// truncates into a bogus half-path.
function cappedEntry(entry) {
    if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit)
        return entry;
    var cut = entry.text.lastIndexOf("\n", displayTextLimit);
    var out = {
        type: "text",
        text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit),
        time: entry.time
    };
    if (entry.pinned)
        out.pinned = true;
    return out;
}

function searchableText(entry) {
    if (!entry)
        return "";
    if (entry.type === "image")
        return "image " + String(entry.mime || "");
    var paths = filePaths(entry);
    return String(entry.text || "") + (paths.length > 0 ? " " + paths.map(fileName).join(" ") : "");
}

// The rows the panel draws: pinned first, then newest first, filtered by a
// case-insensitive substring. Every pin that matches, and at most `limit` of
// the rest: the limit is there to keep the list short, and counting pins
// against it would let enough of them hide every recent copy. Each row
// remembers its `index` into history, because a filtered row's position on
// screen says nothing about where its entry is -- and the paste has to read
// the full, uncapped entry back from there.
function displayRows(history, query, limit, formatTime) {
    var values = Array.isArray(history) ? history : [];
    var needle = String(query || "").trim().toLowerCase();
    var max = limit === undefined || limit === null ? 50 : Math.max(0, Number(limit) || 0);

    var rows = [];
    var rolling = 0;
    for (var i = 0; i < values.length; i++) {
        var entry = cappedEntry(normalizeEntry(values[i]));
        if (!entry)
            continue;
        if (!entry.pinned && rolling >= max)
            break;
        if (needle !== "" && searchableText(entry).toLowerCase().indexOf(needle) < 0)
            continue;
        if (!entry.pinned)
            rolling++;

        var paths = filePaths(entry);
        var isImage = entry.type === "image";
        var isFile = paths.length > 0;
        var image = isImage ? entry.path : (paths.length === 1 && isImagePath(paths[0]) ? paths[0] : "");

        rows.push({
            index: i,
            entryType: isImage ? "image" : (isFile ? "file" : "text"),
            previewText: previewText(entry, formatTime),
            // The preview pane's text: the paths themselves for files, the
            // capped text otherwise, nothing for an image.
            fullText: isImage ? "" : (isFile ? paths.join("\n") : entry.text),
            previewImage: image,
            mime: isImage ? entry.mime : "text/plain",
            pinned: isPinned(entry)
        });
    }
    return rows;
}

// ------------------------------------------------------------ ipc lines

// What a pinned line's preview starts with in `pshell clipboard history`.
// Plain ASCII, inside the preview column rather than a column of its own, so
// `cut -f1` and anything reading two tab-separated fields still work.
var pinMarker = "[pin] ";

// One `index<TAB>preview` line, as history and pinned print them.
function historyLine(entry, index) {
    var capped = cappedEntry(normalizeEntry(entry));
    if (!capped)
        return "";
    return index + "\t" + (isPinned(capped) ? pinMarker : "") + previewText(capped);
}

// `pshell clipboard history N`: every pin, then the N newest of the rest --
// the panel's rows, unfiltered, numbered with their index into history. A
// limit of zero or less lists everything. N counts the rolling entries for
// displayRows' reason: with enough pins, "the last twenty copies" would
// otherwise be no copies at all.
function historyLines(history, limit) {
    var values = Array.isArray(history) ? history : [];
    var max = Number(limit) > 0 ? Math.floor(Number(limit)) : Infinity;
    var out = [];
    var rolling = 0;
    for (var i = 0; i < values.length; i++) {
        var pinned = isPinned(values[i]);
        if (!pinned && rolling >= max)
            break;
        var line = historyLine(values[i], i);
        if (line === "")
            continue;
        if (!pinned)
            rolling++;
        out.push(line);
    }
    return out.join("\n");
}
