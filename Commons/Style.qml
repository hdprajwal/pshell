pragma Singleton

import QtQuick
import qs.Services

// Sizing, type scale, and control state colors. Token names match Omarchy's
// qs.Commons.Style so its widgets resolve here. qsbar reads them from
// config.json instead of a theme TOML.
QtObject {
    id: root

    // Same shape as Color.shellValues: Omarchy's per-token style overrides
    // from a theme file. Empty here, so the built-in defaults win.
    readonly property var styleOverrides: ({})

    readonly property int cornerRadius: Config.cornerRadius
    readonly property int gapsOut: Config.gapsOut

    readonly property string fontFamily: Config.fontFamily
    readonly property int fontBaseSize: Math.max(1, Config.fontSize)
    readonly property real spacingScale: Config.spacingScale

    // Omarchy's spacing scale is calibrated against a 12px base font, so a
    // larger font grows the padding with it.
    readonly property real effectiveSpacingScale: spacingScale * (Config.scaleWithFont ? fontBaseSize / 12 : 1)

    function spaceReal(px) {
        const n = Number(px);
        if (!isFinite(n) || n <= 0)
            return 0;
        return n * effectiveSpacingScale;
    }

    function space(px) {
        const n = spaceReal(px);
        if (n <= 0)
            return 0;
        return Math.max(1, Math.round(n));
    }

    function fontPx(multiplier) {
        return Math.max(1, Math.round(fontBaseSize * multiplier));
    }

    readonly property QtObject font: QtObject {
        readonly property string family: root.fontFamily
        readonly property string resolvedFamily: root.fontFamily
        readonly property string menuFamily: root.fontFamily
        readonly property int baseSize: root.fontBaseSize

        readonly property int caption: root.fontPx(0.833)
        readonly property int bodySmall: root.fontPx(0.917)
        readonly property int body: root.fontPx(1.0)
        readonly property int subtitle: root.fontPx(1.083)
        readonly property int title: root.fontPx(1.167)
        readonly property int heading: root.fontPx(1.333)
        readonly property int display: root.fontPx(2.0)
        readonly property int displayLarge: root.fontPx(2.333)

        readonly property int iconSmall: bodySmall
        readonly property int icon: title
        readonly property int iconLarge: root.fontPx(1.5)
    }

    readonly property QtObject bar: QtObject {
        readonly property int sizeHorizontal: Config.size
        readonly property int sizeVertical: Config.size
        readonly property int iconSlot: root.space(27)
        readonly property int iconCanvas: root.space(16)
        readonly property int iconFont: root.fontPx(1.083)
        readonly property int statusSlot: root.space(21)
    }

    readonly property QtObject spacing: QtObject {
        readonly property int controlPaddingX: root.space(10)
        readonly property int controlPaddingY: root.space(6)
        readonly property int inputPaddingY: root.space(6)
        readonly property int controlHeight: root.space(28)
        readonly property int popupRowHeight: root.space(28)
        readonly property int controlGap: root.space(6)
        readonly property int labelGap: root.space(8)
        readonly property int rowGap: root.space(8)
        readonly property int rowPaddingX: root.space(10)
        readonly property int panelGap: root.space(12)
        readonly property int panelPadding: root.space(16)
        readonly property int popupPadding: root.space(12)

        // The t-shirt scale and the fixed control widths Omarchy's UI kit uses
        // throughout. Same defaults as theirs, put through qsbar's own space()
        // so they scale with the configured font like everything else here.
        readonly property real scale: root.effectiveSpacingScale
        readonly property int hairline: root.space(1)
        readonly property int xxs: root.space(2)
        readonly property int xs: root.space(3)
        readonly property int sm: root.space(4)
        readonly property int md: root.space(6)
        readonly property int lg: root.space(8)
        readonly property int xl: root.space(10)
        readonly property int xxl: root.space(12)
        readonly property int xxxl: root.space(14)
        readonly property int huge: root.space(18)
        readonly property int dropdownWidth: root.space(240)
        readonly property int searchableDropdownWidth: root.space(260)
        readonly property int numberFieldWidth: root.space(120)
        readonly property int searchablePopupMinHeight: root.space(220)
    }

    // Control state chrome. Omarchy lets a theme retune every alpha; qsbar
    // fixes them at Omarchy's defaults, which is enough for widgets to look
    // right without a theme file.
    readonly property real normalFillAlpha: 0.04
    readonly property real hoverFillAlpha: 0.08
    readonly property real selectedFillAlpha: 0.18
    readonly property real pressedFillAlpha: 0.22
    readonly property real focusFillAlpha: hoverFillAlpha
    readonly property real selectionFillAlpha: 0.35

    readonly property real normalBorderAlpha: 0.4
    readonly property real hoverBorderAlpha: 0.25
    readonly property real selectedBorderAlpha: 1.0
    readonly property real focusBorderAlpha: hoverBorderAlpha

    readonly property int normalBorderWidth: 1
    readonly property int hoverBorderWidth: 1
    readonly property int selectedBorderWidth: 0
    readonly property int focusBorderWidth: 1

    function normalFillFor(foreground, accent, urgent) {
        return Util.alpha(foreground, normalFillAlpha);
    }
    function hoverFillFor(foreground, accent, urgent) {
        return Util.alpha(foreground, hoverFillAlpha);
    }
    function selectedFillFor(foreground, accent, urgent) {
        return Util.alpha(foreground, selectedFillAlpha);
    }
    // Omarchy resolves these through a configurable role token. qsbar has one
    // flat palette and no such setting, so a state resolves to the foreground
    // it was handed, which is the default those tokens carry anyway.
    function normalStateColor(foreground, accent, urgent) {
        return foreground;
    }
    function focusStateColor(foreground, accent, urgent) {
        return accent || foreground;
    }
    function hoverStateColor(foreground, accent, urgent) {
        return foreground;
    }
    function selectedStateColor(foreground, accent, urgent) {
        return foreground;
    }
    function selectionFillFor(foreground, accent, urgent) {
        return Util.alpha(foreground, selectionFillAlpha);
    }
    function pressedFillFor(foreground, accent, urgent) {
        return Util.alpha(foreground, pressedFillAlpha);
    }
    function focusFillFor(foreground, accent, urgent) {
        return Util.alpha(foreground, focusFillAlpha);
    }
    function normalBorderFor(foreground, accent, urgent) {
        return Util.alpha(foreground, normalBorderAlpha);
    }
    function hoverBorderFor(foreground, accent, urgent) {
        return Util.alpha(foreground, hoverBorderAlpha);
    }
    function selectedBorderFor(foreground, accent, urgent) {
        return Util.alpha(foreground, selectedBorderAlpha);
    }

    readonly property color normalFill: normalFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color hoverFill: hoverFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color selectedFill: selectedFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color pressedFill: pressedFillFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color normalBorderColor: normalBorderFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color hoverBorderColor: hoverBorderFor(Color.foreground, Color.accent, Color.urgent)
    readonly property color selectedBorderColor: selectedBorderFor(Color.foreground, Color.accent, Color.urgent)

    function controlFill(focused, hot, foreground, accent) {
        if (focused)
            return selectedFillFor(foreground, accent, foreground);
        if (hot)
            return hoverFillFor(foreground, accent, foreground);
        return normalFillFor(foreground, accent, foreground);
    }

    function controlBorder(focused, hot, foreground, accent) {
        if (focused)
            return selectedBorderFor(foreground, accent, foreground);
        if (hot)
            return hoverBorderFor(foreground, accent, foreground);
        return normalBorderFor(foreground, accent, foreground);
    }

    function controlBorderWidth(focused, hot) {
        if (focused)
            return selectedBorderWidth;
        if (hot)
            return hoverBorderWidth;
        return normalBorderWidth;
    }
}
