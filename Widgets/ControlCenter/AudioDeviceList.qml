import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Output or input device picker. `input` switches which list is shown.
// Under the outputs sits the mixer, a slider for each app playing; under the
// inputs, what is recording.
//
// The active device is drawn as an outlined card rather than just tinted
// text, so it stays obvious which one you are listening through when the
// list is long.
Column {
    id: root

    property QtObject bar: null
    property int rowWidth: 260
    property bool input: false
    property string settingsCommand: ""

    signal runRequested(string command)

    readonly property var current: input ? Audio.source : Audio.sink

    // Pinned devices float to the top so a headset you keep switching back
    // to does not sink under everything Pipewire happens to enumerate.
    readonly property var devices: {
        const all = (input ? Audio.sources : Audio.sinks).slice();
        all.sort((a, b) => {
            const pa = Prefs.isPinned(a.name, root.input);
            const pb = Prefs.isPinned(b.name, root.input);
            if (pa !== pb)
                return pa ? -1 : 1;
            return String(a.description || a.name).localeCompare(String(b.description || b.name));
        });
        return all;
    }

    // What is recording, so you can see who has the microphone. The output
    // side's apps are Audio.streams, which the mixer below draws.
    readonly property var recordings: root.input ? Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio) : []

    spacing: 8

    Item {
        width: root.rowWidth
        height: Math.round(Style.font.body * 1.8)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.input ? "Input Devices" : "Audio Devices"
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.body * 1.25)
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Style.font.body * 1.9)
            height: width
            radius: 4
            visible: root.settingsCommand !== ""
            color: gearHover.containsMouse ? Style.selectedFill : "transparent"

            MaterialIcon {
                anchors.centerIn: parent
                name: Glyphs.settings
                size: Math.round(Style.font.body * 1.1)
                color: Commons.Color.foreground
                opacity: 0.7
            }

            MouseArea {
                id: gearHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runRequested(root.settingsCommand)
            }
        }
    }

    Item {
        width: root.rowWidth
        visible: root.input
        height: micSlider.implicitHeight

        MaterialIcon {
            id: micIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: Glyphs.microphone(Audio.micMuted)
            size: Math.round(Style.font.body * 1.4)
            color: Commons.Color.foreground
            opacity: Audio.micMuted ? 0.45 : 1
        }

        PanelSlider {
            id: micSlider
            bar: root.bar
            anchors.left: micIcon.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 1
            step: 0.05
            value: Audio.micVolume
            opacity: Audio.micMuted ? 0.45 : 1
            onMoved: v => Audio.setMicVolume(v)
            onRightClicked: Audio.toggleMicMute()
        }
    }

    Column {
        spacing: 6

        Repeater {
            model: root.devices

            Rectangle {
                id: devRow

                required property var modelData
                readonly property bool selected: root.current === modelData
                readonly property bool pinned: Prefs.isPinned(modelData.name, root.input)

                width: root.rowWidth
                height: Math.round(Style.font.body * 3.4)
                radius: 8
                color: hover.containsMouse && !selected ? Style.hoverFill : "transparent"
                border.width: selected ? 1 : 0
                border.color: Util.alpha(Commons.Color.foreground, 0.45)

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

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Pipewire says what a device actually is -- a headset,
                    // a monitor over HDMI -- so the row shows that rather
                    // than one speaker icon for everything.
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.input ? Glyphs.source(devRow.modelData) : Glyphs.sink(devRow.modelData)
                        size: Math.round(Style.font.body * 1.2)
                        color: Commons.Color.foreground
                        opacity: 0.85
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            // A Bluetooth headset names itself, and that name becomes the
                            // sink's description: shown as typed, never as markup.
                            textFormat: Text.PlainText
                            text: devRow.modelData.description || devRow.modelData.nickname || devRow.modelData.name
                            color: Commons.Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            width: root.rowWidth - 130
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: devRow.selected
                            text: "Active"
                            color: Commons.Color.foreground
                            opacity: 0.55
                            font.family: Style.font.family
                            font.pixelSize: Math.round(Style.font.body * 0.85)
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: pinRow.implicitWidth + 14
                    height: Math.round(Style.font.body * 1.9)
                    radius: height / 2
                    color: devRow.pinned ? Style.selectedFill : (pinHover.containsMouse ? Style.selectedFill : Style.normalFill)

                    Row {
                        id: pinRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: Glyphs.pin
                            filled: devRow.pinned
                            size: Math.round(Style.font.body * 0.95)
                            color: Commons.Color.foreground
                            opacity: devRow.pinned ? 1 : 0.7
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: devRow.pinned ? "Pinned" : "Pin"
                            color: Commons.Color.foreground
                            opacity: devRow.pinned ? 1 : 0.7
                            font.family: Style.font.family
                            font.pixelSize: Math.round(Style.font.body * 0.85)
                        }
                    }

                    MouseArea {
                        id: pinHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Prefs.togglePin(devRow.modelData.name, root.input)
                    }
                }
            }
        }
    }

    Text {
        visible: root.input
        text: "Recording"
        color: Commons.Color.foreground
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.body * 0.9)
    }

    Text {
        visible: root.input && root.recordings.length === 0
        text: "Nothing recording"
        color: Commons.Color.foreground
        opacity: 0.35
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.body * 0.85)
    }

    Column {
        visible: root.input
        spacing: 4

        Repeater {
            model: root.recordings

            Item {
                required property var modelData

                width: root.rowWidth
                height: Math.round(Style.font.body * 2.2)

                PwObjectTracker {
                    objects: [parent.modelData]
                }

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: parent.modelData.description || parent.modelData.name
                    color: Commons.Color.foreground
                    opacity: 0.8
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 0.9)
                    width: root.rowWidth - 60
                    elide: Text.ElideRight
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.audio ? Math.round(parent.modelData.audio.volume * 100) + "%" : ""
                    color: Commons.Color.foreground
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 0.85)
                }
            }
        }
    }

    // The mixer. Gone, caption and all, while nothing is playing: an empty
    // section is a heading over nothing. Shown from root.input and the
    // service's list, never from a child's visibility, so the detail pane's
    // height stays an input rather than something this sets.
    Column {
        visible: !root.input && Audio.streams.length > 0
        width: root.rowWidth
        spacing: Style.spacing.md

        PanelSectionHeader {
            text: "Apps"
        }

        Repeater {
            model: root.input ? [] : Audio.streams

            Item {
                id: appRow

                required property var modelData
                readonly property bool muted: modelData.audio ? modelData.audio.muted : false
                readonly property real volume: modelData.audio ? modelData.audio.volume : 0
                readonly property string iconSource: Audio.streamIcon(modelData)
                readonly property int iconSize: Math.round(Style.font.body * 1.6)

                width: root.rowWidth
                height: appName.implicitHeight + appSlider.implicitHeight

                // A plain Image, as ActiveWindow has it: an app logo is not
                // tinted to the foreground like a symbolic icon.
                Image {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: appRow.iconSize
                    height: appRow.iconSize
                    visible: appRow.iconSource !== ""
                    source: appRow.iconSource
                    sourceSize.width: appRow.iconSize
                    sourceSize.height: appRow.iconSize
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    opacity: appRow.muted ? 0.45 : 1
                }

                MaterialIcon {
                    anchors.centerIn: appIcon
                    visible: appRow.iconSource === ""
                    name: Glyphs.audioApp
                    size: Math.round(Style.font.body * 1.2)
                    color: Commons.Color.foreground
                    opacity: appRow.muted ? 0.45 : 0.85
                }

                Text {
                    id: appName
                    anchors.left: appIcon.right
                    anchors.leftMargin: Style.spacing.lg
                    anchors.right: muteButton.left
                    anchors.rightMargin: Style.spacing.md
                    anchors.top: parent.top
                    text: Audio.streamName(appRow.modelData)
                    color: Commons.Color.foreground
                    opacity: appRow.muted ? 0.45 : 0.8
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 0.9)
                    elide: Text.ElideRight
                }

                PanelSlider {
                    id: appSlider
                    bar: root.bar
                    anchors.left: appName.left
                    anchors.right: appName.right
                    anchors.top: appName.bottom
                    minimum: 0
                    maximum: 1
                    step: 0.05
                    value: appRow.volume
                    opacity: appRow.muted ? 0.45 : 1
                    onMoved: v => Audio.setStreamVolume(appRow.modelData, v)
                    onRightClicked: Audio.toggleStreamMute(appRow.modelData)
                }

                Rectangle {
                    id: muteButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Style.font.body * 1.9)
                    height: width
                    radius: Style.cornerRadius
                    color: muteHover.containsMouse ? Style.selectedFill : (appRow.muted ? Style.normalFill : "transparent")

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: Glyphs.volume(appRow.muted, appRow.volume)
                        size: Math.round(Style.font.body * 1.1)
                        color: Commons.Color.foreground
                        opacity: appRow.muted ? 0.45 : 0.7
                    }

                    MouseArea {
                        id: muteHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleStreamMute(appRow.modelData)
                    }
                }
            }
        }
    }
}
