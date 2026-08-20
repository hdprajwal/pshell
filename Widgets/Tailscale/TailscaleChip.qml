import QtQuick
import qs.Commons
import qs.Ui

// A filter chip with its count. Selected uses Button's own selected fill and
// checkmark, the same treatment any other chosen option gets in a panel, so
// this reads as one kind of control rather than a bespoke pill.
Button {
    id: root

    property string label: ""
    property int count: 0

    signal picked

    text: root.label + " (" + root.count + ")"
    iconText: root.selected ? "✓" : ""
    foreground: Color.popups.text
    radius: height / 2
    onClicked: root.picked()
}
