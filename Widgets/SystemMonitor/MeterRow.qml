import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One reading in the system monitor's panel: symbol, name, value, and a
// meter under them, in the accent colour until the reading is in danger.
// `detail` is the muted line under the meter -- "6.8 GiB of 31.2 GiB".
Column {
    id: root

    property string icon: ""
    property string title: ""
    property string value: ""
    property string detail: ""
    // 0..100, or below zero for no reading, which draws an empty track.
    property real percent: -1
    property int level: 0
    // Off for a reading with no ceiling to measure against: the network.
    property bool meter: true

    readonly property color ink: level >= 2 ? Commons.Color.urgent : Commons.Color.popups.text

    width: parent ? parent.width : implicitWidth
    spacing: Style.spacing.xs

    Item {
        width: parent.width
        height: Math.max(glyph.implicitHeight, reading.implicitHeight)

        MaterialIcon {
            id: glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: Style.font.icon
            color: root.level >= 1 ? (root.level >= 2 ? Commons.Color.urgent : Commons.Color.accent) : Commons.Color.muted
        }

        Text {
            anchors.left: glyph.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: reading.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
        }

        Text {
            id: reading
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.features: ({
                    "tnum": 1
                })
        }
    }

    Rectangle {
        id: track
        visible: root.meter
        width: parent.width
        height: Math.max(2, Style.space(5))
        radius: height / 2
        color: Style.normalFill

        Rectangle {
            width: Math.round(track.width * Math.max(0, Math.min(100, root.percent)) / 100)
            height: parent.height
            radius: parent.radius
            color: root.level >= 2 ? Commons.Color.urgent : Commons.Color.accent

            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Text {
        visible: root.detail !== ""
        width: parent.width
        text: root.detail
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
    }
}
