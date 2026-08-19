import QtQuick
import qs.Commons

// A small state dot or glyph. Hidden unless active, unless the widget asks
// for it to stay put.
WidgetButton {
    id: root

    property bool activeState: false
    property bool alwaysShow: false

    active: activeState
    hasVisualContent: text !== "" && (activeState || alwaysShow)
    keepSpace: alwaysShow
    fontSize: Style.bar.iconFont
    horizontalMargin: 4
}
