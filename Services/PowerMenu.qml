pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Ending the session: lock, log out, suspend, reboot, power off.
//
// A singleton for the reason IdleInhibit gives: the commands used to live
// inline in the control centre's header Repeater, one `{icon, cmd, tip}`
// object each, so they existed once per monitor and nowhere a keybind could
// reach them. Two surfaces draw them now -- the control centre and the power
// menu -- and a second copy of "what does log out run" is how the two come to
// disagree about it.
//
// The panel's wanted-open state lives here too, the way Notifications and
// Weather hold theirs: the widget is built once per monitor, the panel must
// not be, and IPC has no widget to ask which monitor it meant.
Singleton {
    id: root

    // Defaults, and why these five commands.
    //
    // lock and logout are logind's, because they act on *this session* and
    // logind is the thing that owns sessions -- `loginctl lock-session` is
    // also what every lock helper listens for. suspend, reboot and poweroff
    // act on the *machine*, so they are systemctl's, matching the
    // `systemctl poweroff` the control centre already used. Keeping the two
    // families split that way means each command is asked of the daemon that
    // actually knows the answer, and none of them needs root: logind takes
    // all three machine actions from a local active session over polkit.
    readonly property var defaults: ({
            lock: "loginctl lock-session",
            logout: "loginctl terminate-user $USER",
            suspend: "systemctl suspend",
            reboot: "systemctl reboot",
            poweroff: "systemctl poweroff"
        })

    // The list both surfaces draw, in the order they draw it: least
    // destructive first, so the pointer never crosses "power off" on its way
    // to "lock".
    //
    // `confirms` is the policy, held here rather than at either call site.
    // logout, reboot and poweroff take unsaved work with them and are
    // irreversible from the keyboard, so they ask. lock and suspend lose
    // nothing -- everything is still open behind them and the password you
    // already know brings it back -- so asking would be a keystroke charged
    // for nothing, four times a day.
    readonly property var actions: [
        {
            id: "lock",
            label: "Lock",
            icon: Glyphs.lock,
            confirms: false,
            question: ""
        },
        {
            id: "suspend",
            label: "Suspend",
            icon: Glyphs.suspend,
            confirms: false,
            question: ""
        },
        {
            id: "logout",
            label: "Log out",
            icon: Glyphs.logout,
            confirms: true,
            question: "Log out? Anything unsaved goes with the session."
        },
        {
            id: "reboot",
            label: "Restart",
            icon: Glyphs.reboot,
            confirms: true,
            question: "Restart now? Anything unsaved is lost."
        },
        {
            id: "poweroff",
            label: "Power off",
            icon: Glyphs.powerOff,
            confirms: true,
            question: "Power off now? Anything unsaved is lost."
        }
    ]

    function actionFor(id) {
        const want = String(id || "");
        for (var i = 0; i < root.actions.length; i++) {
            if (root.actions[i].id === want)
                return root.actions[i];
        }
        return null;
    }

    // What an action actually runs. `override` is the control centre's three
    // legacy widget keys -- `lock`, `power`, `logout` on the controlCenter
    // entry -- which the README has documented since Phase 2. They still win
    // where they are set: silently ignoring a command somebody put in their
    // config is worse than one extra argument here, and a config.json in the
    // wild cannot be edited from this end.
    function commandFor(id, override) {
        const custom = String(override || "");
        if (custom !== "")
            return custom;
        const configured = Config.power.command(id);
        return configured !== "" ? configured : String(root.defaults[String(id || "")] || "");
    }

    // Runs the command and nothing else -- no dialog, whatever `confirms`
    // says. Every caller that should confirm confirms *before* calling this:
    // the panel through Ui/ConfirmDialog, the control centre through its own.
    // IPC lands here directly on purpose, and that asymmetry is the point:
    // `pshell power reboot` from a script or a keybind has already decided,
    // and a dialog nobody is looking at would leave the machine up.
    //
    // execDetached rather than a Process: `systemctl poweroff` tears this
    // shell down while it runs, and a child of a process being killed is not
    // where you want the command that does the killing.
    function invoke(id, override) {
        const command = root.commandFor(id, override);
        if (command === "") {
            console.warn("pshell: no power action called", JSON.stringify(String(id)));
            return;
        }
        // sh -c, because the defaults contain `$USER` and a user's override
        // may contain anything else a shell understands.
        Quickshell.execDetached(["sh", "-c", command]);
    }

    // ---------------------------------------------------------------- panel

    property bool panelOpen: false
    property string panelScreen: ""

    // Whether a power widget is in the bar at all. Same test Weather uses:
    // an entry whose `id` or `type` is "power" in one of the three sections.
    readonly property bool wanted: Config.hasWidget("power")

    function openPanel(screenName) {
        if (!root.wanted) {
            // The widget draws this panel, so without one there is nothing to
            // open -- and the five actions are all still reachable by name,
            // which is what the warning points at.
            console.warn("pshell: no power widget in the bar, so there is no menu to open. The actions still answer: pshell power lock|logout|suspend|reboot|poweroff");
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

    // Same resolution Notifications and Weather use, for the same reason: IPC
    // has no widget to ask, and the focused monitor is where the eyes are.
    function _focusedScreenName() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            return mon.name;
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    // ------------------------------------------------------------------ IPC

    IpcHandler {
        target: "pshell.power"

        function toggle(): void {
            root.togglePanel();
        }

        function open(): void {
            root.openPanel();
        }

        function close(): void {
            root.closePanel();
        }

        // The five actions by name, so a keybind or a script never has to go
        // through the menu. None of these shows a dialog -- see invoke().
        function lock(): void {
            root.invoke("lock");
        }

        function logout(): void {
            root.invoke("logout");
        }

        function suspend(): void {
            root.invoke("suspend");
        }

        function reboot(): void {
            root.invoke("reboot");
        }

        function poweroff(): void {
            root.invoke("poweroff");
        }
    }
}
