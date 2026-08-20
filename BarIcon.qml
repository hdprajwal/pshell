import QtQuick
import Qt5Compat.GraphicalEffects

// A themed icon tinted to the foreground colour. Symbolic icons ship in a
// fixed dark colour, so they need recolouring to be visible on a dark bar.
Item {
    id: root

    property string iconSource: ""
    property int size: 16
    property color color: Config.fg

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image
        anchors.fill: parent
        source: root.iconSource
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 32
        sourceSize.height: 32
        smooth: true
    }

    ColorOverlay {
        anchors.fill: image
        source: image
        visible: root.iconSource !== ""
        color: root.color
    }
}
