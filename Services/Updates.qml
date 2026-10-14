pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Updates.js" as Model

// Pending package updates, as arch-update sees them.
//
// pshell does not check for updates itself. CachyOS ships cachy-update, a
// fork of arch-update, and both come with a systemd user timer that runs
// `arch-update --check` a couple of minutes after boot and once a day. The
// check writes what it found into ${XDG_STATE_HOME:-~/.local/state}/arch-update/
// -- the same directory for both, since cachy-update is the same script
// under a second name -- and this service watches those files. So the count
// changes the moment the timer's check finishes, and pshell adds no network
// traffic and no pacman database reads of its own. Omarchy's indicator, which
// this follows, polls a checker every six hours instead; with the distro's
// own timer already doing the checking, a poll would only be a second,
// staler copy of it.
//
// What the shell does run, it runs on request:
//
//   refresh  `<tool> --check`, the same command the timer runs, as a child
//            of the shell. It sends arch-update's own "N updates available"
//            notification when the list has changed since the last check,
//            exactly as the timer's run does; pshell leaves that alone.
//   open     the interactive `<tool>` in a terminal: news, confirmation,
//            sudo, then the post-update chores. Detached, never a child:
//            a reload of the shell's QML stops its children, and a pacman
//            transaction is the last thing that should go with it. The
//            updater rewrites the state files as it goes, so the watch is
//            all it takes for the bar to catch up once it has finished.
//
// A singleton for IdleInhibit's reason: the widget exists once per monitor,
// and one watch is enough for all of them. Kept alive from shell.qml so
// `pshell updates` answers on a bar with no updates widget.
Singleton {
    id: root

    // --------------------------------------------------------------- state

    // "cachy-update", "arch-update", or "" when neither is installed. The
    // name is also the command: they take the same options.
    property string tool: ""
    property bool probed: false
    readonly property bool available: tool !== ""

    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/arch-update";
    }

    // What summarize() made of the files: found, total, repo, aur, flatpak,
    // entries.
    property var summary: Model.summarize({})
    readonly property int count: summary.total
    // Epoch seconds of the last check, or 0.
    property real checkedAt: 0

    // True while a check pshell started is running. The timer's own checks
    // are invisible to us until they write.
    readonly property bool checking: checker.running

    // Installed terminals, from the probe, and the one the updater opens in.
    property var terminals: []
    readonly property string terminal: Model.pickTerminal(Config.terminal, Quickshell.env("TERMINAL"), terminals)

    readonly property string missingError: "error: neither cachy-update nor arch-update is installed. On CachyOS: sudo pacman -S cachy-update; on Arch: sudo pacman -S arch-update"

    // The class the updater's terminal window gets, and the float rule
    // matches on.
    readonly property string appId: "pshell.updates"

    // ------------------------------------------------------------ actions

    // Each returns "" on success or the line to hand back to a script, so
    // the IPC handler can answer with it and a click can ignore it.
    function refresh() {
        if (!root.available)
            return root._refused();
        if (!checker.running) {
            checker.command = [root.tool, "--check"];
            checker.running = true;
        }
        return "";
    }

    function open() {
        if (!root.available)
            return root._refused();
        if (root.terminal === "")
            return "error: no terminal to run " + root.tool + " in. Set `terminal` in config.json, or install one of ghostty, kitty, alacritty, foot or wezterm";

        // The rule first, then the terminal, in one sh so they happen in that
        // order: a rule that lands after the window has mapped floats
        // nothing. `hyprctl eval` is Hyprland's Lua config; on anything else
        // it fails quietly and the window opens however the compositor likes.
        const rule = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? Model.floatRule(root.appId, Config.updates.float) : "";
        const argv = Model.terminalArgv(root.terminal, root.appId, "System update", [root.tool]);
        Quickshell.execDetached(["sh", "-c", 'if [ -n "$1" ]; then hyprctl eval "$1" >/dev/null 2>&1; fi; shift; exec "$@"', "pshell-updates", rule].concat(argv));
        return "";
    }

    function status() {
        // "Not yet asked" and "not installed" are different answers, as
        // they are for the nightlight.
        if (!root.probed)
            return "still looking for cachy-update or arch-update";
        return Model.statusLine({
            available: root.tool,
            summary: root.summary,
            checkedAt: root.checkedAt,
            now: Date.now() / 1000,
            checking: root.checking
        });
    }

    function list() {
        return Model.listText(root.summary.entries);
    }

    // Asked again on every refusal, so installing cachy-update while the
    // shell runs needs no restart -- just a second try. The Nightlight's
    // answer to the same question.
    function _refused() {
        root._probe();
        return root.probed ? root.missingError : "error: still looking for cachy-update, try again in a moment";
    }

    // ------------------------------------------------------------- probe

    // Which tool, and which terminals, through sh's `command -v`: the PATH
    // lookup the shell's own children will get. cachy-update first, since
    // on CachyOS both names are installed and that is the one the distro
    // means you to see.
    //
    // The command is built here, each time, rather than bound: the terminal
    // named in config.json is one of the things looked for, and a binding
    // might not have caught up with a change by the time it is run.
    function _probe() {
        if (prober.running)
            return;
        prober.command = ["sh", "-c", 'for t in cachy-update arch-update; do if command -v "$t" >/dev/null 2>&1; then echo "$t"; break; fi; done; echo ---; shift; for t in "$@"; do if [ -n "$t" ] && command -v "$t" >/dev/null 2>&1; then echo "$t"; fi; done', "sh", "--"].concat(Model.TERMINALS, [Config.terminal, Quickshell.env("TERMINAL") || ""]);
        prober.running = true;
    }

    Component.onCompleted: root._probe()

    // A terminal named in config.json after the probe ran has not been
    // looked for yet.
    readonly property string _configuredTerminal: Config.terminal
    on_ConfiguredTerminalChanged: root._probe()

    Process {
        id: prober

        stdout: StdioCollector {
            id: proberOut
        }
        onExited: {
            const halves = proberOut.text.split("---");
            root.tool = (halves[0] || "").trim();
            root.terminals = Model.parseLines(halves[1] || "");
            root.probed = true;
        }
    }

    // ------------------------------------------------------------- check

    Process {
        id: checker

        // Read once more when it has finished: the watch has very likely
        // seen it already, but a state directory that did not exist before
        // this check has nothing being watched yet.
        onExited: code => {
            if (code !== 0)
                console.warn("pshell:", root.tool, "--check exited with", code);
            root._reloadAll();
        }
    }

    // ------------------------------------------------------------- watch

    // One FileView per file. watchChanges sees the timer's check, a refresh,
    // `<tool> -l`, and the interactive updater, which all write here.
    //
    // A file that is not there loads as absent, which summarize() reads as
    // "never checked" rather than as "up to date".
    component StateFile: FileView {
        property bool present: false
        property string content: ""

        // Raised on every read, whatever it found. A signal rather than a
        // call to `settle`: an inline component cannot see this file's ids.
        signal read

        blockLoading: false
        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onLoaded: {
            present = true;
            content = text();
            read();
        }
        onLoadFailed: {
            present = false;
            content = "";
            read();
        }
    }

    StateFile {
        id: packagesFile
        path: root.stateDir + "/last_updates_check_packages"
        onRead: settle.restart()
    }

    StateFile {
        id: aurFile
        path: root.stateDir + "/last_updates_check_aur"
        onRead: settle.restart()
    }

    StateFile {
        id: flatpakFile
        path: root.stateDir + "/last_updates_check_flatpak"
        onRead: settle.restart()
    }

    StateFile {
        id: combinedFile
        path: root.stateDir + "/last_updates_check"
        onRead: settle.restart()
    }

    // Written last by a check, so a change here is also the moment to look
    // at the others again -- see `settle`.
    StateFile {
        id: timeFile
        path: root.stateDir + "/last_updates_check_time"
        onRead: settle.restart()
    }

    function _reloadAll() {
        packagesFile.reload();
        aurFile.reload();
        flatpakFile.reload();
        combinedFile.reload();
        timeFile.reload();
    }

    // A check rewrites five files in a row, and the updater empties three
    // one at a time, so the count waits for a quiet moment rather than
    // stepping through every file on the way -- a bar that read 6, 3, 2, 0
    // in half a second would look broken.
    Timer {
        id: settle

        interval: 300
        onTriggered: {
            const value = file => file.present ? file.content : null;
            root.summary = Model.summarize({
                packages: value(packagesFile),
                aur: value(aurFile),
                flatpak: value(flatpakFile),
                combined: value(combinedFile)
            });
            root.checkedAt = Model.parseCheckTime(timeFile.content);
        }
    }

    // The one poll, and only while there is nothing to watch: a directory
    // that does not exist yet -- arch-update installed, the timer not yet
    // run -- gives the FileViews nothing to see being created. Reading five
    // missing files once a minute costs nothing, and stops the moment the
    // first check has written them.
    Timer {
        interval: 60000
        repeat: true
        running: root.available && !root.summary.found
        onTriggered: root._reloadAll()
    }

    // ---------------------------------------------------------------- ipc

    IpcHandler {
        target: "pshell.updates"

        // Starts a check and answers at once: a check takes seconds, and an
        // IPC call cannot wait for it. `status` says when it has finished.
        function refresh(): string {
            const err = root.refresh();
            return err !== "" ? err : "checking for updates with " + root.tool;
        }

        // Opens the interactive updater in a terminal.
        function open(): string {
            const err = root.open();
            return err !== "" ? err : "opened " + root.tool + " in " + root.terminal;
        }

        function count(): int {
            return root.count;
        }

        // One update per line: its source, a tab, and arch-update's line.
        function list(): string {
            return root.list();
        }

        function isAvailable(): bool {
            return root.available;
        }

        // One line: how many, from where, how long ago, and by which tool.
        function status(): string {
            return root.status();
        }
    }
}
