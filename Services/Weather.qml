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
// No keep-alive line in shell.qml, deliberately. Wallpaper and Lock have one
// because IPC is their only door -- neither has a widget. This has a widget,
// and it is the only reason to fetch at all: a shell with no weather widget
// that still talked to Open-Meteo every fifteen minutes would be making a
// network request on the user's behalf for nothing to display. So a bar
// without the widget answers `pshell weather current` with "this shell has no
// 'weather' target", which is the truth rather than a gap.
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
    // separate from it because state.json loads asynchronously: a fetch that
    // lands before the file does must not be overwritten by what was on disk.
    property var fetched: null

    readonly property var cached: Prefs.weather.reading || null
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

            const stored = Object.assign({}, Prefs.weather);
            stored.reading = next;
            // A no-op while state.json is still loading -- Prefs refuses a
            // write before it has read. The reading is correct in memory
            // either way, and the next refresh persists it.
            Prefs.setWeather(stored);
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
            watchdog.stop();
            root.busy = false;
            root._inFlight = null;
            if (root._pending) {
                root._pending = false;
                // After this handler returns, not inside it: a geocode reply
                // starts the forecast request further down, and re-entering
                // refresh() first would find `busy` false and race it.
                Qt.callLater(root.refresh);
            }

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

    // QML's XMLHttpRequest has no `timeout`, so a connection that opens and
    // then hangs -- a captive portal is the usual one -- would leave `busy`
    // set and every later refresh a no-op for the rest of the session. Thirty
    // seconds is far past a healthy round trip and far short of the fifteen
    // minutes until the next attempt.
    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            if (root._inFlight)
                root._inFlight.abort();
        }
    }

    Timer {
        interval: root.intervalMin * 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    // The first fetch waits for state.json, so a shell that already knows
    // where "Bengaluru" is does not ask again on every start. Both halves are
    // needed: the file may already be read by the time this singleton is
    // built, in which case the change signal never comes.
    readonly property bool prefsReady: Prefs.loaded
    onPrefsReadyChanged: if (prefsReady)
        root.refresh()
    Component.onCompleted: if (Prefs.loaded)
        root.refresh()

    // Guarded by the same readiness: this signal also fires once when the
    // binding is first evaluated at startup, and an unguarded refresh there
    // would geocode a name whose cached coordinates are still on their way in
    // from state.json.
    onRequestKeyChanged: if (Prefs.loaded)
        root.refresh()

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
