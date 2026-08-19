import QtQuick
import qs.Commons

// A WidgetButton that draws a glyph at icon size instead of body text.
WidgetButton {
    id: root

    property string icon: ""

    text: icon
    fontSize: Style.bar.iconFont
    horizontalMargin: 6
    fixedWidth: vertical ? barSize : Style.bar.iconSlot
}
