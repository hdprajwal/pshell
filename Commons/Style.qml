pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

// Everything about the look that is not a colour: rounding, the gap to the
// screen edge, interactive-state affordances, the spacing scale and the type
// scale. Colour lives in Color; the two are fed from the same dictionary.
//
// Token names and resolution are Omarchy's so its widgets resolve here. The
// inputs are qsbar's: config.json supplies the type scale and bar size, and
// rounding and the screen-edge gap are read back from Hyprland so panels
// match window decoration instead of being told the same number twice.
QtObject {
    id: root

    // What Hyprland last reported. cornerRadius mirrors decoration:rounding;
    // gapsOut is half of general:gaps_out, which is tuned as a window-to-
    // window gap and reads as a chasm between a panel and the screen edge.
    property int hyprCornerRadius: 8
    property int hyprGapsOut: 5

    readonly property int cornerRadius: Config.cornerRadiusOverride >= 0 ? Config.cornerRadiusOverride : hyprCornerRadius
    readonly property int gapsOut: Config.gapsOutOverride >= 0 ? Config.gapsOutOverride : hyprGapsOut

    // ---------------------------------------------------------- state tokens
    //
    // Shared interactive-state tokens for every reusable surface. The
    // vocabulary:
    //   normal       - idle control chrome
    //   hover-cursor - mouse hover OR panel keyboard cursor
    //   selected     - persistent chosen/current state
    //   focus        - actual Qt activeFocus, defaulting to hover-cursor
    //
    // A colour token is a palette role (foreground, accent, urgent,
    // background) or a hex colour. A border width of 0 drops that border.
    property var styleOverrides: ({})

    function styleRawNum(key) {
        var v = styleOverrides[key];
        var n = Number(v);
        return isFinite(n) ? n : null;
    }

    function styleNum(key, fallback) {
        var n = styleRawNum(key);
        return n === null ? fallback : n;
    }

    function styleAlpha(key, fallback) {
        return Util.clampAlpha(styleNum(key, fallback));
    }

    function styleString(key, fallback) {
        var v = styleOverrides[key];
        if (typeof v !== "string")
            return fallback;
        v = v.replace(/^\s+|\s+$/g, "");
        return v.length > 0 ? v : fallback;
    }

    readonly property string normalColorToken: styleString("normal-color", "foreground")
    readonly property string hoverColorToken: styleString("hover-cursor-color", "foreground")
    readonly property string selectedColorToken: styleString("selected-color", "foreground")
    readonly property string pressedColorToken: styleString("pressed-color", hoverColorToken)
    readonly property string focusColorToken: styleString("focus-color", hoverColorToken)
    readonly property string selectionColorToken: styleString("selection-color", "foreground")

    readonly property int normalBorderWidth: Math.max(0, Math.round(styleNum("normal-border-width", 1)))
    readonly property int hoverBorderWidth: Math.max(0, Math.round(styleNum("hover-cursor-border-width", normalBorderWidth)))
    readonly property int selectedBorderWidth: Math.max(0, Math.round(styleNum("selected-border-width", 0)))
    readonly property int focusBorderWidth: Math.max(0, Math.round(styleNum("focus-border-width", hoverBorderWidth)))

    readonly property real normalFillAlpha: styleAlpha("normal-fill-alpha", 0.04)
    readonly property real hoverFillAlpha: styleAlpha("hover-cursor-fill-alpha", 0.08)
    readonly property real selectedFillAlpha: styleAlpha("selected-fill-alpha", 0.18)
    readonly property real pressedFillAlpha: styleAlpha("pressed-fill-alpha", 0.22)
    readonly property real focusFillAlpha: styleAlpha("focus-fill-alpha", hoverFillAlpha)
    readonly property real selectionFillAlpha: styleAlpha("selection-fill-alpha", 0.35)

    readonly property real normalBorderAlpha: styleAlpha("normal-border-alpha", 0.4)
    readonly property real hoverBorderAlpha: styleAlpha("hover-cursor-border-alpha", 0.25)
    readonly property real selectedBorderAlpha: styleAlpha("selected-border-alpha", 1.0)
    readonly property real focusBorderAlpha: styleAlpha("focus-border-alpha", hoverBorderAlpha)

    function colorFromHex(value, fallback) {
        var s = String(value || "").replace(/^\s+|\s+$/g, "");
        var shortHex = s.match(/^#([0-9A-Fa-f]{3})$/);
        if (shortHex) {
            var sh = shortHex[1];
            return Qt.rgba(parseInt(sh.charAt(0) + sh.charAt(0), 16) / 255, parseInt(sh.charAt(1) + sh.charAt(1), 16) / 255, parseInt(sh.charAt(2) + sh.charAt(2), 16) / 255, 1);
        }
        var hex = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/);
        if (!hex)
            return fallback;
        var h = hex[1];
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255, hex[2] ? parseInt(hex[2], 16) / 255 : 1);
    }

    function resolveStateColor(token, foreground, accent, urgent, fallback) {
        var fb = fallback || foreground || Color.foreground;
        var s = String(token || "").replace(/^\s+|\s+$/g, "");
        var role = s.toLowerCase();
        if (role === "foreground" || role === "text")
            return foreground || Color.foreground;
        if (role === "accent")
            return accent || Color.accent;
        if (role === "urgent")
            return urgent || Color.urgent;
        if (role === "background")
            return Color.background;
        if (role === "transparent")
            return Qt.rgba(0, 0, 0, 0);
        return colorFromHex(s, fb);
    }

    function normalStateColor(foreground, accent, urgent) {
        return resolveStateColor(normalColorToken, foreground, accent, urgent, foreground || Color.foreground);
    }

    function hoverStateColor(foreground, accent, urgent) {
        return resolveStateColor(hoverColorToken, foreground, accent, urgent, foreground || Color.foreground);
    }

    function selectedStateColor(foreground, accent, urgent) {
        return resolveStateColor(selectedColorToken, foreground, accent, urgent, foreground || Color.foreground);
    }

    function pressedStateColor(foreground, accent, urgent) {
        return resolveStateColor(pressedColorToken, foreground, accent, urgent, hoverStateColor(foreground, accent, urgent));
    }

    function focusStateColor(foreground, accent, urgent) {
        var role = String(focusColorToken || "").replace(/^\s+|\s+$/g, "").toLowerCase();
        if (role === "hover" || role === "hover-cursor" || role === "inherit")
            return hoverStateColor(foreground, accent, urgent);
        return resolveStateColor(focusColorToken, foreground, accent, urgent, hoverStateColor(foreground, accent, urgent));
    }

    function selectionStateColor(foreground, accent, urgent) {
        return resolveStateColor(selectionColorToken, foreground, accent, urgent, foreground || Color.foreground);
    }

    function normalFillFor(foreground, accent, urgent) {
        return Util.alpha(normalStateColor(foreground, accent, urgent), normalFillAlpha);
    }
    function hoverFillFor(foreground, accent, urgent) {
        return Util.alpha(hoverStateColor(foreground, accent, urgent), hoverFillAlpha);
    }
    function selectedFillFor(foreground, accent, urgent) {
        return Util.alpha(selectedStateColor(foreground, accent, urgent), selectedFillAlpha);
    }
    function pressedFillFor(foreground, accent, urgent) {
        return Util.alpha(pressedStateColor(foreground, accent, urgent), pressedFillAlpha);
    }
    function focusFillFor(foreground, accent, urgent) {
        return Util.alpha(focusStateColor(foreground, accent, urgent), focusFillAlpha);
    }
    function selectionFillFor(foreground, accent, urgent) {
        return Util.alpha(selectionStateColor(foreground, accent, urgent), selectionFillAlpha);
    }

    function normalBorderFor(foreground, accent, urgent) {
        return Util.alpha(normalStateColor(foreground, accent, urgent), normalBorderAlpha);
    }
    function hoverBorderFor(foreground, accent, urgent) {
        return Util.alpha(hoverStateColor(foreground, accent, urgent), hoverBorderAlpha);
    }
    function selectedBorderFor(foreground, accent, urgent) {
        return Util.alpha(selectedStateColor(foreground, accent, urgent), selectedBorderAlpha);
    }
    function focusBorderFor(foreground, accent, urgent) {
        return Util.alpha(focusStateColor(foreground, accent, urgent), focusBorderAlpha);
    }

    // The focus > hover > normal ladder every form control surface walks,
    // written once so a TextField and a Dropdown cannot drift apart.
    function controlFill(focused, hot, foreground, accent) {
        if (focused)
            return focusFillFor(foreground, accent);
        if (hot)
            return hoverFillFor(foreground, accent);
        return normalFillFor(foreground, accent);
    }

    function controlBorder(focused, hot, foreground, accent) {
        if (focused)
            return focusBorderFor(foreground, accent);
        if (hot)
            return hoverBorderFor(foreground, accent);
        return normalBorderFor(foreground, accent);
    }

    function controlBorderWidth(focused, hot) {
        if (focused)
            return focusBorderWidth;
        if (hot)
            return hoverBorderWidth;
        return normalBorderWidth;
    }

    // Resolved against the foundational palette, for callers with no local
    // foreground of their own.
    readonly property color normalFill: normalFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color hoverFill: hoverFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color selectedFill: selectedFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color pressedFill: pressedFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color focusFillColor: focusFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color normalBorderColor: normalBorderFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color hoverBorderColor: hoverBorderFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color selectedBorderColor: selectedBorderFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color focusBorderColor: focusBorderFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color selectedAccentFill: Util.alpha(Color.accent, selectedFillAlpha)
    readonly property color selectionFill: selectionFillFor(Color.foreground, Color.accent, Color.urgent)

    // ---------------------------------------------------------------- spacing
    //
    // The shell's equivalent of rem for margins, gaps and padding. A component
    // keeps its proportions by asking for its old pixel value through
    // space(px); the scale then makes the whole shell denser or roomier.
    property real spacingScale: 1.0
    property bool spacingScaleWithFont: true
    property var spacingOverrides: ({})
    readonly property real effectiveSpacingScale: spacingScale * (spacingScaleWithFont ? fontScale : 1)

    function spaceReal(px) {
        var n = Number(px);
        if (!isFinite(n) || n <= 0)
            return 0;
        return n * effectiveSpacingScale;
    }

    function space(px) {
        var n = spaceReal(px);
        if (n <= 0)
            return 0;
        return Math.max(1, Math.round(n));
    }

    function spacingToken(key, fallback) {
        var v = spacingOverrides[key];
        var n = Number(v);
        return (isFinite(n) && n >= 0) ? Math.round(n) : space(fallback);
    }

    readonly property QtObject spacing: QtObject {
        readonly property real scale: root.effectiveSpacingScale

        readonly property int hairline: root.space(1)
        readonly property int xxs: root.spacingToken("xxs", 2)
        readonly property int xs: root.spacingToken("xs", 3)
        readonly property int sm: root.spacingToken("sm", 4)
        readonly property int md: root.spacingToken("md", 6)
        readonly property int lg: root.spacingToken("lg", 8)
        readonly property int xl: root.spacingToken("xl", 10)
        readonly property int xxl: root.spacingToken("xxl", 12)
        readonly property int xxxl: root.spacingToken("xxxl", 14)
        readonly property int huge: root.spacingToken("huge", 18)

        readonly property int controlGap: root.spacingToken("control-gap", 8)
        readonly property int controlPaddingX: root.spacingToken("control-padding-x", 10)
        readonly property int controlPaddingY: root.spacingToken("control-padding-y", 6)
        readonly property int inputPaddingY: root.spacingToken("input-padding-y", 7)
        readonly property int controlHeight: root.spacingToken("control-height", 28)
        readonly property int popupRowHeight: root.spacingToken("popup-row-height", 28)
        readonly property int dropdownWidth: root.spacingToken("dropdown-width", 240)
        readonly property int searchableDropdownWidth: root.spacingToken("searchable-dropdown-width", 260)
        readonly property int numberFieldWidth: root.spacingToken("number-field-width", 120)
        readonly property int searchablePopupMinHeight: root.spacingToken("searchable-popup-min-height", 220)
        readonly property int rowGap: root.spacingToken("row-gap", 8)
        readonly property int rowPaddingX: root.spacingToken("row-padding-x", 12)
        readonly property int labelGap: root.spacingToken("label-gap", 4)
        readonly property int panelGap: root.spacingToken("panel-gap", 14)
        readonly property int panelPadding: root.spacingToken("panel-padding", 18)
        readonly property int popupPadding: root.spacingToken("popup-padding", 14)
        // Distance between adjacent widgets in a bar section. qsbar's own
        // token; Omarchy lays its bar out from iconSlot instead.
        readonly property int barGap: root.spacingToken("bar-gap", 12)
    }

    // ------------------------------------------------------------- typography
    property string fontFamily: Config.fontFamily

    // The concrete family the alias resolves to right now, e.g.
    // "JetBrainsMono Nerd Font". Bind font.family to fontFamily; read
    // resolvedFamily only to *display* what is drawing.
    property string resolvedFontFamily: Config.fontFamily

    // Glyph font for bar icons. qsbar's own token: an icon theme cannot
    // always answer, and a Nerd Font glyph is the fallback that keeps a
    // widget legible. Omarchy has no equivalent and never asks for it.
    readonly property string iconFontFamily: styleString("icon-family", Config.iconFont)

    // Material Symbols Rounded, the set DMS draws with, shipped in-tree so it
    // is always there. Separate from iconFamily because the two are addressed
    // differently: a Nerd Font icon is a codepoint, a Material Symbol is a
    // ligature spelled out ("wifi", "battery_5_bar").
    readonly property string symbolFontFamily: styleString("symbol-family", Fonts.symbols)

    property int fontBaseSize: 12

    property var fontOverrides: ({})
    property var barOverrides: ({})
    property bool barScaleWithFont: true
    readonly property real fontScale: Math.max(1 / 12, fontBaseSize / 12)

    function fontPx(mult) {
        return Math.max(1, Math.round(fontBaseSize * mult));
    }

    function fontToken(key, fallback) {
        var v = fontOverrides[key];
        var n = Number(v);
        return (isFinite(n) && n > 0) ? Math.round(n) : fallback;
    }

    function barToken(key, fallback) {
        var v = barOverrides[key];
        var n = Number(v);
        var base = (isFinite(n) && n > 0) ? n : fallback;
        if (barScaleWithFont)
            base *= fontScale;
        return Math.max(1, Math.round(base));
    }

    function boolToken(value, fallback) {
        if (value === undefined || value === null)
            return fallback;
        var s = String(value).replace(/^\s+|\s+$/g, "").toLowerCase();
        if (s === "true" || s === "1" || s === "yes" || s === "on")
            return true;
        if (s === "false" || s === "0" || s === "no" || s === "off")
            return false;
        return fallback;
    }

    readonly property string menuFontFamily: root.fontFamily

    readonly property QtObject font: QtObject {
        readonly property string family: root.fontFamily
        readonly property string resolvedFamily: root.resolvedFontFamily
        readonly property string menuFamily: root.menuFontFamily
        readonly property string iconFamily: root.iconFontFamily
        readonly property string symbolFamily: root.symbolFontFamily
        readonly property int baseSize: root.fontBaseSize

        readonly property int caption: root.fontToken("caption", root.fontPx(0.833))
        readonly property int bodySmall: root.fontToken("body-small", root.fontPx(0.917))
        readonly property int body: root.fontToken("body", root.fontPx(1.0))
        readonly property int subtitle: root.fontToken("subtitle", root.fontPx(1.083))
        readonly property int title: root.fontToken("title", root.fontPx(1.167))
        readonly property int heading: root.fontToken("heading", root.fontPx(1.333))
        readonly property int display: root.fontToken("display", root.fontPx(2.0))
        readonly property int displayLarge: root.fontToken("display-large", root.fontPx(2.333))

        readonly property int iconSmall: root.fontToken("icon-small", bodySmall)
        readonly property int icon: root.fontToken("icon", title)
        readonly property int iconLarge: root.fontToken("icon-large", root.fontPx(1.5))
    }

    readonly property QtObject bar: QtObject {
        readonly property int sizeHorizontal: root.barToken("size-horizontal", 26)
        readonly property int sizeVertical: root.barToken("size-vertical", 28)
        readonly property int iconSlot: root.barToken("icon-slot", 27)
        readonly property int iconCanvas: root.barToken("icon-canvas", 16)
        readonly property int iconFont: root.barToken("icon-font", 13)
        readonly property int statusSlot: root.barToken("status-slot", 21)
    }

    // Pull typography, bar dimensions, state tokens and spacing out of the
    // dictionary Color assembled, so one parse feeds both singletons.
    function applyShellValues(values) {
        var fontOut = {};
        var barOut = {};
        var styleOut = {};
        var spacingOut = {};
        var nextBase = 12;
        var nextSpacingScale = 1.0;
        var nextSpacingScaleWithFont = true;
        var nextBarScaleWithFont = true;
        var v = values || ({});
        for (var fullKey in v) {
            var dot = fullKey.indexOf(".");
            if (dot < 0)
                continue;
            var section = fullKey.substr(0, dot);
            var key = fullKey.substr(dot + 1);
            var raw = v[fullKey];
            if (section === "font") {
                if (key === "family" || key === "icon-family") {
                    styleOut[key] = raw;
                    continue;
                }
                var ival = parseInt(raw, 10);
                if (!isFinite(ival))
                    continue;
                if (key === "base-size")
                    nextBase = ival;
                else
                    fontOut[key] = ival;
            } else if (section === "bar") {
                if (key === "scale-with-font") {
                    nextBarScaleWithFont = boolToken(raw, nextBarScaleWithFont);
                } else {
                    var b = parseInt(raw, 10);
                    if (isFinite(b))
                        barOut[key] = b;
                }
            } else if (section === "spacing") {
                if (key === "scale-with-font") {
                    nextSpacingScaleWithFont = boolToken(raw, nextSpacingScaleWithFont);
                } else {
                    var fval = parseFloat(raw);
                    if (!isFinite(fval))
                        continue;
                    if (key === "scale")
                        nextSpacingScale = fval;
                    else
                        spacingOut[key] = fval;
                }
            } else if (section === "controls" || section === "style") {
                // Strings pass through; styleRawNum/styleString coerce on read.
                // [style] is the older name for [controls].
                styleOut[key] = raw;
            }
        }
        // A 1px sanity floor and nothing more. A theme that wants
        // display-large at 64 is allowed to have it.
        if (!isFinite(nextBase) || nextBase < 1)
            nextBase = 1;
        if (!isFinite(nextSpacingScale) || nextSpacingScale < 0)
            nextSpacingScale = 1.0;
        spacingScale = nextSpacingScale;
        spacingScaleWithFont = nextSpacingScaleWithFont;
        fontBaseSize = nextBase;
        fontOverrides = fontOut;
        barOverrides = barOut;
        barScaleWithFont = nextBarScaleWithFont;
        spacingOverrides = spacingOut;
        styleOverrides = styleOut;
    }

    function refresh() {
        roundingProc.running = true;
        gapsOutProc.running = true;
    }

    // Hyprland reloads sourced config asynchronously, so an immediate hyprctl
    // races it and reads the old value. Omarchy's theme IPC calls this after
    // applying a theme; a widget that changes a Hyprland option can too.
    function scheduleRefresh() {
        refreshTimer.restart();
    }

    property Timer refreshTimer: Timer {
        id: refreshTimer
        interval: 200
        repeat: false
        onTriggered: root.refresh()
    }

    function applyRoundingJson(raw) {
        try {
            var json = JSON.parse(raw || "{}");
            var n = Number(json.int);
            if (isFinite(n) && n >= 0)
                hyprCornerRadius = n;
        } catch (e)
        // hyprctl missing, or Hyprland is not running. Keep the last value.
        {}
    }

    function applyGapsOutJson(raw) {
        try {
            var json = JSON.parse(raw || "{}");
            var css = String(json.custom || json.css || "");
            var parts = css.match(/-?\d+(?:\.\d+)?/g) || [];
            var n = parts.length > 0 ? Number(parts[0]) : Number(json.int);
            if (isFinite(n) && n >= 0)
                hyprGapsOut = Math.max(0, Math.round(n / 2));
        } catch (e) {}
    }

    property Process roundingProc: Process {
        id: roundingProc
        command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyRoundingJson(text)
        }
    }

    property Process gapsOutProc: Process {
        id: gapsOutProc
        command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyGapsOutJson(text)
        }
    }

    // Resolve the fontconfig alias to a concrete family, so a widget that
    // wants to name the font it is drawing in can.
    property Process fcMatchProc: Process {
        command: ["fc-match", "-f", "%{family[0]}", Config.fontFamily]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var name = String(text || "").trim();
                if (name.length > 0)
                    root.resolvedFontFamily = name;
            }
        }
    }

    function resolveFontFamily() {
        fcMatchProc.running = true;
    }

    Component.onCompleted: {
        refresh();
        resolveFontFamily();
    }
}
