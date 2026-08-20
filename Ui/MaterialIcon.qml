import QtQuick
import qs.Commons

// A Material Symbols Rounded glyph, addressed by name the way DMS addresses
// them: `name: "battery_5_bar"`, not a codepoint. The font maps those names
// through ligatures, so the text really is the icon's name.
//
// The drop-in counterpart to BarIcon: same `size`/`color` contract, so a
// call site swaps one for the other by changing `iconSource:` to `name:`.
// BarIcon asks the icon theme for a file and tints it; this draws a glyph
// from the font qsbar ships, which is why it can never come up empty.
//
// FILL, GRAD, opsz and wght are the font's variable axes. `filled` picks the
// solid cut of an icon and is what a "this is on" state uses. GRAD leans the
// strokes slightly heavier on a dark background, where thin strokes read as
// thinner than they measure.
Item {
    id: root

    property string name: ""
    property real size: Style.font.icon
    property color color: Color.foreground
    property bool filled: false

    property real fill: filled ? 1.0 : 0.0
    property int weight: filled ? 500 : 400
    property int grade: Color.background.hslLightness > 0.5 ? 0 : -25

    implicitWidth: Math.round(size)
    implicitHeight: Math.round(size)

    Text {
        anchors.fill: parent
        text: root.name
        color: root.color
        font.family: Style.font.symbolFamily
        font.pixelSize: Math.round(root.size)
        font.weight: root.weight
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({
                "FILL": root.fill.toFixed(2),
                "GRAD": root.grade,
                "opsz": 24,
                "wght": root.weight
            })
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }

    // A weight and fill change is a state change, so it animates rather than
    // snapping -- the same 100ms the tiles use for their fill.
    Behavior on fill {
        NumberAnimation {
            duration: 100
        }
    }
}
