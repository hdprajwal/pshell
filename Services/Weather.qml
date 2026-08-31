pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Weather.js" as W

// The weather, from Open-Meteo. No API key, no account, no daemon.
//
// A singleton because the bar is built once per monitor and three screens must
// not mean three sets of HTTP requests at a third party's expense. It also
// owns the panel's wanted-open state for the same reason Notifications does:
// the widget exists per monitor, the panel must not, and IPC has no widget to
// ask which one it meant.
//
// XMLHttpRequest rather than Process and curl. Two JSON GETs is the one thing
// QML already does without help, and reaching for curl would add a runtime
// dependency to a shell that currently needs none for this.
//
// There is a keep-alive line in shell.qml, and the reason it is not a
// contradiction is the split below.
//
// Two things were coupled and did not have to be. A singleton *existing* is
// what registers its IPC target, so without a keep-alive `pshell weather
// current` on a bar carrying no weather widget answers "Target not found" --
// and a keybind or a status script should not have to know which widgets are
// in the bar today. A singleton *polling* is what costs Open-Meteo a request,
// four times an hour, forever, and doing that on a bar with nothing to draw
// the answer would be making a network request on the user's behalf for
// nobody.
//
// Wallpaper and Lock need only the first half, because neither has a widget at
// all. This one has a widget, so it separates them: shell.qml keeps the
// singleton alive, and `wanted` below gates the refresh timer and the startup
// fetch on the widget actually being in a bar section. refresh() itself stays
// ungated. A bar without the widget therefore answers every command, fetches
// when asked, and asks for nothing on its own.
Singleton {
    id: root

    // ------------------------------------------------------------- config

    readonly property string units: Config.weather.units
    readonly property int intervalMin: Config.weather.intervalMin
    readonly property bool fixedCoordinates: Config.weather.hasCoordinates
    readonly property string configuredLocation: Config.weather.location
    readonly property bool configured: fixedCoordinates || configuredLocation !== ""

    // Everything that decides what to ask for, as one string. A change to any
    // of it means the reading on screen is answering a question nobody is
    // asking any more, so it refetches -- and only then, so editing an
    // unrelated line of config.json does not cost a request.
    readonly property string requestKey: fixedCoordinates ? Config.weather.latitude + "," + Config.weather.longitude + "," + units : configuredLocation.trim().toLowerCase() + "," + units

    // ------------------------------------------------------------- state

    // This session's fetches. Authoritative over the persisted cache, and
    // separate from it because weather.json loads asynchronously: a fetch that
    // lands before the file does must not be overwritten by what was on disk.
    property var fetched: null

    // The last good reading off disk, until this session takes one of its own.
    property var cached: null
    readonly property var reading: fetched !== null ? fetched : cached

    property bool busy: false
    property string lastError: ""

    // A minute hand, for `stale` and for the panel's age line. Minutes is the
    // right precision: the reading itself only moves in fifteen-minute steps,
    // and a second-precision clock would repaint the panel sixty times for
    // every time it changed.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property real now: clock.date ? clock.date.getTime() : Date.now()

    readonly property var summary: W.summarise(reading)
    readonly property var strip: W.dailyStrip(reading)
    readonly property bool stale: reading !== null && W.isStale(reading.fetchedAt, now, intervalMin)
    readonly property string age: reading !== null ? W.ageText(reading.fetchedAt, now) : "never"
    readonly property string place: reading !== null ? String(reading.place || "") : ""

    // --------------------------------------------------------- geocoding
    //
    // Resolved once and kept, keyed by the name that resolved, so changing the
    // name in config.json re-resolves and leaving it alone never does.
    // Re-geocoding a fixed place every fifteen minutes is two requests where
    // one will do, forever, for an answer that has not moved since the city
    // was founded.
    //
    // One entry, not a table. A history of every place ever typed would grow
    // without bound for the sake of making one setting change cheap the second
    // time, and that setting changes about once.

    readonly property string cachedGeocodeKey: String(Prefs.weather.geocodeKey || "")
    readonly property var cachedGeocode: Prefs.weather.geocode || null

    function _key(name) {
        return String(name || "").trim().toLowerCase();
    }

    function resolvedFor(name) {
        const key = _key(name);
        if (key === "" || key !== root.cachedGeocodeKey)
            return null;
        const hit = root.cachedGeocode;
        return hit && isFinite(Number(hit.latitude)) && isFinite(Number(hit.longitude)) ? hit : null;
    }

    // ------------------------------------------------------------ fetching

    // Set when a refresh is asked for while one is already in flight, and
    // honoured when that one finishes. Without it, `setLocation` during the
    // fifteen-minute request that happened to be running would change the
    // config, skip the refetch and leave the old city on screen until the next
    // tick -- which reads as the command having done nothing.
    property bool _pending: false

    function refresh() {
        if (root.busy) {
            root._pending = true;
            return;
        }

        if (!root.configured) {
            root.lastError = "No location set. Put a `location` or a `latitude`/`longitude` in config.json's weather block.";
            return;
        }

        if (root.fixedCoordinates) {
            // The name is kept as the label when both are set: coordinates win
            // the question of where, and a name is still the better answer to
            // "where is this".
            root._fetchForecast(Config.weather.latitude, Config.weather.longitude, root.configuredLocation !== "" ? root.configuredLocation : Config.weather.latitude.toFixed(2) + ", " + Config.weather.longitude.toFixed(2));
            return;
        }

        const hit = root.resolvedFor(root.configuredLocation);
        if (hit) {
            root._fetchForecast(Number(hit.latitude), Number(hit.longitude), String(hit.label || hit.name || root.configuredLocation));
            return;
        }
        root._geocode(root.configuredLocation);
    }

    function _geocode(name) {
        const url = W.geocodeUrl(name);
        if (url === "")
            return;
        root._get(url, function (payload) {
            const hit = W.parseGeocode(payload);
            if (!hit) {
                // Naming the string that missed, because "not found" without
                // it sends the reader to look at their network first.
                root.lastError = "No such place: “" + String(name) + "”";
                console.warn("pshell: weather could not geocode", JSON.stringify(String(name)));
                return;
            }
            const next = Object.assign({}, Prefs.weather);
            next.geocodeKey = root._key(name);
            next.geocode = hit;
            Prefs.setWeather(next);
            root._fetchForecast(hit.latitude, hit.longitude, hit.label);
        }, "geocode");
    }

    function _fetchForecast(latitude, longitude, label) {
        const url = W.forecastUrl(latitude, longitude, root.units);
        if (url === "")
            return;
        root._get(url, function (payload) {
            const next = W.parseForecast(payload, Date.now(), root.units);
            if (!next) {
                root.lastError = "Open-Meteo sent something that is not a forecast";
                console.warn("pshell: weather got an unparseable forecast");
                return;
            }
            // The place is ours, not the payload's: the forecast endpoint
            // answers with coordinates and a timezone and never with a name.
            next.place = String(label || "");
            root.fetched = next;
            root.lastError = "";
            saveTimer.restart();
        }, "forecast");
    }

    // One request at a time, and a failed one keeps the cache rather than
    // clearing it. A dropped network must show stale data with its age
    // visible; a blank widget is the shell saying it has forgotten what it
    // knew ten minutes ago, which is not true.
    function _get(url, onPayload, what) {
        root.busy = true;
        watchdog.restart();

        const request = new XMLHttpRequest();
        root._inFlight = request;

        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            // A reply from a request the watchdog already gave up on. It is
            // let go rather than applied: the shell has moved on, `busy` is
            // already clear, and clearing it a second time would step on the
            // request that took its place.
            if (root._inFlight !== request)
                return;
            watchdog.stop();
            root._settle();

            // status 0 is a request that never reached anyone: no route, DNS
            // down, or the watchdog below aborting it.
            if (request.status === 0) {
                root.lastError = "Could not reach Open-Meteo";
                console.warn("pshell: weather", what, "request did not complete");
                return;
            }
            if (request.status !== 200) {
                root.lastError = "Open-Meteo answered " + request.status;
                console.warn("pshell: weather", what, "request failed with", request.status);
                return;
            }
            try {
                onPayload(JSON.parse(request.responseText));
            } catch (e) {
                root.lastError = "Open-Meteo sent unreadable JSON";
                console.warn("pshell: weather could not read the", what, "reply —", e);
            }
        };

        request.open("GET", url);
        request.send();
    }

    property var _inFlight: null

    // The one place `busy` is cleared, so the watchdog and a real reply agree
    // about what "finished" means.
    function _settle() {
        root.busy = false;
        root._inFlight = null;
        if (root._pending) {
            root._pending = false;
            // Deferred, not called here: a geocode reply starts the forecast
            // request from inside its own handler, and re-entering refresh()
            // before that happens would find `busy` false and race it.
            Qt.callLater(root.refresh);
        }
    }

    // QML's XMLHttpRequest has no `timeout`, so a connection that opens and
    // then hangs -- a captive portal is the usual one -- would leave `busy`
    // set and every later refresh a no-op for the rest of the session. Thirty
    // seconds is far past a healthy round trip and far short of the fifteen
    // minutes until the next attempt.
    //
    // The timer clears the state itself rather than leaving it to abort()'s
    // callback. Whether Qt's XMLHttpRequest dispatches a readystatechange on
    // abort is not something this shell should be betting the widget on, and
    // the guard above means a late reply after the timer fired is discarded
    // rather than arriving to find its own bookkeeping already undone.
    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            const abandoned = root._inFlight;
            root._settle();
            root.lastError = "Open-Meteo did not answer in time";
            console.warn("pshell: weather request timed out");
            if (abandoned)
                abandoned.abort();
        }
    }

    // Polling follows the widget, not the singleton.
    //
    // The singleton itself is kept alive by shell.qml so `pshell weather` has
    // a target on any bar, which is the same thing that block does for the
    // lock and the wallpaper. But existing and polling are two different
    // things, and only one of them costs a third party a request: a bar with
    // no weather widget on it would otherwise talk to Open-Meteo four times an
    // hour for nothing to draw the answer. So the timer and the startup fetch
    // are gated on the widget being configured, and refresh() itself is not --
    // `pshell weather refresh` works on any bar, it just does not repeat.
    //
    // What it actually means: an entry whose `id` or `type` is "weather" sits
    // in one of the three bar sections. That is ConfigPath.findWidget's test,
    // so an on-disk QML widget whose manifest id is "weather" counts as well
    // as the built-in type -- the sections are the same list either way. What
    // it would miss is a third-party widget under some other id driving this
    // singleton, which nothing does today.
    //
    // Written down because the failure mode is silent. A widget this does not
    // recognise gets no poll, no log line, and a bar face stuck on "Waiting
    // for the first reading" for as long as the shell runs.
    //
    // Binding-safe: Config blocks on loading, so this is right the first time
    // it is evaluated rather than false for a frame.
    readonly property bool wanted: Config.hasWidget("weather")

    // config.json is watched, so a widget can be added to a running shell.
    // Nothing else notices: all three refresh sites below are startup-shaped,
    // and a Timer that flips to running starts a fresh full interval rather
    // than firing. Without this the widget appears and sits on "Waiting for
    // the first reading" for up to intervalMin minutes.
    //
    // Not left to onRequestKeyChanged. It would cover the case where the
    // location changed too, but setting the location and adding the widget in
    // one edit is one Config.data write, and the order the two bindings
    // re-evaluate in is not something to depend on.
    onWantedChanged: if (root.wanted && Prefs.loaded)
        root.refresh()

    Timer {
        interval: root.intervalMin * 60000
        running: root.wanted
        repeat: true
        onTriggered: root.refresh()
    }

    // The first fetch waits for state.json, so a shell that already knows
    // where "Bengaluru" is does not ask again on every start. Both halves are
    // needed: the file may already be read by the time this singleton is
    // built, in which case the change signal never comes.
    readonly property bool prefsReady: Prefs.loaded
    onPrefsReadyChanged: if (prefsReady)
        root._start()
    Component.onCompleted: {
        // FileView does not create parent directories, and ~/.local/state/pshell
        // is nothing else's job to make. Notifications does this for the same
        // directory; doing it twice is a no-op and depending on the other
        // service having run first would be a load-order bug waiting.
        Quickshell.execDetached(["mkdir", "-p", root._statePath.substring(0, root._statePath.lastIndexOf("/"))]);
        if (Prefs.loaded)
            root._start();
    }

    function _start() {
        root._retireOldCache();
        if (root.wanted)
            root.refresh();
    }

    // An earlier cut of this service kept the forecast in state.json under
    // `weather.reading`. It has its own file now, and the leftover would
    // otherwise be copied forward by every geocode write for the life of the
    // config -- a kilobyte of dead JSON nothing ever reads again.
    //
    // Idempotent, so it costs one comparison per start once it has run: the
    // write reassigns Prefs.data, the key is gone from the next evaluation,
    // and the guard stops it firing again.
    function _retireOldCache() {
        if (Prefs.weather.reading === undefined)
            return;
        const next = Object.assign({}, Prefs.weather);
        delete next.reading;
        Prefs.setWeather(next);
    }

    // Guarded by the same readiness: this signal also fires once when the
    // binding is first evaluated at startup, and an unguarded refresh there
    // would geocode a name whose cached coordinates are still on their way in
    // from state.json.
    onRequestKeyChanged: if (Prefs.loaded && root.wanted)
        root.refresh()

    // --------------------------------------------------------- persistence
    //
    // The forecast gets a file of its own rather than a corner of state.json.
    //
    // It is rewritten every fifteen minutes for as long as the shell runs, and
    // Prefs.data is read by bindings that have nothing to do with the weather
    // -- the control centre's device list sorts on Prefs.isPinned() -- so a
    // timer-driven writer in there means those bindings re-evaluate and their
    // delegates rebuild, four times an hour, forever, for a value that did not
    // change. The place name stays in Prefs because that write happens when
    // the setting changes and at no other time.
    //
    // Shape taken from Services/Notifications.qml's history: ~/.local/state
    // rather than ~/.config because this is state the shell owns and can
    // regenerate, spelled from the environment because Qt's StateLocation is
    // newer than the rest of that enum and a wrong guess writes nothing
    // silently, and `watchChanges: false` because nothing else ever writes
    // this file -- no watcher means no self-reload and no guard to get wrong.

    readonly property string _statePath: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        const base = xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state";
        return base + "/pshell/weather.json";
    }

    property bool _stateLoaded: false

    // A refresh that chains geocode into forecast can land two writes a few
    // milliseconds apart. Half a second of settling makes that one, the same
    // interval and the same reason as the notification history's.
    Timer {
        id: saveTimer
        interval: 500
        repeat: false
        onTriggered: {
            // The guard every writer in this shell carries: a write before the
            // load finished would truncate the reading it was about to read.
            if (root.fetched === null)
                return;
            if (!root._stateLoaded) {
                // Try again rather than drop the write. A fetch that beat the
                // load home would otherwise leave this session's reading
                // unpersisted until the next one, fifteen minutes later. This
                // terminates: onLoadFailed sets the flag too.
                saveTimer.restart();
                return;
            }
            stateFile.setText(JSON.stringify(root.fetched, null, 2));
        }
    }

    FileView {
        id: stateFile

        path: root._statePath
        watchChanges: false
        blockWrites: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && typeof parsed === "object")
                    root.cached = parsed;
            } catch (e) {
                // A truncated or hand-mangled cache is not worth a warning the
                // user can do nothing about: the next refresh replaces it.
                root.cached = null;
            }
            root._stateLoaded = true;
        }

        // No cache file yet is the normal first run, not an error.
        onLoadFailed: root._stateLoaded = true

        onSaveFailed: error => console.warn("pshell: could not write weather.json —", error)
    }

    // ---------------------------------------------------------------- panel
    //
    // Drawn by the bar widget, which exists once per monitor, so the
    // wanted-open state lives here and the widgets follow it. Phase 4's
    // notification centre records what happens without this: `toggle` on a
    // two-monitor bar opened one panel per monitor and they fought each other
    // over the popout coordinator.

    property bool panelOpen: false
    property string panelScreen: ""

    function openPanel(screenName) {
        // The widget draws this panel, so without one there is nothing to
        // open. Setting the flag anyway would have `pshell weather toggle`
        // exit 0 having done nothing visible, twice, before anyone thought to
        // check the bar config -- and then `close` would be needed to undo a
        // panel that was never on screen.
        if (!root.wanted) {
            console.warn("pshell: no weather widget in the bar, so there is no panel to open");
            return;
        }
        root.panelScreen = screenName !== undefined && String(screenName) !== "" ? String(screenName) : root._focusedScreenName();
        root.panelOpen = true;
        // Opening is the one moment the numbers are certainly being looked at.
        // Guarded by `stale` rather than unconditional: clicking the widget
        // four times must not be four requests, and a reading two minutes old
        // has nothing new behind it.
        if (root.stale || root.reading === null)
            root.refresh();
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

    // Same resolution Notifications uses, for the same reason: IPC has no
    // widget to ask, and the focused monitor is where the eyes are.
    function _focusedScreenName() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            return mon.name;
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    // ------------------------------------------------------------------ IPC
    //
    // One handler, here, for both the panel's lifecycle and the service's own
    // methods. The widget carries `manageIpc: false` rather than an
    // `ipcTarget` of its own: two handlers on one target collide, and with the
    // widget under Variants it would be one collision per monitor.

    IpcHandler {
        target: "pshell.weather"

        function refresh(): void {
            root.refresh();
        }

        // One line, fixed order, no tabs: temperature, condition, place, age.
        function current(): string {
            return W.oneLine(root.reading, Date.now());
        }

        function setLocation(name: string): void {
            const text = String(name || "").trim();
            if (text === "") {
                console.warn("pshell: weather setLocation needs a place name");
                return;
            }
            // Written to config.json rather than held here, because a location
            // typed once is a setting and not session state -- it has to
            // survive a restart, and config.json is the file the user can also
            // edit by hand.
            //
            // Explicit coordinates are cleared with it, and only when there
            // are some: leaving them would make the new name silently do
            // nothing, since coordinates win, and setting them to null
            // unconditionally would rewrite the file three times for a config
            // that never had them.
            if (Config.weather.hasCoordinates) {
                Config.set("weather.latitude", null);
                Config.set("weather.longitude", null);
            }
            Config.set("weather.location", text);
        }

        function toggle(): void {
            root.togglePanel();
        }

        function open(): void {
            root.openPanel();
        }

        function close(): void {
            root.closePanel();
        }
    }
}
