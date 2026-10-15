import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A square glyph key: the password field's reveal and submit, and the media
// row's transport. Flat -- a fill under the pointer, a solid fill when `lit`,
// never an outline -- so it reads as part of the card it sits in rather
// than as a form control dropped on top of it.
Rectangle {
    id: key

    property string glyph: ""
    property bool lit: false
    property bool filledGlyph: false
    // Accent for the field's submit key, the text colour for the media
    // row's play key: one says "go", the other only "this is on".
    property color litColor: Commons.Color.lock.borderActive
    property real glyphSize: Style.font.icon

    signal clicked

    radius: Style.cornerRadius
    opacity: key.enabled ? 1 : 0.4
    color: key.lit ? key.litColor : (hover.containsMouse && key.enabled ? Util.alpha(Commons.Color.lock.text, 0.12) : "transparent")

    Behavior on color {
        ColorAnimation {
            duration: 100
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        name: key.glyph
        filled: key.filledGlyph
        size: key.glyphSize
        color: key.lit ? Commons.Color.background : Commons.Color.lock.text
    }

    MouseArea {
        id: hover

        anchors.fill: parent
        hoverEnabled: true
        enabled: key.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: key.clicked()
    }
}
