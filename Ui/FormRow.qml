import QtQuick
import qs.Commons
import qs.Commons as Commons

// One setting on one line inside a FormSection: its name on the left, its
// control on the right. The same shape a Toggle already has, for the controls
// that are not a switch -- a number, a dropdown, a button group.
//
// It exists so a section with three one-control settings is one card of three
// lines rather than three cards with a heading each. Give the control no
// label of its own (NumberField's `label: ""`, Dropdown's `showLabel: false`);
// the row's label is the label.
//
// The slot is sized from childrenRect, not from a declared width, so the row
// takes whatever the control says it needs and right-aligns it.
Item {
  id: row

  property string label: ""

  default property alias control: slot.data

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labelText.implicitHeight, slot.height) + Style.spacing.md * 2

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.right: slot.left
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    color: Commons.Color.foreground
    elide: Text.ElideRight
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
