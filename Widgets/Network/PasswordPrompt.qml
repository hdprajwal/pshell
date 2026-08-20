import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Services

// Password entry for a secured network qsbar has no saved secret for.
//
// Two things make this different from Popout. It needs real keyboard focus,
// which layer surfaces only get when they ask, and it is centred rather than
// anchored to a widget. Everything else stays deliberately similar.
PanelWindow {
    id: prompt

    property var network: null
    property string ssid: ""

    signal accepted(string password)

    property string message: ""

    function open(target, why) {
        prompt.network = target;
        prompt.message = why || "";
        prompt.ssid = target ? target.name : "";
        field.text = "";
        field.echoMode = TextInput.Password;
        prompt.visible = true;
        Qt.callLater(() => field.forceActiveFocus());
    }

    function close() {
        prompt.visible = false;
        prompt.network = null;
        field.text = "";
    }

    function submit() {
        if (field.text === "")
            return;
        prompt.accepted(field.text);
        prompt.close();
    }

    visible: false
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qsbar:password"
    WlrLayershell.layer: WlrLayer.Top
    // Exclusive so keystrokes reach the field rather than whatever was
    // focused before. Without this the window renders but cannot be typed in.
    WlrLayershell.keyboardFocus: prompt.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)

        MouseArea {
            anchors.fill: parent
            onClicked: prompt.close()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 360
        height: card.implicitHeight + 32
        radius: Config.cornerRadius > 0 ? Config.cornerRadius : 8
        color: Config.bg
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.15)

        // Swallow clicks so they do not reach the backdrop and cancel.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: card
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 12

            Text {
                width: parent.width
                text: "Connect to " + prompt.ssid
                color: Config.fg
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 1.2)
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: prompt.message !== ""
                text: prompt.message + ". The saved password may be wrong."
                color: Config.urgent
                wrapMode: Text.WordWrap
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 0.9)
            }

            Rectangle {
                width: parent.width
                height: Math.round(Config.fontSize * 2.6)
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.07)
                border.width: field.activeFocus ? 1 : 0
                border.color: Config.accent

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    color: Config.fg
                    font.family: Config.fontFamily
                    font.pixelSize: Config.fontSize
                    echoMode: TextInput.Password
                    selectByMouse: true
                    selectionColor: Config.accent
                    clip: true

                    Keys.onEscapePressed: prompt.close()
                    onAccepted: prompt.submit()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: "Password"
                        color: Config.fg
                        opacity: 0.4
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Config.fontSize * 1.9)
                    height: width
                    radius: 4
                    color: revealHover.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                    BarIcon {
                        anchors.centerIn: parent
                        iconSource: Icons.first(field.echoMode === TextInput.Password ? ["view-conceal-symbolic", "view-private-symbolic", "view-hidden-symbolic"] : ["view-reveal-symbolic", "view-visible-symbolic"])
                        size: Math.round(Config.fontSize * 1.1)
                        opacity: 0.7
                    }

                    MouseArea {
                        id: revealHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: field.echoMode = field.echoMode === TextInput.Password ? TextInput.Normal : TextInput.Password
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Rectangle {
                    width: Math.round(Config.fontSize * 6)
                    height: Math.round(Config.fontSize * 2.4)
                    radius: 6
                    color: cancelHover.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Config.fg
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }

                    MouseArea {
                        id: cancelHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: prompt.close()
                    }
                }

                Rectangle {
                    width: Math.round(Config.fontSize * 6)
                    height: Math.round(Config.fontSize * 2.4)
                    radius: 6
                    opacity: field.text === "" ? 0.4 : 1
                    color: Config.fg

                    Text {
                        anchors.centerIn: parent
                        text: "Connect"
                        color: Config.bg
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: prompt.submit()
                    }
                }
            }
        }
    }
}
