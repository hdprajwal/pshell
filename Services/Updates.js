.pragma library

// The update indicator's reading of arch-update's state files, and the
// command lines it builds to act on them. Kept out of Services/Updates.qml
// so `node --test` can load it the way tests/load-qml-js.mjs loads the
// others: a line format with three spellings and a terminal table with six
// entries are the kind of thing that is wrong in one corner nobody clicks.
//
// The files are arch-update's, written by `arch-update --check` and by the
// interactive updater (CachyOS's cachy-update is the same script under a
// second name, and writes to the same directory). Under
// ${XDG_STATE_HOME:-~/.local/state}/arch-update/:
//
//   last_updates_check_packages  repo updates, `name old -> new`
//   last_updates_check_aur       AUR updates, the same shape
//   last_updates_check_flatpak   Flatpak updates, `Name version`, where the
//                                name may have spaces in it
//   last_updates_check           all three concatenated
//   last_updates_check_time      epoch seconds, then a human date
//
// With `NoVersion` in arch-update.conf the repo and AUR lines are a bare
// name and the Flatpak ones a bare application name.

// --------------------------------------------------------------- reading

// The non-blank lines of a file, with any colour codes taken out. --check
// strips them itself; this is for the files the interactive updater writes,
// and for anything else that ends up there.
function parseLines(text) {
    var raw = String(text === undefined || text === null ? "" : text);
    var out = [];
    var lines = raw.replace(/\x1B\[[0-9;]*m/g, "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line !== "")
            out.push(line);
    }
    return out;
}

// One pending update. `source` is "repo", "aur" or "flatpak"; `from` and
// `to` are empty where the line does not carry them.
//
// Flatpak lines are the whole line as the name: flatpak's display names
// have spaces ("Mesa (Extra) 26.2.2"), so there is no telling the name from
// the version by splitting, and guessing would print half a name.
function parseEntry(line, source) {
    var text = String(line).trim();
    var entry = {
        source: source,
        name: text,
        from: "",
        to: "",
        line: text
    };
    if (source === "flatpak")
        return entry;
    var m = text.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
    if (m) {
        entry.name = m[1];
        entry.from = m[2];
        entry.to = m[3];
        return entry;
    }
    entry.name = text.split(/\s+/)[0];
    return entry;
}

// What the state files add up to. `files` carries each file's text, or null
// for a file that is not there:
//   packages, aur, flatpak, combined
// Answers { found, total, repo, aur, flatpak, entries }.
//
// The three split files are read rather than the combined one because they
// say where each update comes from, and because the updater empties each as
// it finishes that part -- the count goes down as it works.
//
// The combined file is the fallback for a state directory that has it and
// none of the others, which is an arch-update older than the split: its
// lines are counted as repo updates, which is what most of them will be.
function summarize(files) {
    var f = files || {};
    var has = function (v) {
        return v !== undefined && v !== null;
    };
    var result = {
        found: false,
        total: 0,
        repo: 0,
        aur: 0,
        flatpak: 0,
        entries: []
    };
    var split = has(f.packages) || has(f.aur) || has(f.flatpak);
    var sources = split ? [["repo", f.packages], ["aur", f.aur], ["flatpak", f.flatpak]] : [["repo", f.combined]];
    for (var i = 0; i < sources.length; i++) {
        var source = sources[i][0];
        var text = sources[i][1];
        if (!has(text))
            continue;
        result.found = true;
        var lines = parseLines(text);
        for (var j = 0; j < lines.length; j++)
            result.entries.push(parseEntry(lines[j], source));
        result[source] += lines.length;
    }
    result.total = result.repo + result.aur + result.flatpak;
    return result;
}

// The epoch on the first line of last_updates_check_time, or 0 for a file
// that does not start with one.
function parseCheckTime(text) {
    var first = parseLines(text)[0] || "";
    return /^\d+$/.test(first) ? Number(first) : 0;
}

// --------------------------------------------------------------- writing

function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many);
}

// "10 repo, 1 AUR, 1 Flatpak", leaving out the sources with nothing.
function breakdown(summary) {
    var parts = [];
    if (summary.repo > 0)
        parts.push(summary.repo + " repo");
    if (summary.aur > 0)
        parts.push(summary.aur + " AUR");
    if (summary.flatpak > 0)
        parts.push(summary.flatpak + " Flatpak");
    return parts.join(", ");
}

