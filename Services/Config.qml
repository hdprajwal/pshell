pragma Singleton

import QtCore
import Quickshell
import Quickshell.Io
import "ConfigPath.js" as ConfigPath

Singleton {
    id: root

    property var data: ({})

    readonly property string position: data.position || "top"
    readonly property int size: data.size || 30
    // Explicit colours win, then anything matugen derived from the wallpaper,
    // then the built-in defaults.
    readonly property string bg: data.bg || Theme.bg || "#1e1e2e"
    readonly property string fg: data.fg || Theme.fg || "#cdd6f4"
    readonly property string accent: data.accent || Theme.accent || "#89b4fa"
    readonly property string dim: data.dim || Theme.dim || "#6c7086"
    readonly property string fontFamily: data.font || "monospace"
    readonly property int fontSize: data.fontSize || 12
    // Glyph font for widget icons. Nerd Fonts are the least intrusive choice
    // here: they are usually already installed, so pshell ships no font of its own.
    // Size of icons drawn in the bar itself. Popout and panel icons size
    // themselves off the font instead, so this does not touch them.
    readonly property int barIconSize: data.barIconSize || Math.round(size * 0.55)
    readonly property string iconFont: data.iconFont || "JetBrainsMono Nerd Font"
    readonly property string urgent: data.urgent || Theme.urgent || "#f38ba8"

    // "manual" uses the colours above as written. "wallpaper" runs matugen on
    // `wallpaper` and fills in whatever you have not set yourself.
    readonly property string theme: data.theme || "manual"
    // Setting `mode` pins it. Leaving it out follows the desktop, so the
    // control centre's Dark Mode tile — or GNOME settings, or anything else
    // that writes the GTK colour-scheme — restyles the shell along with
    // everything else, rather than only the GTK apps.
    readonly property string mode: {
        if (data.mode === "light")
            return "light";
        if (data.mode === "dark")
            return "dark";
        return SystemTheme.scheme;
    }
    readonly property string wallpaper: data.wallpaper || ""
    readonly property string wallpaperPath: expandHome(wallpaper)

    // A leading ~/ is what anyone writes in a config file by hand, and
    // nothing downstream -- matugen, Image.source -- understands it. Shared
    // with the lock's own wallpaper setting, which takes paths from the same
    // hands.
    function expandHome(path) {
        const p = String(path || "");
        if (p.indexOf("~/") === 0)
            return Quickshell.env("HOME") + p.substring(1);
        return p;
    }
    readonly property string matugenScheme: data.matugenScheme || "scheme-tonal-spot"
    // matugen refuses to guess when an image has several candidate source
    // colours and no terminal to ask, so a preference is mandatory here.
    readonly property string matugenPrefer: data.matugenPrefer || "saturation"

    // Everything the lockscreen reads, under one `lock` object.
    //
    // Grouped rather than flattened into `lockDim`, `lockBlur` and friends
    // because this is the first part of the shell that is not the bar, and a
    // flat namespace shared with `position` and `size` would stop saying
    // which is which. Colours are not here: the lock paints itself from
    // Color.lock.*, which is Omarchy's token group, so it restyles with the
    // rest of the shell rather than carrying a second palette.
    readonly property QtObject lock: QtObject {
        // `raw`, not `data`: `data` is what the enclosing singleton calls the
        // whole config, and two of them one scope apart reads as a bug.
        readonly property var raw: root.data.lock && typeof root.data.lock === "object" ? root.data.lock : ({})

        function _bool(key, fallback) {
            const v = raw[key];
            return typeof v === "boolean" ? v : fallback;
        }

        function _num(key, fallback, lo, hi) {
            const v = Number(raw[key]);
            if (!isFinite(v))
                return fallback;
            return Math.min(hi, Math.max(lo, v));
        }

        function _str(key, fallback) {
            const v = raw[key];
            return typeof v === "string" && v !== "" ? v : fallback;
        }

        // The auth stack to run. /etc/pam.d/hyprlock and /etc/pam.d/swaylock
        // are both nothing but `auth include login`, so `login` is the same
        // stack they use and needs no file installed as root.
        readonly property string pamService: _str("pamService", "login")

        // Defaults to the bar's own wallpaper, so the lock shows the picture
        // its colours were derived from without being told twice.
        readonly property string wallpaper: _str("wallpaper", root.wallpaper)
        readonly property string wallpaperPath: root.expandHome(wallpaper)

        readonly property bool blur: _bool("blur", true)
        readonly property real blurAmount: _num("blurAmount", 0.75, 0, 1)
        // Scrim over the wallpaper. Without one, a pale photograph makes
        // every label on top of it unreadable.
        readonly property real dim: _num("dim", 0.45, 0, 1)

        readonly property bool showClock: _bool("showClock", true)
        readonly property string clockFormat: _str("clockFormat", "HH:mm")
        readonly property string dateFormat: _str("dateFormat", "dddd, d MMMM")
        readonly property bool showAvatar: _bool("showAvatar", true)
        readonly property bool showStatus: _bool("showStatus", true)
        readonly property string placeholder: _str("placeholder", "Enter Password")
    }

    // Three separate distances, which used to be one:
    //   gap     - between two widgets in a section
    //   padding - between the bar's own edge and the first or last widget
    //   margin  - between the bar and the screen edge, which detaches it
    // `padding` defaults to `gap` because that is what it was before it had
    // a name of its own, so a config written without it looks unchanged.
    readonly property int gap: data.gap !== undefined ? data.gap : 12
    readonly property int padding: data.padding !== undefined ? data.padding : gap

    // A number margins every side equally; an object sets the sides it names
    // and leaves the rest at zero. A bar anchored to the top only ever shows
    // three of them, but naming all four keeps one spelling for every
    // position.
    readonly property var margin: {
        const m = data.margin;
        const out = {
            top: 0,
            bottom: 0,
            left: 0,
            right: 0
        };
        if (typeof m === "number") {
            out.top = out.bottom = out.left = out.right = Math.max(0, Math.round(m));
            return out;
        }
        if (m && typeof m === "object") {
            for (var side in out) {
                const v = Number(m[side]);
                if (isFinite(v))
                    out[side] = Math.max(0, Math.round(v));
            }
        }
        return out;
    }

    // Style takes its rounding and screen-edge gap from Hyprland, so panels
    // match window decoration without being told twice. These are the escape
    // hatch: -1 means "not set here", and Style keeps asking the compositor.
    readonly property int cornerRadiusOverride: data.cornerRadius !== undefined ? data.cornerRadius : -1
    readonly property int gapsOutOverride: data.gapsOut !== undefined ? data.gapsOut : -1
    readonly property real spacingScale: data.spacingScale || 1.0
    readonly property bool scaleWithFont: data.scaleWithFont !== false

    // config.json expressed in Omarchy's token vocabulary. Color merges this
    // under ~/.config/pshell/shell.toml and hands the result to Style, so one
    // dictionary drives both qs.Components and every qs.Ui widget.
    //
    // Only tokens where pshell wants something other than Omarchy's built-in
    // default belong here; anything absent falls through to that default.
    readonly property var shellDefaults: {
        const out = {
            "font.base-size": String(fontSize),
            "bar.size-horizontal": String(size),
            "bar.size-vertical": String(size),
            "bar.icon-canvas": String(barIconSize),
            "spacing.bar-gap": String(gap),
            "spacing.bar-padding": String(padding),
            "spacing.bar-margin-top": String(margin.top),
            "spacing.bar-margin-bottom": String(margin.bottom),
            "spacing.bar-margin-left": String(margin.left),
            "spacing.bar-margin-right": String(margin.right),
            "spacing.scale": String(spacingScale),
            "spacing.scale-with-font": scaleWithFont ? "true" : "false",
            // A panel edge that states itself quietly. Omarchy's default is a
            // solid 2px accent, which reads as a highlight rather than a
            // container next to pshell's flat bar.
            "popups.border": "foreground",
            "popups.border-alpha": "0.15",
            "popups.border-width": "1",
            "spacing.popup-padding": "12",
            "tooltip.border": "foreground",
            "tooltip.border-alpha": "0.15",
            "menu.border": "foreground",
            "menu.border-alpha": "0.15"
        };
        const extra = data.shell;
        if (extra && typeof extra === "object") {
            for (var key in extra)
                out[key] = String(extra[key]);
        }
        return out;
    }

    readonly property var left: data.left || []
    readonly property var center: data.center || []
    readonly property var right: data.right || []

    // -------------------------------------------------------------- writing
    //
    // This reverses the invariant Prefs.qml was created to protect. Until
    // now nothing in the shell ever rewrote config.json, so a hand-edited
    // file was safe from the shell's own opinions, and anything the shell
    // needed to remember went to state.json instead.
    //
    // The settings app changes that: it owns config.json and may rewrite it.
    // The visible consequence, recorded here so it is not discovered later as
    // a bug: the first write normalises the file to two-space JSON. Nothing
    // is lost semantically -- JSON has no comments -- but key order and hand
    // formatting will not survive it.
    //
    // state.json keeps its role for shell-owned runtime state: pinned sinks,
    // and the settings window's last tab and size.

    property bool _loaded: false
    property bool _writing: false

    function set(dottedPath, value) {
        if (!root._loaded)
            return;
        root.data = ConfigPath.setPath(root.data, dottedPath, value);
        _save();
    }

    function setWidgetSetting(widgetId, key, value) {
        if (!root._loaded)
            return;
        root.data = ConfigPath.setWidgetSetting(root.data, widgetId, key, value);
        _save();
    }

    function hasWidget(widgetId) {
        return ConfigPath.findWidget(root.data, widgetId) !== null;
    }

    function widgetSetting(widgetId, key, fallback) {
        const found = ConfigPath.findWidget(root.data, widgetId);
        if (found === null)
            return fallback;
        const value = root.data[found.section][found.index][key];
        return value === undefined || value === null ? fallback : value;
    }

    // The guard exists so an early write cannot truncate a config that has
    // not finished loading -- the same reason Prefs.qml carries one.
    function _save() {
        root._writing = true;
        configFile.setText(JSON.stringify(root.data, null, 2));
    }

    FileView {
        id: configFile

        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/pshell/config.json"
        watchChanges: true
        blockLoading: true
        atomicWrites: true
        blockWrites: false
        printErrors: false

        // Our own write fires the watcher a moment later. Reloading then is
        // not wrong -- the file says what we just put in it -- but with two
        // writes in flight the reload can land between them and hand `data`
        // back the older of the two, undoing a setting the user just
        // changed. Skipping the reload we caused avoids the race entirely;
        // an edit made in a text editor still reloads, which is the point of
        // watching.
        onFileChanged: {
            if (root._writing)
                return;
            reload();
        }

        onSaved: root._writing = false

        onSaveFailed: error => {
            root._writing = false;
            console.warn("pshell: could not write config.json —", error);
        }

        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {
                console.warn("pshell: bad config.json —", e);
            }
            root._loaded = true;
        }

        // No config file yet is a normal first run, not an error -- but the
        // shell must still know loading finished, or the first write would be
        // refused forever.
        onLoadFailed: root._loaded = true
    }
}
