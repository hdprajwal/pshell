pragma Singleton

import QtCore
import Quickshell
import Quickshell.Io

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
    // here: they are usually already installed, so qsbar ships no font of its own.
    // Size of icons drawn in the bar itself. Popout and panel icons size
    // themselves off the font instead, so this does not touch them.
    readonly property int barIconSize: data.barIconSize || Math.round(size * 0.55)
    readonly property string iconFont: data.iconFont || "JetBrainsMono Nerd Font"
    readonly property string urgent: data.urgent || Theme.urgent || "#f38ba8"

    // "manual" uses the colours above as written. "wallpaper" runs matugen on
    // `wallpaper` and fills in whatever you have not set yourself.
    readonly property string theme: data.theme || "manual"
    readonly property string mode: data.mode === "light" ? "light" : "dark"
    readonly property string wallpaper: data.wallpaper || ""
    readonly property string wallpaperPath: {
        const path = String(wallpaper);
        if (path.indexOf("~/") === 0)
            return Quickshell.env("HOME") + path.substring(1);
        return path;
    }
    readonly property string matugenScheme: data.matugenScheme || "scheme-tonal-spot"
    // matugen refuses to guess when an image has several candidate source
    // colours and no terminal to ask, so a preference is mandatory here.
    readonly property string matugenPrefer: data.matugenPrefer || "saturation"
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
    // under ~/.config/qsbar/shell.toml and hands the result to Style, so one
    // dictionary drives both qs.Components and every qs.Ui widget.
    //
    // Only tokens where qsbar wants something other than Omarchy's built-in
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
            // container next to qsbar's flat bar.
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

    FileView {
        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/qsbar/config.json"
        watchChanges: true
        blockLoading: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {
                console.warn("qsbar: bad config.json —", e);
            }
        }
    }
}
