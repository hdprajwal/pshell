import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Components
import qs.Services
import qs.Commons

// Output or input device picker. `input` switches which list is shown.
//
// The active device is drawn as an outlined card rather than just tinted
// text, so it stays obvious which one you are listening through when the
// list is long.
Column {
    id: root

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

    // Application streams, so you can see what is actually making noise.
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink === !root.input && n.audio)

    spacing: 8

    Item {
        width: root.rowWidth
        height: Math.round(Style.font.body * 1.8)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.input ? "Input Devices" : "Audio Devices"
            color: Color.foreground
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

            BarIcon {
                anchors.centerIn: parent
                iconSource: Icons.first(["preferences-system-symbolic", "emblem-system-symbolic", "applications-system"])
                size: Math.round(Style.font.body * 1.1)
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

    Slider {
        width: root.rowWidth
        visible: root.input
        value: Audio.micVolume
        dimmed: Audio.micMuted
        iconSource: Icons.microphone(Audio.micMuted)
        onMoved: v => Audio.setMicVolume(v)
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
                border.color: Util.alpha(Color.foreground, 0.45)

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

                    BarIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: root.input ? Icons.microphone(false) : Icons.first(["audio-speakers-symbolic", "audio-volume-high-symbolic"])
                        size: Math.round(Style.font.body * 1.2)
                        opacity: 0.85
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: devRow.modelData.description || devRow.modelData.nickname || devRow.modelData.name
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            width: root.rowWidth - 130
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: devRow.selected
                            text: "Active"
                            color: Color.foreground
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

                        BarIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            iconSource: Icons.first(["pin-symbolic", "view-pin-symbolic", "gnome-panel-pin"])
                            size: Math.round(Style.font.body * 0.95)
                            opacity: devRow.pinned ? 1 : 0.7
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: devRow.pinned ? "Pinned" : "Pin"
                            color: Color.foreground
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
        text: root.input ? "Recording" : "Playback"
        color: Color.foreground
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.body * 0.9)
    }

    Text {
        visible: root.streams.length === 0
        text: root.input ? "Nothing recording" : "Nothing playing"
        color: Color.foreground
        opacity: 0.35
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.body * 0.85)
    }

    Column {
        spacing: 4

        Repeater {
            model: root.streams

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
                    text: parent.modelData.description || parent.modelData.name
                    color: Color.foreground
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
                    color: Color.foreground
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 0.85)
                }
            }
        }
    }
}
