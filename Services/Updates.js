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
// `previous` is optional: the entries of the summary before this one, used
// only to say which source a line came from when the split files cannot.
// Answers { found, total, repo, aur, flatpak, entries, consistent }.
//
// The split files say where each update comes from, but they are not safe
// to read on their own. check.sh writes each with a plain `>` redirect --
// `checkupdates > last_updates_check_packages` -- which empties the file the
// moment it starts and leaves it empty for the seconds pacman spends syncing
// its databases; `paru -Qua > ..._aur` does the same. Read in that window
// they say "0 repo updates", and a bar that trusted them would drop from
// 552 to 55 to 11 and back on every check.
//
// The combined file is the one every writer keeps whole:
//   check.sh          builds it aside and `mv`s it into place, after the
//                     split files are final
//   update.sh         rewrites it as `cat` of the three straight after it
//                     empties each one
//   list_packages.sh  empties all four together, then writes each source to
//                     its split file and the combined one back to back
// So the split files are used only while their lines, in order, are the
// combined file's lines -- `consistent`. While they disagree, a writer is
// part-way through, and the combined file is the last finished answer: its
// lines are counted, each given the source the split files or `previous`
// knew it under, and "repo" otherwise.
//
// No combined file at all is "never checked", whatever the split files say:
// it is the state of the very first check, which touches the split files
// before it writes anything, and the combined file arrives when it is done.
//
// A state directory with only the combined file is an arch-update older
// than the split; its lines are counted as repo updates, which is what most
// of them will be.
function summarize(files, previous) {
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
        entries: [],
        consistent: true
    };
    var add = function (line, source) {
        result.entries.push(parseEntry(line, source));
        result[source] += 1;
    };
    var sources = [["repo", f.packages], ["aur", f.aur], ["flatpak", f.flatpak]];
    var split = has(f.packages) || has(f.aur) || has(f.flatpak);
    if (!has(f.combined)) {
        result.consistent = !split;
        return result;
    }
    result.found = true;
    var combined = parseLines(f.combined);
    var splitLines = [];
    for (var i = 0; i < sources.length; i++) {
        var lines = parseLines(sources[i][1]);
        for (var j = 0; j < lines.length; j++)
            splitLines.push([lines[j], sources[i][0]]);
    }
    var agree = split && splitLines.length === combined.length;
    for (var k = 0; agree && k < combined.length; k++)
        agree = splitLines[k][0] === combined[k];
    if (agree) {
        for (var a = 0; a < splitLines.length; a++)
            add(splitLines[a][0], splitLines[a][1]);
    } else {
        result.consistent = !split;
        // A line's source: the summary before this one first, since a check
        // in progress is what makes the files disagree and the split files
        // are then the half-written ones; then the split files, which is all
        // there is on the shell's first read.
        var known = {};
        for (var b = 0; b < splitLines.length; b++)
            known[splitLines[b][0]] = splitLines[b][1];
        var prev = previous || [];
        for (var c = 0; c < prev.length; c++)
            known[prev[c].line] = prev[c].source;
        for (var d = 0; d < combined.length; d++)
            add(combined[d], known[combined[d]] || "repo");
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
//   updating   - the interactive updater is running
//   fetchFailed - pshell's last check could not reach the mirrors, and the
//                count is the one from before it
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
    // Left out with no time to give: the time file is written last, so a
    // first check part-way through has the others and not it yet.
    if (s.found && state.checkedAt > 0)
        parts.push("checked " + formatAge(state.now, state.checkedAt));
    if (state.fetchFailed)
        parts.push("the last check could not reach the mirrors, so this is the one before it");
    if (state.checking)
        parts.push("checking now");
    if (state.updating)
        parts.push("updating now");
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

// A `terminal` setting as an argv: the program, then any arguments, split on
// whitespace -- "kitty -1" is ["kitty", "-1"]. Never handed to a shell, so
// nothing in it is expanded or run, and there is no quoting either: a
// program whose path has a space in it cannot be named here.
function splitTerminal(value) {
    var text = String(value === undefined || value === null ? "" : value).trim();
    return text === "" ? [] : text.split(/\s+/);
}

// Which terminal to open the updater in. `configured` is config.json's
// `terminal`, `env` is $TERMINAL, and `installed` the program names the
// probe found on PATH. Answers { argv, name, note }:
//   argv  the terminal and the arguments it was given, [] for none
//   name  its program, "" for none
//   note  why the configured terminal, or $TERMINAL, was passed over, ""
//         when it was not
// A choice that is set but not installed is passed over, so a stale
// $TERMINAL does not leave the click doing nothing; `note` is there so the
// reply to `open` can say so rather than quietly using another.
function pickTerminal(configured, env, installed) {
    var found = installed || [];
    var wanted = [["`terminal` in config.json", splitTerminal(configured)], ["$TERMINAL", splitTerminal(env)]];
    for (var t = 0; t < TERMINALS.length; t++)
        wanted.push(["", [TERMINALS[t]]]);
    var skipped = [];
    for (var i = 0; i < wanted.length; i++) {
        var argv = wanted[i][1];
        if (argv.length === 0)
            continue;
        if (found.indexOf(argv[0]) >= 0) {
            return {
                argv: argv,
                name: argv[0],
                note: skipped.join("; ")
            };
        }
        if (wanted[i][0] !== "")
            skipped.push(wanted[i][0] + " names " + argv[0] + ", which is not installed");
    }
    return {
        argv: [],
        name: "",
        note: skipped.join("; ")
    };
}

// The argv that opens `command` in `terminal`, with its window class set to
// `appId` where the terminal lets us -- which is what the compositor's float
// rule matches on. Each spells it differently, and ghostty also has to be
// told not to hand the window to a running instance, which would take the
// class with it and exit at once.
//
// `terminal` is a program, or an argv whose first word is the program and
// the rest arguments of the user's own, which go straight after it.
//
// A terminal not in the table gets `-e`, which nearly all of them take.
function terminalArgv(terminal, appId, title, command) {
    var head = Array.isArray(terminal) ? terminal.slice() : [String(terminal)];
    var cmd = command || [];
    switch (baseName(head[0])) {
    case "ghostty":
        return head.concat(["--class=" + appId, "--title=" + title, "--gtk-single-instance=false", "-e"], cmd);
    case "kitty":
        return head.concat(["--class", appId, "--title", title], cmd);
    case "alacritty":
        return head.concat(["--class", appId, "--title", title, "-e"], cmd);
    case "foot":
        return head.concat(["--app-id=" + appId, "--title=" + title], cmd);
    case "wezterm":
        return head.concat(["start", "--class", appId, "--"], cmd);
    default:
        return head.concat(["-e"], cmd);
    }
}

// --------------------------------------------------------------- refresh

// The lock the interactive updater holds for as long as it runs
// (full_upgrade.sh: `exec {fd}> /tmp/${name}.lock` then `flock -n`), and the
// unit the timer starts. `name` is "arch-update" in the script itself, so
// both are the same under cachy-update.
var LOCK = "/tmp/arch-update.lock";
var UNIT = "arch-update.service";

// What a refresh runs, as sh with its inputs as arguments rather than
// spliced into the text. In order:
//
//   1. Refuse while the updater holds its lock. A check started mid-update
//      can write the list from before `pacman -Syu` after update.sh has
//      emptied it, and it would stay wrong until the next day's check.
//      flock's conflict code is set apart (-E 75) so a lock it cannot open
//      at all is not mistaken for a running updater.
//   2. Start the timer's own unit when it is there, rather than running the
//      check as a child. It is Type=oneshot, so `start` returns when the
//      check has finished, and it joins a check the timer already has
//      running rather than racing it for the same files. Once started it
//      belongs to systemd: a reload of the shell kills only this sh, and
//      the check still finishes, cleans up its database copy and writes
//      the time.
//   3. Otherwise -- no systemd user manager, or no unit -- run
//      `<tool> --check` directly, as before.
//
// A check whose `checkupdates` could not reach the mirrors still exits 0,
// with empty files, which read as "up to date". checkupdates says
// "Cannot fetch updates" on stderr (it is not translated), so look for that:
// in the unit's journal, by this run's invocation id, or in the direct
// check's own stderr.
//
// Prints one word per outcome, for parseRefresh: busy, systemd or direct,
// then fetch-failed if it was. Exits with the check's own code.
var REFRESH_SCRIPT = 'tool=$1 lock=$2 unit=$3\n'
    + 'if command -v flock >/dev/null 2>&1; then\n'
    + '    flock -n -E 75 "$lock" true 2>/dev/null\n'
    + '    if [ $? -eq 75 ]; then echo busy; exit 0; fi\n'
    + 'fi\n'
    + 'if command -v systemctl >/dev/null 2>&1 && systemctl --user cat "$unit" >/dev/null 2>&1; then\n'
    + '    echo systemd\n'
    + '    systemctl --user start "$unit"\n'
    + '    code=$?\n'
    + '    id=$(systemctl --user show -p InvocationID --value "$unit" 2>/dev/null)\n'
    + '    if [ -n "$id" ] && journalctl --user -o cat --no-pager "_SYSTEMD_INVOCATION_ID=$id" 2>/dev/null | grep -q "Cannot fetch updates"; then echo fetch-failed; fi\n'
    + 'else\n'
    + '    echo direct\n'
    + '    err=$("$tool" --check 2>&1 >/dev/null)\n'
    + '    code=$?\n'
    + '    if printf "%s\\n" "$err" | grep -q "Cannot fetch updates"; then echo fetch-failed; fi\n'
    + 'fi\n'
    + 'exit $code\n';

// `lock` and `unit` default to arch-update's; the tests point them elsewhere.
function refreshArgv(tool, lock, unit) {
    return ["sh", "-c", REFRESH_SCRIPT, "pshell-updates-refresh", String(tool), lock || LOCK, unit || UNIT];
}

// What the refresh script printed, as { busy, via, fetchFailed }. `via` is
// "systemd", "direct", or "" when it did not get that far.
function parseRefresh(text) {
    var words = parseLines(text);
    var via = "";
    if (words.indexOf("systemd") >= 0)
        via = "systemd";
    else if (words.indexOf("direct") >= 0)
        via = "direct";
    return {
        busy: words.indexOf("busy") >= 0,
        via: via,
        fetchFailed: words.indexOf("fetch-failed") >= 0
    };
}

// The argv that asks whether the updater holds its lock: prints "held" if
// it does. The same flock as the refresh script's first step.
function lockProbeArgv(lock) {
    return ["sh", "-c", 'flock -n -E 75 "$1" true 2>/dev/null; [ $? -ne 75 ] || echo held', "pshell-updates-lock", lock || LOCK];
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
