import QtQuick
import qs.Commons

// A clickable label sized to the bar. Omarchy widgets build their whole
// visible surface out of these, so the property names have to match.
Item {
    id: root

    property var bar: null
    property string text: ""
    property string fontFamily: bar ? bar.fontFamily : Style.font.family
    property real fontSize: Style.font.body
    property color foreground: bar ? bar.barForeground : Color.foreground
    property color activeColor: bar ? bar.urgent : Color.urgent
    property bool active: false
    property real horizontalMargin: 8.5
    property real verticalPadding: 6
    property real fixedWidth: -1
    property real fixedHeight: -1
    property real textRotation: 0
    property bool keepSpace: false
    property bool dimmed: false
    property bool concealed: false
    property bool interactive: true
    property bool pressable: true
    property bool useActiveColor: true
    property bool labelVisible: true
    property bool hasVisualContent: text !== ""
    property string tooltipText: ""

    signal pressed(int button)
    signal wheelMoved(int delta)

    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
    readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)
    readonly property real scaledVerticalPadding: Style.spaceReal(verticalPadding)
    readonly property real labelWidth: label.visible ? label.implicitWidth : 0

    function triggerPress(button) {
        if (root.bar)
            root.bar.hideTooltip(root);
        root.pressed(button);
    }

    visible: hasVisualContent || keepSpace
    opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
    implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? barSize : Math.max(12, label.implicitWidth + scaledHorizontalMargin * 2))
    implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? Math.max(12, label.implicitHeight + scaledVerticalPadding * 2) : barSize)

    onVisibleChanged: if (!visible && bar)
        bar.hideTooltip(root)

    Behavior on opacity {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    Text {
        id: label
        visible: root.labelVisible
        anchors.centerIn: parent
        text: root.text
        color: root.active && root.useActiveColor ? root.activeColor : root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        renderType: Text.NativeRendering
        rotation: root.textRotation
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: if (root.bar)
            root.bar.showTooltip(root, root.tooltipText)
        onExited: if (root.bar)
            root.bar.hideTooltip(root)
        onClicked: mouse => {
            if (root.pressable)
                root.triggerPress(mouse.button);
        }
        onWheel: wheel => root.wheelMoved(wheel.angleDelta.y)
    }
}
