import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Services

// A titled group of setting rows on one filled card.
//
// `help` is a tooltip on a small info mark beside the title, not a paragraph
// under it. The pages read as forms, not documentation -- the README is the
// documentation -- and a sentence above every card was most of what made
// them feel long. Keep it to one short sentence: a tooltip does not wrap.
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
  // Optional Material Symbol name before the title. Drawn at the info mark's
  // size and in the same muted tone, so it labels the section without
  // outweighing the caption beside it.
  property string icon: ""

  default property alias rows: body.children

  width: parent ? parent.width : 0
  spacing: Style.spacing.md

  Row {
    visible: section.title !== "" || section.help !== ""
    spacing: Style.spacing.sm

    MaterialIcon {
      anchors.verticalCenter: parent.verticalCenter
      visible: section.icon !== ""
      name: section.icon
      size: Math.round(header.font.pixelSize * 1.2)
      color: Commons.Color.muted
    }

    PanelSectionHeader {
      id: header
      anchors.verticalCenter: parent.verticalCenter
      visible: section.title !== ""
      text: section.title
    }

    // Sized from the header's type, so the mark sits on the title's line
    // rather than pushing the card down; muted, so it reads as an aside.
    MaterialIcon {
      id: infoIcon
      anchors.verticalCenter: parent.verticalCenter
      visible: section.help !== ""
      name: Glyphs.info
      size: Math.round(header.font.pixelSize * 1.2)
      color: infoHover.hovered ? Commons.Color.foreground : Commons.Color.muted

      HoverHandler {
        id: infoHover
      }

      PanelToolTip {
        visible: infoHover.hovered
        text: section.help
      }
    }
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
