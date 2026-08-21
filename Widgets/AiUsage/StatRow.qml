import QtQuick
import qs.Commons

// A named figure at the foot of a view: label on the left, number on the
// right. The panel's other rows are things you press; these are only read,
// so they carry no hover state.
Item {
    id: root

    property string label: ""
    property string value: ""
    property color valueColor: Color.popups.text

    width: parent ? parent.width : implicitWidth
    implicitWidth: name.implicitWidth + reading.implicitWidth + Style.spacing.xl
    implicitHeight: Math.max(name.implicitHeight, reading.implicitHeight)

    Text {
        id: name
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - reading.implicitWidth - Style.spacing.xl)
        text: root.label
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
    }

    Text {
        id: reading
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.valueColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }
}
