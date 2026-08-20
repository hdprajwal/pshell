import QtQuick

// Output or input device picker. `input` switches which list is shown.
Column {
    id: root

    property int rowWidth: 260
    property bool input: false

    readonly property var devices: input ? Audio.sources : Audio.sinks
    readonly property var current: input ? Audio.source : Audio.sink

    spacing: 1

    Repeater {
        model: root.devices

        Rectangle {
            id: devRow

            required property var modelData
            readonly property bool selected: root.current === modelData

            width: root.rowWidth
            height: Math.round(Config.fontSize * 2.4)
            radius: 4
            color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                text: devRow.modelData.description || devRow.modelData.nickname || devRow.modelData.name
                color: devRow.selected ? Config.accent : Config.fg
                opacity: devRow.selected ? 1 : 0.8
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: devRow.selected
                text: "✓"
                color: Config.accent
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.input)
                        Audio.setSource(devRow.modelData);
                    else
                        Audio.setSink(devRow.modelData);
                }
            }
        }
    }
}
