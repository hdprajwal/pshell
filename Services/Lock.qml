pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.Widgets.Lock

// The lockscreen: the session lock, the PAM conversation, and the IPC that
// starts them.
//
// pshell does not decide *when* to lock, and that is deliberate. Omarchy
// splits the job -- hyprlock draws and authenticates, hypridle owns every
// timer and bridges logind's Lock signal to it -- and this takes only the
// first half. dpms, keyboard backlight and sleep inhibition are a daemon's
// job; pshell has no code for any of them and should not grow any. Point
// hypridle's lock_cmd at `qs ipc call pshell.lock lock` and suspend, lid
// close and idle all arrive here through machinery that already works.
//
// A singleton for the reason SettingsApp.qml already documents: bar widgets
// are instantiated once per monitor under Variants, so anything the whole
// session shares has to live outside them. WlSessionLock does its own
// per-monitor fan-out, so multi-monitor costs nothing here.
Singleton {
    id: root

    // The intent to be locked, and the authority on it.
    //
    // WlSessionLock.locked is bound to this rather than assigned, because
    // reading it back does not work: it notifies on the compositor's
    // answer, not on the request, so a binding to it sits stale at false
    // while a lock surface is demonstrably on screen -- which had
    // `pshell.lock isLocked` reporting an unlocked machine to anything that
    // asked. Driving the protocol from a property this file owns means the
    // answer is whatever was last asked for, which is the truth.
    property bool locked: false

    // What the compositor confirms, as opposed to what we asked for. False
    // for the moment between the two, and the honest thing to report.
    readonly property bool secure: sessionLock.secure

    property bool previewing: false

    // idle | checking | failed. A string rather than an enum because a
    // singleton cannot declare one and the alternative is three booleans
    // that can disagree with each other.
    property string authState: "idle"
    property string message: ""
    property int attempts: 0

    property bool capsLock: false
    property string keyboardLayout: ""

    // Held only between submit and PAM asking for it, and cleared the
    // instant it is handed over.
    property string _pending: ""

    function lock() {
        // Idempotent: hypridle can fire lock_cmd while a lock is already up
        // -- an idle timeout landing on top of a manual lock is the normal
        // case, not an edge one -- and restarting the surface under someone
        // mid-password would throw away what they had typed.
        if (root.locked)
            return;

        // A preview must never be what is covering a locked screen.
        root.previewing = false;
        root._reset();
        root.locked = true;
    }

    function preview() {
        // Refused rather than stacked. Opening a fake lock over a real one
        // is how you end up typing a real password into a stub.
        if (root.locked)
            return;

        root._reset();
        root.previewing = true;
    }

    function closePreview() {
        root.previewing = false;
        root._reset();
    }

    function submit(password) {
        if (root.authState === "checking" || password === "")
            return;

        root.authState = "checking";
        root.message = "";

        if (root.previewing) {
            // The stub. It fails, always, and after a delay in the same
            // order as the real thing -- PAM's rejection is slow on
            // purpose, and a preview that answered instantly would hide
            // the one state this field spends real time in.
            stub.restart();
            return;
        }

        root._pending = password;
        if (!pam.start()) {
            root._pending = "";
            root._fail("Authentication is unavailable");
        }
    }

    // Called on every keystroke. The failure colour and text stay until the
    // user starts typing over them, then go together.
    function clearMessage() {
        if (root.authState === "failed") {
            root.authState = "idle";
            root.message = "";
        }
    }

    function _reset() {
        root.authState = "idle";
        root.message = "";
        root.attempts = 0;
        root._pending = "";
    }

    function _succeed() {
        root._pending = "";
        root.authState = "idle";
        root.message = "";
        root.attempts = 0;
        root.locked = false;
    }

    function _fail(text) {
        root._pending = "";
        root.attempts += 1;
        root.authState = "failed";
        root.message = text;
    }

    PamContext {
        id: pam

        // /etc/pam.d/hyprlock and /etc/pam.d/swaylock are both nothing but
        // `auth include login`, so this runs the identical stack without
        // pshell needing a file installed as root -- which a shell you
        // clone into ~/.config cannot ask for.
        config: Config.lock.pamService

        // Left empty on purpose: PamContext defaults to the user running
        // the shell, which is the only user this lock is ever for.

        // What PAM says as it says it. The prompt itself ("Password: ") is
        // not shown -- the field already asks -- but an error is kept so a
        // failure can be reported in PAM's words rather than in guesses
        // about what went wrong.
        property string lastError: ""

        onPamMessage: {
            if (pam.responseRequired) {
                pam.respond(root._pending);
                root._pending = "";
            } else if (pam.messageIsError && pam.message !== "") {
                pam.lastError = pam.message;
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root._succeed();
                return;
            }

            const said = pam.lastError;
            pam.lastError = "";

            if (result === PamResult.MaxTries)
                root._fail(said !== "" ? said : "Too many attempts");
            else if (result === PamResult.Error)
                root._fail(said !== "" ? said : "Authentication error");
            else
                root._fail(said !== "" ? said : "Incorrect password");
        }

        // An unlock must never be the consequence of something going wrong.
        onError: error => {
            pam.lastError = "";
            root._fail("Authentication error: " + PamError.toString(error));
        }
    }

    Timer {
        id: stub

        interval: 900
        onTriggered: root._fail("Incorrect password (preview)")
    }

    WlSessionLock {
        id: sessionLock

        locked: root.locked

        LockSurface {}
    }

    // Behind a LazyLoader, like the settings window and for a sharper
    // reason than saving memory: LockPreview reads the Lock singleton, and
    // declaring it inline made it a child built *during* that singleton's
    // own construction, reading a half-built object. Deferring it until
    // `previewing` goes true means the singleton is finished by the time
    // anything inside asks it a question.
    LazyLoader {
        active: root.previewing

        LockPreview {}
    }

    // Caps Lock and the keyboard layout, from the compositor.
    //
    // Hyprland emits no event for Caps Lock, so a poll is the only way to
    // see it. It is bounded hard: the timer runs only while a lock or a
    // preview is actually on screen, and stops the moment either goes away.
    // A locked machine is not doing anything else with the CPU, and the
    // alternative is watching someone type a password into a shift-locked
    // field with no hint as to why it keeps failing.
    Timer {
        running: root.locked || root.previewing
        interval: 1000
        repeat: true
        triggeredOnStart: true

        // Skipped rather than queued if the last read has not come back, so
        // a slow hyprctl cannot pile up children.
        onTriggered: {
            if (!keyboards.running)
                keyboards.running = true;
        }
    }

    Process {
        id: keyboards

        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (e) {
                    // Hyprland not running, or answering something else.
                    // Both mean "no keyboard facts", not "Caps Lock is off".
                    return;
                }

                const list = parsed && parsed.keyboards ? parsed.keyboards : [];
                let caps = false;
                let layout = "";

                for (var i = 0; i < list.length; i++) {
                    // Any keyboard, because the one being typed on is not
                    // necessarily the one Hyprland calls main -- an
                    // external keyboard on a laptop is the common case.
                    if (list[i].capsLock)
                        caps = true;
                    if (layout === "" || list[i].main)
                        layout = String(list[i].layout || "");
                }

                root.capsLock = caps;
                root.keyboardLayout = layout;
            }
        }
    }

    IpcHandler {
        target: "pshell.lock"

        // What hypridle's lock_cmd should call, and what to put on a
        // keybind. Safe to call twice.
        function lock(): void {
            root.lock();
        }

        // Draws the lockscreen in an ordinary window with auth stubbed, so
        // it can be changed without locking yourself out to look at it.
        function preview(): void {
            root.preview();
        }

        function isLocked(): bool {
            return root.locked;
        }
    }
}
