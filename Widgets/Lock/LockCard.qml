import QtQuick
import qs.Commons
import qs.Commons as Commons

// The lock's one-line card: the field's fill and corners, with its children
// laid out in a row. The notification count and the app chips are made of
// these.
Rectangle {
    id: card

    default property alias content: inner.data

    implicitWidth: inner.implicitWidth + Style.spacing.huge * 2
    implicitHeight: Math.round(Style.font.body * 3)
    radius: Style.cornerRadius
    color: Commons.Color.lock.background

    Row {
        id: inner

        anchors.centerIn: parent
        spacing: Style.spacing.md
    }
}