// How long ago a check was, in the largest unit that fits. A check from the
// future -- a clock that moved back -- is "just now" rather than a negative
// number of minutes.
function formatAge(nowSec, thenSec) {
    if (!thenSec)
        return "never";
    var s = Math.max(0, Math.floor(nowSec - thenSec));
    if (s < 60)
        return "just now";
    var min = Math.floor(s / 60);
    if (min < 60)
        return plural(min, "minute", "minutes") + " ago";
    var h = Math.floor(min / 60);
    if (h < 48)
        return plural(h, "hour", "hours") + " ago";
    return plural(Math.floor(h / 24), "day", "days") + " ago";
}

// The one line `pshell updates status` prints. `state` carries:
//   available  - the tool's name, or "" when neither is installed
//   summary    - what summarize() answered
//   checkedAt  - epoch seconds of the last check, or 0
//   now        - epoch seconds now
//   checking   - a check pshell started is still running
function statusLine(state) {
    if (!state.available)
        return "unavailable: neither cachy-update nor arch-update is installed";
    var s = state.summary;
    var parts = [];
    if (!s.found)
        parts.push("never checked");
    else if (s.total === 0)
        parts.push("up to date");
    else
        parts.push(plural(s.total, "update", "updates") + " (" + breakdown(s) + ")");
    if (s.found)
        parts.push("checked " + formatAge(state.now, state.checkedAt));
    if (state.checking)
        parts.push("checking now");
    parts.push("by " + state.available);
    return parts.join(", ");
}

// What `pshell updates list` prints: one update per line, its source, a
// tab, and the line as arch-update wrote it. The source first, and the tab,
// so `cut -f1 | sort | uniq -c` and `grep ^aur` both work.
function listText(entries) {
    var out = [];
    for (var i = 0; i < entries.length; i++)
        out.push(entries[i].source + "\t" + entries[i].line);
    return out.join("\n");
}

// ------------------------------------------------------------- terminal

// The terminals pshell knows how to name a window in, most likely first.
// The order is the guess when nothing is configured.
var TERMINALS = ["ghostty", "kitty", "alacritty", "foot", "wezterm"];

function baseName(path) {
    var p = String(path || "");
    return p.substring(p.lastIndexOf("/") + 1);
}

// Which terminal to open the updater in. `configured` is config.json's
// `terminal`, `env` is $TERMINAL, and `installed` the subset of the
// candidates the probe found on PATH. A choice that is set but not
// installed is passed over, so a stale $TERMINAL does not leave the click
// doing nothing. "" when there is nothing to use.
function pickTerminal(configured, env, installed) {
    var found = installed || [];
    var wanted = [String(configured || "").trim(), String(env || "").trim()].concat(TERMINALS);
    for (var i = 0; i < wanted.length; i++) {
        if (wanted[i] !== "" && found.indexOf(wanted[i]) >= 0)
            return wanted[i];
    }
    return "";
}

// The argv that opens `command` in `terminal`, with its window class set to
// `appId` where the terminal lets us -- which is what the compositor's float
// rule matches on. Each spells it differently, and ghostty also has to be
// told not to hand the window to a running instance, which would take the
// class with it and exit at once.
//
// A terminal not in the table gets `-e`, which nearly all of them take.
function terminalArgv(terminal, appId, title, command) {
    var t = String(terminal);
    var cmd = command || [];
    switch (baseName(t)) {
    case "ghostty":
        return [t, "--class=" + appId, "--title=" + title, "--gtk-single-instance=false", "-e"].concat(cmd);
    case "kitty":
        return [t, "--class", appId, "--title", title].concat(cmd);
    case "alacritty":
        return [t, "--class", appId, "--title", title, "-e"].concat(cmd);
    case "foot":
        return [t, "--app-id=" + appId, "--title=" + title].concat(cmd);
    case "wezterm":
        return [t, "start", "--class", appId, "--"].concat(cmd);
    default:
        return [t, "-e"].concat(cmd);
    }
}

// The Hyprland rule that floats the updater's window, as Lua for
// `hyprctl eval`. Named, so adding it again on every click replaces the one
// before rather than stacking copies. Matched on the class terminalArgv set,
// so it touches no other window.
//
// `float` false sends the same rule switched off. A rule outlives the click
// that added it -- it is the compositor's until Hyprland reloads its config
// -- so turning `updates.float` off has to say so, or the window would keep
// floating on the strength of an earlier click.
function floatRule(appId, float) {
    var pattern = "^(" + String(appId).replace(/[.]/g, "\\\\.") + ")$";
    var head = 'hl.window_rule({ name = "pshell-updates", match = { class = "' + pattern + '" }, ';
    if (float === false)
        return head + "enabled = false })";
    return head + 'float = true, size = "monitor_w*0.6 monitor_h*0.7", center = true })';
}
