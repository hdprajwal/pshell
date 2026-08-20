import QtQuick
import Quickshell
import qs.Commons

WidgetButton {
  id: root

  property Component iconComponent: null

  // A bar entry is one or more icons and an optional label, laid out in a
  // single centred row whose width the slot follows. Omarchy's version fits
  // exactly one glyph in a square canvas, so anything else -- the control
  // centre's three status icons, the battery's percentage -- had to compute
  // its own slot width and remember to widen the canvas with it. Several
  // widgets got that subtly wrong in different directions.
  //
  // `iconSources` is several themed icons side by side. `iconSource` is the
  // single-icon case. `iconNames`/`iconName` are the same two cases in
  // Material Symbols, named rather than looked up in the icon theme. `text`
  // stays the Nerd Font glyph, as Omarchy means it, drawn through the same
  // optically-centred canvas. `label` is trailing text. `iconComponent`
  // still takes anything none of these covers.
  property var iconSources: []
  property string iconSource: ""
  property var iconNames: []
  property string iconName: ""
  property string label: ""

  property real slotSize: Style.bar.iconSlot
  property real opticalSize: Style.bar.iconCanvas
  // The breathing room an icon-only slot already carries, kept so a wide
  // widget sits the same distance from its neighbour as a narrow one.
  readonly property real slotPadding: Style.bar.iconSlot - Style.bar.iconCanvas

  readonly property bool usingImages: iconSources.length > 0 || iconSource !== ""
  readonly property bool usingSymbols: iconNames.length > 0 || iconName !== ""
  readonly property bool usingCanvas: iconComponent !== null || (!usingImages && !usingSymbols && text !== "")
  property color iconColor: active && useActiveColor ? activeColor : foreground

  property bool debugOpticalBounds: Quickshell.env("OMARCHY_DEBUG_BAR_ICONS") === "1"
  readonly property real opticalCenterErrorX: glyph.visible ? glyph.paintedCenterX - opticalCanvas.width / 2 : 0
  readonly property real glyphPaintedWidth: glyph.visible ? glyph.tightWidth : 0
  readonly property real glyphBaselineY: glyph.visible ? glyph.baselineY : 0
  readonly property int glyphFontSize: glyph.visible ? glyph.renderedFontSize : 0

  labelVisible: false
  hasVisualContent: text !== "" || iconComponent !== null || usingImages || usingSymbols || label !== ""
  fontSize: Style.bar.iconFont
  fixedWidth: vertical ? -1 : Math.max(slotSize, content.implicitWidth + slotPadding)
  fixedHeight: vertical ? Math.max(slotSize, content.implicitHeight + slotPadding) : -1

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Repeater {
      model: root.iconSources

      BarIcon {
        required property string modelData

        anchors.verticalCenter: parent.verticalCenter
        iconSource: modelData
        size: root.opticalSize
        color: root.iconColor
      }
    }

    BarIcon {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.iconSources.length === 0 && root.iconSource !== ""
      iconSource: root.iconSource
      size: root.opticalSize
      color: root.iconColor
    }

    Repeater {
      model: root.iconNames

      MaterialIcon {
        required property string modelData

        anchors.verticalCenter: parent.verticalCenter
        name: modelData
        size: root.opticalSize
        color: root.iconColor
      }
    }

    MaterialIcon {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.iconNames.length === 0 && root.iconName !== ""
      name: root.iconName
      size: root.opticalSize
      color: root.iconColor
    }

    // The glyph keeps its square canvas: OpticalGlyph centres itself against
    // the canvas it is given, and BarIndicator reads that measurement back.
    Item {
      id: opticalCanvas
      anchors.verticalCenter: parent.verticalCenter
      visible: root.usingCanvas
      width: root.opticalSize
      height: root.opticalSize

      OpticalGlyph {
        id: glyph
        anchors.fill: parent
        visible: root.iconComponent === null
        text: root.text
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        color: root.iconColor
        rotation: root.textRotation
        debugBounds: root.debugOpticalBounds
      }

      Loader {
        anchors.fill: parent
        visible: root.iconComponent !== null
        sourceComponent: root.iconComponent
      }

      Rectangle {
        visible: root.debugOpticalBounds && root.iconComponent !== null
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: "#4488ff"
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.label !== ""
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }
  }

  Rectangle {
    visible: root.debugOpticalBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#ff4455"
  }
}
