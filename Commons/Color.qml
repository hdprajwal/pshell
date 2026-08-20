pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "BorderGeometry.js" as Geometry

// The palette, and the only place colour is decided.
//
// Structure, token names and resolution rules are Omarchy's, so a widget
// written for that shell finds what it expects. What differs is where the
// values come from: Omarchy reads a theme's colors.toml and shell.toml, while
// qsbar takes the foundational palette from config.json (or matugen, when the
// theme is derived from the wallpaper) and expresses the rest of config.json
// as Omarchy tokens.
//
// Both stacks read this singleton. qs.Components and qs.Ui are drawn from one
// dictionary, so a colour has one definition rather than one per kit.
QtObject {
    id: root

    readonly property color foreground: Config.fg
    readonly property color background: Config.bg
    readonly property color accent: Config.accent
    readonly property color urgent: Config.urgent
    readonly property color muted: Config.dim

    // Flat "section.key" -> raw string dictionary. Reassigning the whole
    // property is what makes the surface roles below re-evaluate; mutating it
    // in place would not.
    property var shellValues: ({})

    function pick(key, fallback) {
        var v = shellValues[key];
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    function pickAlpha(key, fallback) {
        var v = shellValues[key];
        if (typeof v !== "string" || v.length === 0)
            return fallback;
        var n = Number(v);
        if (!isFinite(n))
            return fallback;
        return Util.clampAlpha(n);
    }

    function firstColorToken(value) {
        var parts = String(value || "").replace(/^\s+|\s+$/g, "").split(/\s+/);
        for (var i = 0; i < parts.length; i++) {
            if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/))
                return parts[i];
        }
        return value;
    }

    // A token is a role name, another token to chase, or a literal colour.
    function flatColor(value, fallback) {
        var token = firstColorToken(value);
        var role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase();
        if (root.shellValues[role] && root.shellValues[role] !== token)
            return flatColor(root.shellValues[role], fallback);
        if (role === "foreground" || role === "text")
            return root.foreground;
        if (role === "accent")
            return root.accent;
        if (role === "urgent")
            return root.urgent;
        if (role === "muted")
            return root.muted;
        if (role === "background")
            return root.background;
        if (role === "transparent")
            return Qt.rgba(0, 0, 0, 0);

        var color = Geometry.canonicalColor(token, 1);
        if (typeof color === "string" && color === token && token.charAt(0) !== "#")
            return fallback;
        return color;
    }

    // Compose a colour from a base key and its `-alpha` companion. A gradient
    // token collapses to its first stop for callers that want one colour.
    function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
        return Util.alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback));
    }

    readonly property QtObject bar: QtObject {
        property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
        property color text: root.pick("bar.text", root.foreground)
        property color active: root.pick("bar.active", root.accent)
        // qs.Components grew up calling the readable colour `foreground`.
        property color foreground: bar.text
        property color border: root.composed("bar.border", "bar.border-alpha", root.foreground, 0.15)
    }
    readonly property QtObject popups: QtObject {
        property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
        property color text: root.pick("popups.text", root.foreground)
        property color border: root.composed("popups.border", "popups.border-alpha", root.accent, 1.0)
        property color foreground: popups.text
    }
    readonly property QtObject tooltip: QtObject {
        property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 1.0)
        property color text: root.pick("tooltip.text", root.foreground)
        property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
        property color foreground: tooltip.text
    }
    readonly property QtObject notifications: QtObject {
        property color background: root.composed("notifications.background", "notifications.background-alpha", root.background, 1.0)
        property color text: root.pick("notifications.text", root.foreground)
        property color border: root.composed("notifications.border", "notifications.border-alpha", root.accent, 1.0)
        property color countdown: root.pick("notifications.countdown", root.accent)
    }
    readonly property QtObject menu: QtObject {
        property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
        property color text: root.pick("menu.text", root.foreground)
        property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
        property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)
        property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.foreground, 0.08)
        property color selectedText: root.pick("menu.selected-text", root.accent)
        property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
        property color foreground: menu.text
    }
    // polkit and lock share one border-alpha across border / border-active /
    // border-error: the three states are mutually exclusive in time.
    readonly property QtObject polkit: QtObject {
        property color background: root.composed("polkit.background", "polkit.background-alpha", root.background, 1.0)
        property color text: root.pick("polkit.text", root.foreground)
        property color textError: root.pick("polkit.text-error", root.urgent)
        property color border: root.composed("polkit.border", "polkit.border-alpha", root.accent, 1.0)
        property color borderError: root.composed("polkit.border-error", "polkit.border-alpha", root.urgent, 1.0)
        property color accent: root.pick("polkit.accent", root.accent)
        property color scrim: root.composed("polkit.scrim", "polkit.scrim-alpha", root.background, 0.5)
    }
    readonly property QtObject lock: QtObject {
        property color background: root.composed("lock.background", "lock.background-alpha", root.background, 0.8)
        property color text: root.pick("lock.text", root.foreground)
        property color placeholder: root.shellValues["lock.placeholder"] ? root.flatColor(root.shellValues["lock.placeholder"], Util.alpha(root.foreground, 0.66)) : Util.alpha(root.foreground, 0.66)
        property color textError: root.pick("lock.text-error", root.urgent)
        property color border: root.composed("lock.border", "lock.border-alpha", root.foreground, 1.0)
        property color borderActive: root.composed("lock.border-active", "lock.border-alpha", root.accent, 1.0)
        property color borderError: root.composed("lock.border-error", "lock.border-alpha", root.urgent, 1.0)
        property color selection: root.composed("lock.selection", "lock.selection-alpha", root.accent, 0.45)
    }
    readonly property QtObject imagePicker: QtObject {
        property color scrim: root.composed("image-picker.scrim", "image-picker.scrim-alpha", root.background, 0.5)
        property color text: root.pick("image-picker.text", root.foreground)
        property color selectedBorder: root.composed("image-picker.selected-border", "image-picker.selected-border-alpha", root.accent, 1.0)
        property color unselectedBorder: root.composed("image-picker.unselected-border", "image-picker.unselected-border-alpha", root.foreground, 0.28)
    }

    // Where Omarchy keeps its own theme, for a widget that wants to load an
    // asset out of it. qsbar takes no colour from here — the palette comes
    // from config.json and matugen — but the paths are the same ones.
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    readonly property string currentThemePath: stateHome + "/omarchy/current/theme"

    // Three layers, weakest first: config.json expressed as tokens, then
    // anything pushed in at runtime, then the hand-written override file. A
    // token tuned in one survives an edit to another.
    readonly property var themeShellValues: Config.shellDefaults
    property var pushedShellValues: ({})
    property var userShellValues: ({})

    onThemeShellValuesChanged: mergeShell()

    // Omarchy's shell.toml walker. Accepts quoted strings, bare numbers, bare
    // width lists and bare role names, and tolerates inline comments. Values
    // stay strings; readers coerce when they pull one.
    function parseShell(raw) {
        var parsed = {};
        var text = String(raw || "");
        if (text) {
            var lines = text.split("\n");
            var section = "";
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].replace(/^\s+|\s+$/g, "");
                if (!line || line.charAt(0) === "#")
                    continue;
                var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/);
                if (sectionMatch) {
                    section = sectionMatch[1];
                    continue;
                }
                var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/);
                var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/);
                var widthKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3})\s*(#.*)?$/);
                var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/);
                var kv = stringKv || numKv || widthKv || bareKv;
                if (!kv || !section)
                    continue;
                parsed[section + "." + kv[1]] = kv[2];
            }
        }
        return parsed;
    }

    // Re-derive shellValues from config.json plus the override file and push
    // the result to Style, so a single parse feeds both singletons.
    function mergeShell() {
        var merged = {};
        var base = themeShellValues || ({});
        for (var tk in base)
            merged[tk] = base[tk];
        for (var pk in pushedShellValues)
            merged[pk] = pushedShellValues[pk];
        for (var uk in userShellValues)
            merged[uk] = userShellValues[uk];
        shellValues = merged;
        Style.applyShellValues(merged);
    }

    function loadUserShell(raw) {
        userShellValues = parseShell(raw);
        mergeShell();
    }

    // Omarchy's shell reads a theme's shell.toml and pushes it in here on a
    // theme switch. qsbar has no theme switcher of its own, but the entry
    // point works, so anything driving one gets the same result.
    function loadShell(raw) {
        pushedShellValues = parseShell(raw);
        mergeShell();
    }

    Component.onCompleted: mergeShell()

    // Optional, and absent by default. Anything Omarchy's shell.toml accepts
    // works here, which is how a token with no config.json key of its own
    // still gets tuned.
    property FileView userShellFile: FileView {
        path: Quickshell.env("HOME") + "/.config/qsbar/shell.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadUserShell(text())
        // text() is stale inside the change signal, so route both paths
        // through reload -> onLoaded and always parse fresh content.
        onFileChanged: reload()
        onLoadFailed: root.loadUserShell("")
    }
}
