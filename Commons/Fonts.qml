pragma Singleton

import QtQuick
import Quickshell

// Fonts qsbar ships with itself, as opposed to the ones it asks fontconfig
// for. Only one so far: Material Symbols Rounded, the icon set DMS draws
// with, vendored under assets/ so a themed icon set is never a prerequisite
// for the shell looking right.
//
// A FontLoader registers the family with Qt for this process only, so the
// font does not have to be installed and nothing outside qsbar sees it. If
// the load fails the family name is still the right answer: a user who has
// ttf-material-symbols-variable installed system-wide gets it from there.
Singleton {
    id: root

    readonly property string symbols: symbolsFont.name || "Material Symbols Rounded"
    readonly property bool symbolsReady: symbolsFont.status === FontLoader.Ready

    FontLoader {
        id: symbolsFont
        source: Qt.resolvedUrl("../assets/fonts/material-symbols/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf")
    }
}
