import QtQuick
import qs.Services
import qs.Commons
import qs.Ui

// A provider's brand mark, addressed by the id its record carries. The marks
// are shipped rather than looked up in the icon theme because no theme has
// them, and they keep their brand colour rather than being tinted to the
// foreground: a row of five identical grey shapes is not something you can
// read at a glance.
//
// The set is resolved up front from the ids we actually ship a file for, not
// from an Image that failed. A missing icon comes back Ready with a magenta
// placeholder rather than Error, so there is nothing to react to after the
// fact -- the same trap Services/Icons.qml documents.
Item {
    id: root

    property string providerId: ""
    property real size: Style.font.icon
    property color fallbackColor: Color.popups.text

    readonly property bool shipped: ["claude", "codex", "fireworks"].indexOf(String(providerId)) >= 0

    // Codex's mark is a monochrome glyph and ships in both cuts, so it
    // follows the palette the rest of the shell is drawn in. The other two
    // are coloured artwork and read on either.
    readonly property string markSource: {
        if (!shipped)
            return "";
        const name = providerId === "codex" && Config.mode === "light" ? "codex-light" : providerId;
        return Qt.resolvedUrl("assets/" + name + ".svg");
    }

    implicitWidth: Math.round(size)
    implicitHeight: Math.round(size)

    Image {
        anchors.fill: parent
        visible: root.shipped
        source: root.markSource
        // Rasterised at twice the drawn size so the mark stays crisp when the
        // font scale pushes it up.
        sourceSize.width: Math.round(root.size * 2)
        sourceSize.height: Math.round(root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }

    // A provider the updater learns about before qsbar has artwork for it
    // still gets a row rather than a hole.
    MaterialIcon {
        anchors.centerIn: parent
        visible: !root.shipped
        name: "smart_toy"
        size: root.size
        color: root.fallbackColor
    }
}
