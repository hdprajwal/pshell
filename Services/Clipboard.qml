pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Widgets.Clipboard as ClipboardLayer
import "ClipboardHistory.js" as History

// pshell's clipboard history: the watchers that record copies, the history
// file, the panel's wanted-open state, and pshell.clipboard.
//
// Modelled on Omarchy's first-party clipboard plugin, and for the same
// reason it exists: the shell is already running, so it can own the two
// `wl-paste --watch` processes itself rather than asking cliphist or
// elephant to keep a daemon up. The watchers are this shell's children,
// started under `setpriv --pdeathsig TERM` so the kernel takes them down
// with it however it exits.
//
// A singleton for the reason WallpaperCarousel gives: anything inside a
// per-screen widget exists once per screen, and two monitors would mean two
// pairs of watchers recording every copy twice. Kept alive from shell.qml,
// because the watchers have to run whether or not anyone has opened the
// panel -- a history that starts at the first SUPER+CTRL+V is no history.
//
// Everything that runs outside QML -- reading a copy, reaping, pasting --
// is Services/clipboard.sh; the rules about what an entry is are
// Services/ClipboardHistory.js, where node tests them.
Singleton {
    id: root

    // --------------------------------------------------------------- state

    // Newest first, capped at `limit`. Plain records, written to
    // history.json as they are.
    property var history: []

    readonly property int limit: Config.clipboard.historySize
    readonly property bool recording: limit > 0

    // ~/.local/state/pshell/clipboard, under the directory notifications.json
    // is in, for the reason Notifications.qml gives: history is state the
    // shell owns, not config. A directory of its own because it is the one
    // thing there that must be private -- clipboard.sh init makes it 0700.
    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        const base = xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state";
        return base + "/pshell/clipboard";
    }
    readonly property string historyPath: stateDir + "/history.json"
    readonly property string imageDir: stateDir + "/images"
    readonly property string script: Quickshell.shellDir + "/Services/clipboard.sh"

    // ------------------------------------------------------------ history

    // A capture line from a watcher or the snapshot. The time is stamped
    // here rather than in the script, because the script runs once per copy
    // and the shell's clock is the one the panel formats.
    function _addJson(line) {
        const entry = History.parseEntryJson(line);
        if (!entry || !root.recording)
            return;
        entry.time = Date.now();
        // Debounced: a browser's image copy fires both watchers at once,
        // and nobody is waiting on a copy to reach the disk.
        root._replace(History.addEntry(root.history, entry, root.limit), true);
        root._unsaved = root._unsaved.concat([entry]);
        carry.pending = JSON.stringify(root._unsaved);
    }

    // Forgetting the newest entry, or all of them, also takes that copy off
    // the clipboard. It is almost certainly still there, and the snapshot
    // every watcher start takes -- each config reload, each restart -- would
    // otherwise record it again: delete a password, save a QML file, and it
    // is back in the history file.
    function remove(index) {
        const next = History.removeEntryAt(root.history, index);
        if (next.length === root.history.length)
            return;
        if (index === 0)
            Quickshell.execDetached([root.script, "clear"]);
        root._replace(next);
    }

    function clear() {
        if (root.history.length > 0)
            Quickshell.execDetached([root.script, "clear"]);
        root._replace([]);
    }

    // Every edit goes through here, so no edit can forget the two things
    // that follow one: the file is rewritten, and an image no entry points
    // at any more is deleted -- capture stored it, and nothing else ever
    // would clean it up.
    //
    // A copy may wait half a second to be written. Forgetting never waits:
    // somebody deleting an entry wants it off the disk now.
    function _replace(next, later) {
        const gone = History.orphanedImages(root.history, next, root.imageDir);
        root.history = next;
        if (gone.length > 0)
            Quickshell.execDetached(["rm", "-f", "--"].concat(gone));
        if (later)
            saveTimer.restart();
        else
            root._save();
    }

    // Lowering the cap forgets the copies past it now, rather than at the
    // next copy -- including all of them, at zero.
    onLimitChanged: {
        if (root._loaded && root.history.length > root.limit)
            root._replace(root.history.slice(0, root.limit));
    }

    // ------------------------------------------------------------- paste

    // Back onto the clipboard, by index into history. paste also types
    // Shift+Insert into whatever has focus once the panel is gone; copy only
    // copies. The full entry is read from history here, not from the row the
    // panel drew, because the panel only ever holds the first 8 KiB of it.
    function paste(index, copyOnly) {
        const entry = root.history[index];
        if (!entry)
            return;
        root.close();

        const verb = copyOnly ? "copy" : "paste";
        if (entry.type === "image") {
            paster.pending = "";
            paster.command = [root.script, verb, "--type", entry.mime, "--file", entry.path];
        } else {
            // Over stdin, not argv: one argument tops out at 128 KiB, and a
            // copied log file does not.
            paster.pending = entry.text;
            paster.command = [root.script, verb];
        }
        paster.running = false;
        paster.stdinEnabled = true;
        paster.running = true;
    }

    Process {
        id: paster

        property string pending: ""

        onStarted: {
            if (paster.pending !== "")
                paster.write(paster.pending);
            paster.pending = "";
            // Closing stdin is what ends the script's `cat`.
            paster.stdinEnabled = false;
        }
    }

    // ------------------------------------------------------------- panel

    property bool visible: false

    // Captured once per open, never bound, for the carousel's reason: a
    // binding to the focused monitor would drag the panel -- and its
    // keyboard grab -- to wherever the pointer wanders while it is up.
    property var screen: null

    function open() {
        root.screen = root._focusedScreen();
        loader.active = true;
        root.visible = true;
    }

    function close() {
        root.visible = false;
    }

    function toggle() {
        if (root.visible)
            close();
        else
            open();
    }

    // Same resolution WallpaperCarousel uses. No Hyprland -- a nested
    // compositor, say -- means no focus answer, and the first screen is the
    // honest fallback.
    function _focusedScreen() {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        if (mon) {
            for (var i = 0; i < screens.length; i++) {
                if (screens[i].name === mon.name)
                    return screens[i];
            }
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // Built on first open and kept after, like the carousel: nothing on
    // screen until somebody asks, and no re-decoding every thumbnail on each
    // open after that.
    LazyLoader {
        id: loader
        active: false

        ClipboardLayer.ClipboardOverlay {}
    }

    // -------------------------------------------------------- persistence

    // The directory exists, 0700, and nothing in it is readable by anyone
    // else. Nothing is read or written there before.
    property bool _prepared: false
    property bool _loaded: false

    // The guard Notifications.qml carries, for the same reason: a write
    // before the load finished would truncate the history it was about to
    // read. The watchers wait on the load too, so the snapshot at start
    // cannot be the first thing written over a file nobody has read yet.
    //
    // Compact, not indented: this is the whole history, rewritten on every
    // copy, and nobody reads it by eye.
    function _save() {
        saveTimer.stop();
        if (!root._loaded)
            return;
        historyFile.setText(JSON.stringify(root.history) + "\n");
        root._unsaved = [];
        carry.pending = "";
    }

    // Half a second for the reason Notifications.qml gives for its own:
    // copies come in bursts, and each one would otherwise be a full rewrite.
    Timer {
        id: saveTimer

        interval: 500
        onTriggered: root._save()
    }

    // The copies the timer has not written yet. A config reload tears this
    // generation down without running a single destruction handler, so they
    // cannot be flushed on the way out; instead they ride across the reload
    // here and the next generation adds them back once it has loaded. Only
    // the unsaved copies, not the history, so keeping it current costs one
    // small stringify per copy.
    property var _unsaved: []

    PersistentProperties {
        id: carry

        reloadableId: "pshellClipboardUnsaved"
        property string pending: ""
    }

    // Read every entry, not just `limit` of them. A cap lowered while the
    // shell was down -- or set to zero, which the README promises forgets
    // everything -- would otherwise leave the rest of the file, and every
    // image it names, on disk for good, since nothing would ever rewrite it.
    function _onLoaded(raw) {
        if (!root._prepared)
            return;
        const full = History.parseHistory(raw, Infinity);
        root.history = full;
        root._loaded = true;
        if (full.length > root.limit)
            root._replace(full.slice(0, root.limit));

        const carried = History.parseHistory(carry.pending, Infinity);
        carry.pending = "";
        if (carried.length === 0 || !root.recording)
            return;
        var next = root.history;
        for (var i = 0; i < carried.length; i++)
            next = History.addEntry(next, carried[i], root.limit);
        root._replace(next);
    }

    // FileView does not create parent directories, and the history's has to
    // be private before anything lands in it, so this runs to completion
    // before the file is even named.
    Process {
        id: prepare

        running: true
        command: [root.script, "init", root.stateDir]
        environment: ({
                PSHELL_CLIPBOARD_IMAGES: root.imageDir
            })
        onExited: root._prepared = true
    }

    FileView {
        id: historyFile

        path: root._prepared ? root.historyPath : ""
        // Not watched, for the reason notifications.json is not: the shell
        // is the only writer. Watching it would also reload over a copy that
        // arrived between a write and its change signal.
        watchChanges: false
        blockWrites: false
        atomicWrites: true
        printErrors: false

        onLoaded: root._onLoaded(text())
        // No history yet is the normal first run, not an error.
        onLoadFailed: root._onLoaded("[]")
    }

    // ----------------------------------------------------------- watchers

    // Whether the watchers should be up: once history is loaded, for as long
    // as the cap leaves anything to record.
    readonly property bool watching: _loaded && recording

    onWatchingChanged: {
        if (root.watching)
            root._startWatching();
        else {
            textWatcher.running = false;
            imageWatcher.running = false;
        }
    }

    // Reap first, then snapshot what is on the clipboard now, then watch.
    // The snapshot is how a copy made while the shell was down -- or before
    // it first came up this session -- still makes it into history.
    function _startWatching() {
        if (!root.watching || reaper.running)
            return;
        reaper.running = true;
    }

    Process {
        id: reaper

        command: [root.script, "reap"]
        onExited: {
            if (!root.watching)
                return;
            snapshot.running = true;
            textWatcher.running = true;
            imageWatcher.running = true;
        }
    }

    Process {
        id: snapshot

        command: [root.script, "capture"]
        environment: ({
                PSHELL_CLIPBOARD_IMAGES: root.imageDir
            })
        stdout: StdioCollector {
            onStreamFinished: root._addJson(text)
        }
    }

    // `--type text` lets wl-paste pick the best text type on offer;
    // image/png is the one every screenshot tool and browser offers. Other
    // image types are still caught by the snapshot at start.
    Process {
        id: textWatcher

        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.script, "capture", "text"]
        environment: ({
                PSHELL_CLIPBOARD_IMAGES: root.imageDir
            })
        stdout: SplitParser {
            onRead: line => root._addJson(line)
        }
        onExited: restart.restart()
    }

    Process {
        id: imageWatcher

        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.script, "capture", "image/png"]
        environment: ({
                PSHELL_CLIPBOARD_IMAGES: root.imageDir
            })
        stdout: SplitParser {
            onRead: line => root._addJson(line)
        }
        onExited: restart.restart()
    }

    // A watcher that dies takes the history with it silently: copying still
    // works, the panel still opens, and everything already in it is still
    // there, so nothing looks wrong until somebody misses a copy. Omarchy
    // learned that one; bring it back after a second instead.
    Timer {
        id: restart

        interval: 1000
        onTriggered: {
            if (!root.watching)
                return;
            if (!textWatcher.running)
                textWatcher.running = true;
            if (!imageWatcher.running)
                imageWatcher.running = true;
        }
    }

    // ---------------------------------------------------------------- ipc

    IpcHandler {
        target: "pshell.clipboard"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        // No confirmation, unlike Shift+Delete in the panel: the PowerMenu
        // rule. A script or a keybind asking to clear has already decided,
        // and a dialog nobody is looking at would leave the history there.
        function clear(): void {
            root.clear();
        }

        function count(): int {
            return root.history.length;
        }

        // One line per entry, newest first, numbered with the index copy
        // and remove take -- so `pshell clipboard history 20 | fzf` can pick
        // one and hand its number back.
        function history(limit: int): string {
            const take = limit > 0 ? Math.min(limit, root.history.length) : root.history.length;
            const out = [];
            for (var i = 0; i < take; i++)
                out.push(i + "\t" + History.previewText(History.cappedEntry(root.history[i])));
            return out.join("\n");
        }

        // Back onto the clipboard without typing anything: from a script
        // there is no telling which window would get the keystroke.
        function copy(index: int): void {
            root.paste(index, true);
        }

        function remove(index: int): void {
            root.remove(index);
        }
    }
}
