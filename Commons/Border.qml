pragma Singleton

import QtQuick

// Border specs. Omarchy supports gradients and per-side widths; qsbar only
// does flat colors, so a spec is a color plus a width.
QtObject {
    id: root

    function flat(color, width) {
        return {
            color: color,
            width: Math.max(0, Number(width) || 0),
            gradient: null
        };
    }

    function none() {
        return flat("transparent", 0);
    }

    function isVisible(spec) {
        return !!spec && spec.width > 0 && String(spec.color) !== "transparent";
    }
}
