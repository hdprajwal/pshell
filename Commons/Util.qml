pragma Singleton

import QtQuick
import Quickshell

// Pure helpers. No state. Names and behaviour match Omarchy's qs.Commons.Util
// so widgets written for Omarchy resolve their imports here unchanged.
QtObject {
    id: root

    function clamp(value, min, max) {
        const n = Number(value);
        if (!isFinite(n))
            return min;
        return Math.max(min, Math.min(max, n));
    }

    function clampAlpha(value) {
        return clamp(value, 0, 1);
    }

    // One wheel notch is one step. Touchpads send smaller deltas, so the
    // remainder carries over to the next event.
    function wheelSteps(accumulator, delta) {
        delta = Math.max(-120, Math.min(120, delta));
        if (accumulator * delta < 0)
            accumulator = 0;
        const total = accumulator + delta;
        const steps = total < 0 ? Math.ceil(total / 120) : Math.floor(total / 120);
        return {
            steps: steps,
            remainder: total - steps * 120
        };
    }

    function alpha(c, opacity) {
        const a = clampAlpha(opacity);
        if (!c)
            return Qt.rgba(0, 0, 0, a);
        if (typeof c === "string")
            c = Qt.color(c);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function fileUrl(path) {
        if (!path)
            return "";
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function shellQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\\''") + "'";
    }

    function execDetached(command) {
        Quickshell.execDetached(["bash", "-lc", command]);
    }

    // The text-editing keys every searchable panel's filter shares:
    //   Backspace       delete the previous character
    //   Ctrl+Backspace  delete the previous word
    //   Ctrl+U          clear the field
    // True only when the key would actually change the text, so an empty
    // filter never swallows it and a panel's own empty-filter fallback (menu
    // back-navigation, say) still gets its turn.
    function editsFilter(event, text) {
        if (!text)
            return false;
        // Alt and Meta sequences belong to other shortcuts.
        if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
            return false;
        // Ctrl+U alone; Ctrl+Shift+U is Unicode input.
        if (event.key === Qt.Key_U)
            return event.modifiers === Qt.ControlModifier;
        return event.key === Qt.Key_Backspace;
    }

    // The filter text after applying one of those keys. Assumes
    // editsFilter(event, text) already said yes.
    function editedFilter(event, text) {
        if (event.key === Qt.Key_U)
            return "";
        if (event.modifiers & Qt.ControlModifier)
            return text.replace(/\s+$/, "").replace(/\S+$/, "");
        return text.slice(0, -1);
    }

    function isPlainObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function canonicalWidgetId(id) {
        return String(id || "");
    }

    function decodeBase64(value) {
        const s = String(value || "");
        if (!s)
            return "";
        try {
            return Qt.atob(s);
        } catch (e) {
            return "";
        }
    }

    function cloneJson(value) {
        return JSON.parse(JSON.stringify(value === undefined ? null : value));
    }

    // Waybar-style output. Takes the last line so a chatty command still works.
    function parseModuleJson(raw) {
        const text = String(raw || "").trim();
        if (!text)
            return {};
        const lines = text.split("\n");
        try {
            return JSON.parse(lines[lines.length - 1]);
        } catch (e) {
            return {
                text: text
            };
        }
    }

    function normalizeLayoutEntry(entry) {
        if (typeof entry === "string")
            return {
                id: canonicalWidgetId(entry)
            };
        if (isPlainObject(entry) && entry.id) {
            const copy = cloneJson(entry);
            copy.id = canonicalWidgetId(copy.id);
            return copy;
        }
        return null;
    }

    function normalizeLayoutSection(list) {
        if (!Array.isArray(list))
            return [];
        const out = [];
        for (var i = 0; i < list.length; i++) {
            const e = normalizeLayoutEntry(list[i]);
            if (e)
                out.push(e);
        }
        return out;
    }

    function normalizeLayout(layout) {
        const src = isPlainObject(layout) ? layout : {};
        return {
            left: normalizeLayoutSection(src.left),
            center: normalizeLayoutSection(src.center),
            right: normalizeLayoutSection(src.right)
        };
    }
}
