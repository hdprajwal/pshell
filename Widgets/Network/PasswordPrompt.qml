import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Services
import qs.Commons

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
        radius: Style.cornerRadius
        color: Color.background
        border.width: 1
        border.color: Color.popups.border

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
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 1.2)
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: prompt.message !== ""
                text: prompt.message + ". The saved password may be wrong."
                color: Color.urgent
                wrapMode: Text.WordWrap
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.9)
            }

            Rectangle {
                width: parent.width
                height: Math.round(Style.font.body * 2.6)
                radius: 6
                color: Util.alpha(Color.foreground, 0.07)
                border.width: field.activeFocus ? 1 : 0
                border.color: Color.accent

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    echoMode: TextInput.Password
                    selectByMouse: true
                    selectionColor: Color.accent
                    clip: true

                    Keys.onEscapePressed: prompt.close()
                    onAccepted: prompt.submit()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: "Password"
                        color: Color.foreground
                        opacity: 0.4
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Style.font.body * 1.9)
                    height: width
                    radius: 4
                    color: revealHover.containsMouse ? Style.selectedFill : "transparent"

                    BarIcon {
                        anchors.centerIn: parent
                        iconSource: Icons.first(field.echoMode === TextInput.Password ? ["view-conceal-symbolic", "view-private-symbolic", "view-hidden-symbolic"] : ["view-reveal-symbolic", "view-visible-symbolic"])
                        size: Math.round(Style.font.body * 1.1)
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
                    width: Math.round(Style.font.body * 6)
                    height: Math.round(Style.font.body * 2.4)
                    radius: 6
                    color: cancelHover.containsMouse ? Style.selectedFill : Style.normalFill

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
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
                    width: Math.round(Style.font.body * 6)
                    height: Math.round(Style.font.body * 2.4)
                    radius: 6
                    opacity: field.text === "" ? 0.4 : 1
                    color: Color.foreground

                    Text {
                        anchors.centerIn: parent
                        text: "Connect"
                        color: Color.background
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
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
