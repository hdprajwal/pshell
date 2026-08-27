pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "NotificationHistory.js" as History

// pshell's notification daemon: the org.freedesktop.Notifications server,
// the live list the toasts draw, the history the panel draws, and DND.
//
// A singleton for a harder reason than the idle inhibitor's: bar widgets are
// instantiated once per monitor, and there must be exactly one
// NotificationServer in the whole shell or a three-monitor machine tries to
// own the DBus name three times. Per-monitor widgets and toast stacks are
// views over this; nothing else in the shell talks to the server.
//
// pshell keeps the persistence model, not the popup model: a notification
// stays tracked after its toast times out, and only a user dismissing it --
// toast click, panel clear, dismissAll -- actually closes it. That is what
// `persistenceSupported: true` promises applications, and it is what keeps a
// history row's action buttons alive to invoke. The exception is a transient
// notification, which asks not to be kept: it toasts, skips history, and is
// expired the moment its toast is done.
Singleton {
    id: root

    // ------------------------------------------------------------- server

    readonly property var server: notifServer

    // The tracked model itself, for views that want incremental updates (a
    // ListView over `values` rebuilds every delegate on any change; over the
    // model it only touches the row that changed).
    readonly property var trackedModel: notifServer.trackedNotifications
    readonly property var live: notifServer.trackedNotifications.values

    NotificationServer {
        id: notifServer

        // A config reload must not drop live notifications on the floor.
        keepOnReload: true

        // Advertised because they are true of what the widgets render:
        // bodies draw as StyledText, so markup and clickable links work;
        // `image` renders in the toast; actions render as buttons; inline
        // replies render as a text field. persistenceSupported is the load-
        // bearing one -- it tells applications their notification survives
        // its popup, which the history panel is built on.
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        inlineReplySupported: true

        // Not advertised because nothing renders them: <img> tags inside a
        // body are not drawn (bodyImagesSupported), and action buttons show
        // their text, never an icon (actionIconsSupported). Advertising a
        // capability you do not implement is a lie applications act on --
        // an app told icons work sends icon names as labels and its buttons
        // come out unreadable.
        bodyImagesSupported: false
        actionIconsSupported: false

        onNotification: n => root._onNotification(n)
    }

    // ------------------------------------------------------------ history

    // Plain serialisable records, newest first, capped at
    // Config.notifications.historyDepth. Never the live Notification
    // objects: records outlive the notification they describe and are
    // written to notifications.json as-is. The notification's `image` is
    // deliberately not recorded -- it is an image:// provider URL that dies
    // with the notification, so a persisted copy would render as nothing
    // after a restart. appIcon is a theme name or file path and survives.
    property var history: []

    // When this shell came up. History rows use it to know whether their
    // record can still have a live notification behind it: server ids
    // restart from scratch with the shell, so an id match against a record
    // from a previous session would resurrect the wrong notification.
    readonly property real sessionStart: Date.now()

    // ---------------------------------------------------------------- dnd

    // Off after every restart, deliberately -- the idle inhibitor's
    // reasoning: a machine silently swallowing notifications because of
    // something switched on last week is a bad surprise. History still
    // records everything while this is on; only the toast is suppressed,
    // because losing notifications entirely is not what "do not disturb"
    // means.
    property bool dnd: false

    function setDnd(state) {
        const s = String(state);
        if (s === "on")
            root.dnd = true;
        else if (s === "off")
            root.dnd = false;
        else if (s === "toggle")
            root.dnd = !root.dnd;
        else
            console.warn("pshell: dnd takes on, off or toggle, not", s);
    }

    // ------------------------------------------------------------- unread

    // How many notifications arrived since the panel was last opened. The
    // bar widget wears it. readonly over a private counter so a widget can
    // only ever read it -- opening the panel is the one thing that zeroes
    // it, and that goes through openPanel().
    property int _unread: 0
    readonly property int unreadCount: _unread

    // ------------------------------------------------------------- popups

    // Which notifications currently have a toast up, newest first, as
    // entries of { id, deadline, remaining, held }. deadline is an epoch
    // millisecond, 0 for "never expires". Owned here rather than by the
    // toast stacks because a stack exists once per monitor: per-screen
    // timers raced each other -- a toast paused under the pointer on one
    // screen was still counted down by its twin on the other.
    property var _popups: []
    readonly property var popupIds: _popups.map(p => p.id)

    function _onNotification(n) {
        // Claimed first, before anything else: a notification is only kept
        // past this signal handler if `tracked` is set true during it --
        // DMS's handler opens the same way. Without this line the server
        // acknowledges every notification and then drops it on the floor,
        // which looks exactly like the timeout logic being broken.
        n.tracked = true;

        const record = {
            id: n.id,
            appName: String(n.appName || ""),
            desktopEntry: String(n.desktopEntry || ""),
            appIcon: String(n.appIcon || ""),
            summary: String(n.summary || ""),
            body: String(n.body || ""),
            urgency: n.urgency,
            time: Date.now(),
            // 0 is "still open"; the closed handler below records the real
            // reason, which is how history tells "dismissed" from "expired".
            closeReason: 0
        };

        const muted = History.isMuted(record, Config.notifications.muted);

        // Transient means "do not persist in a centre" -- it affects
        // history, not the popup. Everything else is recorded even under
        // DND and even when muted; both of those only silence the toast.
        if (!n.transient) {
            root.history = History.append(root.history, record, Config.notifications.historyDepth);
            root._unread += 1;
            saveTimer.restart();
        }

        // The record's close reason is written when the notification goes,
        // matched by identity: append never copies the record objects, so
        // the reference stays good however often the array is reassigned.
        n.closed.connect(reason => {
            record.closeReason = reason;
            if (root.history.indexOf(record) >= 0)
                saveTimer.restart();
            root._releasePopup(n.id);
        });

        if (root.dnd || muted) {
            // No toast. A transient notification that will never be seen
            // has nothing left to wait for, so it is expired now rather
            // than sitting tracked forever.
            if (n.transient)
                n.expire();
            return;
        }

        const ms = root._timeoutMsFor(n);
        root._popups = [{
                id: n.id,
                deadline: ms > 0 ? Date.now() + ms : 0,
                remaining: 0,
                held: false
            }].concat(root._popups);

        // The persistence model keeps notifications tracked until the user
        // dismisses them, and a chatty app would grow that list without
        // bound. The history cap is the honest limit: anything older than
        // the history could remember is expired, oldest first. maxVisible
        // is the floor so a zero historyDepth cannot expire the toast that
        // just went up.
        const keep = Math.max(Config.notifications.historyDepth, Config.notifications.maxVisible);
        const tracked = notifServer.trackedNotifications.values;
        if (tracked.length > keep)
            tracked[0].expire();
    }

    // The notification's own expireTimeout wins when it sets one. It is in
    // milliseconds; the spec says -1 means "the server decides" -- that is
    // the config fallback -- and 0 means never auto-expire. DMS reads the
    // same field the same way.
    function _timeoutMsFor(n) {
        const own = n.expireTimeout;
        if (own === 0)
            return 0;
        if (own > 0)
            return Math.round(own);
        let secs = Config.notifications.timeoutNormal;
        if (n.urgency === NotificationUrgency.Low)
            secs = Config.notifications.timeoutLow;
        else if (n.urgency === NotificationUrgency.Critical)
            secs = Config.notifications.timeoutCritical;
        return Math.round(secs * 1000);
    }

    // Reading a notification should not race a countdown: the toast under
    // the pointer holds its remaining time and gets it back on leave. Held
    // state lives here with the deadlines, so a hover on any monitor's copy
    // of the toast holds all of them.
    function holdPopup(id) {
        const now = Date.now();
        for (const p of root._popups) {
            if (p.id === id && !p.held) {
                p.held = true;
                p.remaining = p.deadline > 0 ? Math.max(0, p.deadline - now) : 0;
            }
        }
        root._popups = root._popups.slice();
    }

    function resumePopup(id) {
        for (const p of root._popups) {
            if (p.id === id && p.held) {
                p.held = false;
                if (p.deadline > 0)
                    p.deadline = Date.now() + Math.max(1000, p.remaining);
            }
        }
        root._popups = root._popups.slice();
    }

    function _releasePopup(id) {
        if (root.popupIds.indexOf(id) < 0)
            return;
        root._popups = root._popups.filter(p => p.id !== id);
    }

    // A quarter second of slack on a five second toast is invisible; a
    // deadline-exact timer per popup per screen was the alternative and is
    // where the racing came from. Runs only while something can expire.
    Timer {
        id: sweep
        interval: 250
        repeat: true
        running: root._popups.some(p => p.deadline > 0 && !p.held)
        onTriggered: {
            const now = Date.now();
            const due = root._popups.filter(p => p.deadline > 0 && !p.held && p.deadline <= now);
            for (const p of due) {
                const n = root.liveById(p.id);
                // Transient asked not to be kept; everything else stays
                // tracked for the history panel -- the toast going away is
                // a view change, not a close.
                if (n && n.transient)
                    n.expire();
                else
                    root._releasePopup(p.id);
            }
        }
    }

    function liveById(id) {
        const tracked = notifServer.trackedNotifications.values;
        for (var i = 0; i < tracked.length; i++) {
            if (tracked[i].id === id)
                return tracked[i];
        }
        return null;
    }

    function defaultActionOf(n) {
        if (!n)
            return null;
        for (var i = 0; i < n.actions.length; i++) {
            // "default" is the spec's name for the action a plain click on
            // the notification invokes.
            if (n.actions[i].identifier === "default")
                return n.actions[i];
        }
        return null;
    }

    // The spec closes a notification once an action is invoked unless the
    // sender marked it resident, so every invoke in the shell goes through
    // here rather than each view remembering the rule.
    function invokeAction(n, action) {
        if (!n || !action)
            return;
        action.invoke();
        if (!n.resident)
            n.dismiss();
    }

    function dismissAll() {
        // Over a copy: each dismiss edits the tracked model under the loop.
        const tracked = notifServer.trackedNotifications.values.slice();
        for (const n of tracked)
            n.dismiss();
    }

    // The panel's "clear all": dismiss everything live and forget the
    // history too. Distinct from dismissAll, which leaves history alone --
    // the IPC caller asked for silence, not amnesia.
    function clearHistory() {
        dismissAll();
        root.history = [];
        saveTimer.restart();
    }

    // Per-group clear: one app's records out of history, and its live
    // notifications dismissed with them.
    function clearApp(key) {
        const tracked = notifServer.trackedNotifications.values.slice();
        for (const n of tracked) {
            if (History.appKey({
                    desktopEntry: n.desktopEntry,
                    appName: n.appName
                }) === key)
                n.dismiss();
        }
        root.history = root.history.filter(r => History.appKey(r) !== key);
        saveTimer.restart();
    }

    // -------------------------------------------------------------- panel

    // The history panel is drawn by the bar widget, which exists once per
    // monitor -- so the wanted-open state lives here and the widgets follow
    // it, with panelScreen naming the one that hosts. Without this, IPC and
    // the widget would each own half the state, and `pshell notifications
    // toggle` on a two-monitor bar opened two panels that fought over the
    // popout coordinator.
    property bool panelOpen: false
    property string panelScreen: ""

    function openPanel(screenName) {
        root.panelScreen = screenName !== undefined && String(screenName) !== "" ? String(screenName) : _focusedScreenName();
        root.panelOpen = true;
        root._unread = 0;
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

    // Same resolution WallpaperCarousel uses, for the same reason: IPC has
    // no widget to ask, and the focused monitor is where the eyes are. No
    // Hyprland means no focus answer, and the first screen is the honest
    // fallback.
    function _focusedScreenName() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            return mon.name;
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    // -------------------------------------------------------- persistence

    // ~/.local/state, not ~/.config: history is runtime state the shell
    // owns, exactly what Prefs.qml keeps out of config.json. Spelled from
    // the environment rather than StandardPaths because Qt's StateLocation
    // is newer than the rest of the enum and a wrong guess here writes
    // nothing, silently.
    readonly property string _statePath: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        const base = xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state";
        return base + "/pshell/notifications.json";
    }

    property bool _loaded: false

    // FileView does not create parent directories, and ~/.local/state/pshell
    // is nothing else's job to make. Done once at startup, long before the
    // first notification could want to save.
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", _statePath.substring(0, _statePath.lastIndexOf("/"))])

    // Notifications arrive in bursts -- a chat channel waking up is a dozen
    // in a second -- and each one reassigns history. Half a second of
    // settling turns the burst into one write.
    Timer {
        id: saveTimer
        interval: 500
        repeat: false
        onTriggered: {
            // The guard Prefs.qml carries, for the same reason: a write
            // before the load finished would truncate the history it was
            // about to read.
            if (!root._loaded)
                return;
            historyFile.setText(JSON.stringify(root.history, null, 2));
        }
    }

    FileView {
        id: historyFile

        path: root._statePath
        // Unlike config.json, nothing else ever writes this file, so there
        // is no editor to pick up changes from and no watcher needed.
        watchChanges: false
        blockWrites: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (Array.isArray(parsed))
                    root.history = parsed.slice(0, Config.notifications.historyDepth);
            } catch (e) {
                console.warn("pshell: bad notifications.json —", e);
            }
            root._loaded = true;
        }
        // No history yet is the normal first run, not an error.
        onLoadFailed: root._loaded = true
    }

    // ---------------------------------------------------------------- ipc

    IpcHandler {
        target: "pshell.notifications"

        function toggle(): void {
            root.togglePanel();
        }

        function open(): void {
            root.openPanel();
        }

        function close(): void {
            root.closePanel();
        }

        function dismissAll(): void {
            root.dismissAll();
        }

        function dnd(state: string): void {
            root.setDnd(state);
        }

        function count(): int {
            return root.unreadCount;
        }

        function dismiss(id: int): void {
            const n = root.liveById(id);
            if (n)
                n.dismiss();
        }

        function invoke(id: int, action: string): void {
            const n = root.liveById(id);
            if (!n)
                return;
            for (var i = 0; i < n.actions.length; i++) {
                if (n.actions[i].identifier === action) {
                    root.invokeAction(n, n.actions[i]);
                    return;
                }
            }
            console.warn("pshell: notification", id, "has no action", action);
        }

        function history(limit: int): string {
            const take = limit > 0 ? limit : root.history.length;
            return root.history.slice(0, take).map(r => History.summarise(r)).join("\n");
        }
    }
}
