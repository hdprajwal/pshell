import QtQuick
import Quickshell
import qs.Commons

// A titled group of FormRows on one filled card.
//
// `rows` is a default property alias into the inner Column, which works
// because a default alias only captures children a *consumer* declares --
// the header and the card below are declared in this file and stay where
// they are written. Verified on Qt 6 rather than assumed, because getting it
// backwards nests the header inside its own card and the mistake looks like
// a layout bug rather than a scoping one.
Column {
  id: section

  property string title: ""
  property string help: ""

  default property alias rows: body.children

  width: parent ? parent.width : 0
  spacing: Style.spacing.md

  PanelSectionHeader {
    visible: section.title !== ""
    text: section.title
  }

  Text {
    width: parent.width
    visible: section.help !== ""
    text: section.help
    color: Color.muted
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  BorderSurface {
    width: parent.width
    height: body.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    // A fill and no outline, the same choice the control centre's tiles
    // make: a page of forty outlined boxes reads as a grid of frames rather
    // than a list of things you can change.
    color: Style.normalFill
    borderSpec: Border.none()

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.spacing.lg
      anchors.rightMargin: Style.spacing.lg
      anchors.topMargin: Style.spacing.md
      spacing: 0
    }
  }
}
