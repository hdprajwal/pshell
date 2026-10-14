pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Nightlight.js" as Model

// The nightlight: a warmer screen, by way of Hyprland's hyprsunset.
//
// Modelled on Omarchy's nightlight service, which runs `hyprctl hyprsunset
// temperature N` and starts hyprsunset first if nothing answers. pshell does
// the same with one difference in who owns the result. Omarchy starts
// hyprsunset with setsid and leaves it running for good; here a hyprsunset
// pshell had to start is its own child, under `setpriv --pdeathsig TERM` as
// the clipboard watchers are, so the kernel takes it down with the shell and
// a crashed bar cannot leave the screen orange with nothing on it to say why.
//
// A hyprsunset somebody else started -- an exec-once in hyprland.lua, a
// systemd unit -- is used and never stopped. pshell only ever learns it is
// there by asking it to do something, so the shell touches it only when told
// to, and turning the nightlight off sends `identity` rather than a signal.
//
// A singleton for IdleInhibit's reason: the widget exists once per monitor,
// and one screen temperature with two owners would disagree with itself.
// Kept alive from shell.qml so the schedule runs, and `pshell nightlight`
// answers, on a bar with no nightlight widget at all.
//
// The temperature and the schedule are config (Config.nightlight). Whether it
// is on is session state, and off after every start -- the idle inhibitor's
// and DND's reasoning: a screen that comes up orange because of something you
// pressed last week, on a bar that may not even carry the widget, is a bad
// surprise. A schedule is the way to have it come back on its own. A reload
// of the shell's QML counts as a start: Quickshell stops the old
// generation's processes, hyprsunset with them, and nothing carries the
// state across for the new one to start it again.
Singleton {
    id: root

    // --------------------------------------------------------------- state

    // Whether hyprsunset is installed. Unknown until the probe below has
    // answered, which is why `probed` exists: "not yet asked" and "not
    // installed" are different answers to give a script.
    property bool available: false
    property bool probed: false

    // Whether pshell wants the screen warm. What hyprsunset is actually
    // doing is `reported`, read back after every change.
    property bool active: false
    readonly property int temperature: Config.nightlight.temperature

    // True while the hyprsunset doing the work is pshell's own child.
    readonly property bool owned: child.running

    // The temperature hyprsunset last reported, or null when nothing
    // answered.
    property var reported: null

    readonly property string scheduleStart: Config.nightlight.start
    readonly property string scheduleEnd: Config.nightlight.end
    readonly property bool scheduled: Model.hasSchedule(scheduleStart, scheduleEnd)

    readonly property string missingError: "error: hyprsunset is not installed, so there is no nightlight. Install it with: sudo pacman -S hyprsunset"

    // ------------------------------------------------------------ actions

    // Each returns "" on success or the line to hand back to a script, so
    // the IPC handler can answer with it and a click can ignore it.
    function setActive(value) {
        const want = !!value;
        if (!root.available) {
            // Asked again on every refusal, so installing hyprsunset while
            // the shell runs needs no restart -- just a second try.
            root._probe();
            // Off is already true of a machine that cannot warm the screen,
            // so a script making sure of it is not told it failed.
            if (!want)
                return "";
            return root.probed ? root.missingError : "error: still looking for hyprsunset, try again in a moment";
        }
        if (root.active === want)
            return "";
        root.active = want;
        root._apply();
        return "";
    }

    function toggle() {
        return root.setActive(!root.active);
    }

    // Written to config.json, like `pshell weather setLocation`: the
    // temperature is a setting, and one the settings file should agree with.
    // The change reaches hyprsunset through onTemperatureChanged below.
    function setTemperature(kelvin) {
        if (!Model.isValidTemperature(kelvin))
            return "error: the temperature is a whole number of kelvin from 1000 to 6000, not " + kelvin;
        Config.set("nightlight.temperature", Number(kelvin));
        return "";
    }

    function status() {
        return Model.statusLine({
            available: root.available,
            on: root.active,
            temperature: root.temperature,
            reported: root.reported,
            owned: root.owned,
            start: root.scheduleStart,
            end: root.scheduleEnd
        });
    }

    // What on, off and toggle answer with when they worked.
    function _reply() {
        return root.active ? "on " + Model.formatTemperature(root.temperature) : "off";
    }

    onTemperatureChanged: {
        if (root.active)
            root._apply();
    }

    // ---------------------------------------------------------- hyprsunset

    // Brings hyprsunset in line with `active` and `temperature`. Nothing
    // here is remembered between calls: every call works out what to send
    // from the state as it is now, so two clicks while a hyprctl is still
    // running fold into one more call when it exits, not two stale ones.
    property bool _dirty: false

    function _apply() {
        if (!root.available)
            return;
        if (applier.running) {
            root._dirty = true;
            return;
        }
        if (root.active) {
            // Asking first, even with no child of our own, is how a
            // hyprsunset somebody else started is found and used rather than
            // fought with: two of them would both be writing the colour
            // matrix. Nothing answering is what starts one.
            applier.mode = "set";
            applier.command = ["hyprctl", "hyprsunset", "temperature", String(root.temperature)];
        } else {
            // `identity` before anything is stopped, whoever's it is: the
            // screen goes back to normal because it was told to, not because
            // of whatever Hyprland does with a client that leaves.
            applier.mode = child.running ? "release" : "identity";
            applier.command = ["hyprctl", "hyprsunset", "identity"];
        }
        applier.running = true;
    }

    Process {
        id: applier

        property string mode: ""

        onExited: code => {
            if (applier.mode === "set" && code !== 0 && root.active && !child.running)
                root._startChild();
            else if (applier.mode === "release" && !root.active)
                root._stopChild();

            if (root._dirty) {
                root._dirty = false;
                root._apply();
                return;
            }
            if (root.active && code === 0)
                reader.running = true;
        }
    }

    function _startChild() {
        // The temperature goes on the command line rather than over IPC a
        // moment later: a hyprsunset still starting up applies its own
        // default when it is ready, over anything sent before then, and
        // `-t` makes that default the one we wanted.
        child.command = ["setpriv", "--pdeathsig", "TERM", "hyprsunset", "-t", String(root.temperature)];
        child.stopping = false;
        child.checked = false;
        child.running = true;
    }

    function _stopChild() {
        child.stopping = true;
        child.running = false;
    }

    Process {
        id: child

        // Set when pshell asked it to go, so its exit is not mistaken for
        // a crash.
        property bool stopping: false
        // Whether this hyprsunset has been read back once since it started.
        property bool checked: false
        property real startedAt: 0

        onStarted: {
            child.startedAt = Date.now();
            settle.restart();
        }

        // Not respawned. hyprsunset going away on its own -- killed by hand,
        // refused by Hyprland, never started for want of setpriv -- is not
        // something another try a second later would fix, so the nightlight
        // says it is off, which is now true, and the shell says why once.
        onExited: code => {
            settle.stop();
            if (child.stopping) {
                child.stopping = false;
                return;
            }
            if (!root.active)
                return;
            if (Date.now() - child.startedAt < 2000)
                console.warn("pshell: hyprsunset exited with", code, "as soon as it started, so the nightlight is off. It needs Hyprland, and setpriv from util-linux.");
            else
                console.warn("pshell: hyprsunset exited with", code, "so the nightlight is off.");
            root.reported = null;
            root.active = false;
        }
    }

    // A hyprsunset that has just started cannot be asked anything until its
    // socket is up, so the first read-back waits a moment.
    Timer {
        id: settle

        interval: 1000
        onTriggered: reader.running = true
    }

    // Reads the temperature back. Mostly for `pshell nightlight status`,
    // which should say what the screen is doing rather than what pshell
    // asked for -- but once per child it also catches a temperature changed
    // while that child was still starting up, which hyprsunset would have
    // ignored, and sends it again.
    Process {
        id: reader

        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            id: readerOut
        }
        onExited: code => {
            root.reported = code === 0 ? Model.parseTemperature(readerOut.text) : null;
            if (child.running && !child.checked) {
                child.checked = true;
                if (root.active && root.reported !== null && root.reported !== root.temperature)
                    root._apply();
            }
        }
    }

    // ------------------------------------------------------------- probe

    // `command -v` through sh, because that is the PATH lookup the shell's
    // own children will get. Run once at start and again whenever a request
    // was refused for want of it.
    function _probe() {
        if (!prober.running)
            prober.running = true;
    }

    Process {
        id: prober

        running: true
        command: ["sh", "-c", "command -v hyprsunset >/dev/null 2>&1"]
        onExited: code => {
            root.available = code === 0;
            root.probed = true;
            root._followSchedule(true);
        }
    }

    // ----------------------------------------------------------- schedule

    // The schedule switches the nightlight at its two edges and leaves it
    // alone in between, so turning it off at 21:00 because you are watching
    // a film keeps it off until the next edge rather than for thirty
    // seconds. `_lastScheduled` is what the schedule said last time it was
    // asked; only a change in that answer moves anything.
    //
    // A thirty-second poll of a pure function rather than a timer aimed at
    // the next edge: a laptop that slept through 20:00 catches up within
    // half a minute of waking, and there is no interval arithmetic across
    // midnight or a clock change to get wrong.
    property bool _lastScheduled: false

    function _followSchedule(force) {
        if (!root.scheduled || !root.available)
            return;
        const want = Model.scheduledOn(Model.minutesOfDay(new Date()), root.scheduleStart, root.scheduleEnd);
        if (!force && want === root._lastScheduled)
            return;
        root._lastScheduled = want;
        root.setActive(want);
    }

    // A new schedule takes over at once, rather than at its next edge.
    readonly property string _scheduleKey: scheduleStart + "-" + scheduleEnd
    on_ScheduleKeyChanged: root._followSchedule(true)

    Timer {
        interval: 30000
        repeat: true
        running: root.scheduled && root.available
        onTriggered: root._followSchedule(false)
    }

    // ---------------------------------------------------------------- ipc

    IpcHandler {
        target: "pshell.nightlight"

        // `on` and `off` besides `toggle`, for IdleInhibit's reason. Each
        // answers with the state it left behind, or with a line starting
        // `error:` that `pshell` turns into a failing exit.
        function on(): string {
            const err = root.setActive(true);
            return err !== "" ? err : root._reply();
        }

        function off(): string {
            const err = root.setActive(false);
            return err !== "" ? err : "off";
        }

        function toggle(): string {
            const err = root.toggle();
            return err !== "" ? err : root._reply();
        }

        function isOn(): bool {
            return root.active;
        }

        function isAvailable(): bool {
            return root.available;
        }

        function temperature(): int {
            return root.temperature;
        }

        function setTemperature(kelvin: int): string {
            const err = root.setTemperature(kelvin);
            return err !== "" ? err : Model.formatTemperature(kelvin);
        }

        // One line: on or off, at what, by whose hyprsunset, and the
        // schedule if there is one.
        function status(): string {
            return root.status();
        }
    }
}
