import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// Password entry for a secured network qsbar has no saved secret for.
//
// A KeyboardPanel gives this the same layer-shell focus priming every other
// panel gets (see the comment block at the top of Ui/KeyboardPanel.qml), so
// there is no bespoke WlrLayershell handling here. Opening it hands this
// popout the coordinator's single-popout slot, which is what closes the
// network panel underneath without this component asking it to.
Item {
    id: root

    property QtObject bar: null
    property Item anchorItem: null

    property var network: null
    property string ssid: ""
    property string message: ""

    signal accepted(string password)

    readonly property bool opened: keyboardPanel.open

    function open(target, why) {
        root.network = target;
        root.message = why || "";
        root.ssid = target ? target.name : "";
        field.text = "";
        field.password = true;
        keyboardPanel.open = true;
    }

    function close() {
        keyboardPanel.open = false;
        root.network = null;
        field.text = "";
    }

    function submit() {
        if (field.text === "")
            return;
        root.accepted(field.text);
        root.close();
    }

    KeyboardPanel {
        id: keyboardPanel
        anchorItem: root.anchorItem
        bar: root.bar
        owner: root
        centerOnBar: true
        focusTarget: field
        contentWidth: keyboardPanel.fittedContentWidth(Style.space(320))
        contentHeight: keyboardPanel.fittedContentHeight(card.implicitHeight)

        Column {
            id: card
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.spacing.md

            Text {
                width: parent.width
                text: "Connect to " + root.ssid
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.message !== ""
                text: root.message + ". The saved password may be wrong."
                color: Color.urgent
                wrapMode: Text.WordWrap
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }

            Item {
                width: parent.width
                implicitHeight: field.implicitHeight

                TextField {
                    id: field
                    anchors.fill: parent
                    password: true
                    placeholderText: "Password"
                    rightPadding: horizontalPadding + reveal.width + Style.spacing.xs

                    Keys.onEscapePressed: root.close()
                    onAccepted: root.submit()
                }

                Item {
                    id: reveal
                    width: Math.round(Style.font.body * 1.9)
                    height: width
                    anchors.right: field.right
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: field.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: revealHover.containsMouse ? Style.hoverFill : "transparent"
                    }

                    BarIcon {
                        anchors.centerIn: parent
                        iconSource: Icons.first(field.password ? ["view-conceal-symbolic", "view-private-symbolic", "view-hidden-symbolic"] : ["view-reveal-symbolic", "view-visible-symbolic"])
                        size: Math.round(Style.font.body * 1.1)
                        color: Color.popups.text
                    }

                    MouseArea {
                        id: revealHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: field.password = !field.password
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: Style.spacing.md

                Button {
                    text: "Cancel"
                    onClicked: root.close()
                }

                Button {
                    text: "Connect"
                    bordered: true
                    opacity: field.text === "" ? 0.4 : 1
                    onClicked: root.submit()
                }
            }
        }
    }
}
