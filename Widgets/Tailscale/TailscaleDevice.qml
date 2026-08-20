import QtQuick
import qs.Services
import qs.Commons
import qs.Ui

// One machine on the tailnet.
//
// The card sits on a lifted surface derived from the panel background rather
// than a fixed colour, so it stays readable whatever the wallpaper does to the
// theme. Reachability is the one thing here that does not follow the accent:
// green means online in every tool that shows a network, and an accent pulled
// off a red wallpaper would make a healthy machine look broken.
Rectangle {
    id: root

    property var device: ({})
    property bool isSelf: false

    signal copyRequested(string text)

    // The DNS label, not HostName. Two people on a shared tailnet can give a
    // machine the same HostName, and Tailscale disambiguates only in the DNS
    // name, so this is what its own CLI and admin console display.
    readonly property string hostName: {
        const dns = String(device.DNSName || "").split(".")[0];
        return dns !== "" ? dns : String(device.HostName || "");
    }
    // Empty for your own machines. Someone else's is worth labelling, since
    // on a shared tailnet a name alone does not say whose it is.
    property string owner: ""
    readonly property bool online: device.Online === true
    readonly property string ip: (device.TailscaleIPs || [])[0] || ""
    readonly property string relay: String(device.Relay || "")
    readonly property string os: String(device.OS || "")

    // Fixed rather than the accent: green reads as "online" the same way in
    // every network tool, and an accent pulled off a red wallpaper would
    // make a healthy machine look broken.
    readonly property color onlineColor: "#3fb950"

    width: Math.round(Style.font.body * 26)
    height: body.implicitHeight + 16
    radius: Style.cornerRadius
    color: hover.containsMouse ? Style.hoverFill : Style.normalFill
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.08)

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 3

        Item {
            width: parent.width
            height: nameLabel.implicitHeight

            Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(Style.font.body * 0.6)
                height: width
                radius: width / 2
                color: root.online ? root.onlineColor : Color.muted
                opacity: root.online ? 1 : 0.6
            }

            Text {
                id: nameLabel
                anchors.left: dot.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.hostName
                color: Color.popups.text
                opacity: root.online ? 1 : 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.isSelf || root.owner !== ""
                text: root.isSelf ? "This device" : root.owner
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.85)
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Math.round(Style.font.body * 12))
                horizontalAlignment: Text.AlignRight
            }
        }

        Item {
            width: parent.width
            height: ipLabel.implicitHeight

            Text {
                id: ipLabel
                anchors.left: parent.left
                anchors.leftMargin: Math.round(Style.font.body * 0.6) + 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.ip
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.body * 0.9)
            }

            // The address is the one thing you open this panel to take away
            // with you, so copying it is a click rather than a selection.
            PanelActionButton {
                id: copyButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.ip !== ""
                foreground: Color.popups.text
                tooltipText: "Copy address"
                onClicked: {
                    root.copyRequested(root.ip);
                    copied.restart();
                }

                BarIcon {
                    anchors.centerIn: parent
                    iconSource: Icons.first(["edit-copy-symbolic", "edit-copy"])
                    size: Style.font.icon
                    color: copied.running ? root.onlineColor : Color.muted
                }
            }

            // Tints the icon briefly so the click has an answer. There is no
            // other feedback: the clipboard is invisible.
            Timer {
                id: copied
                interval: 900
            }
        }

        Text {
            // Relay is the DERP region traffic is bouncing through. It only
            // means something when there is no direct path, which is exactly
            // when you are wondering why a machine feels slow.
            text: {
                const parts = [];
                if (root.os !== "")
                    parts.push(root.os);
                if (root.relay !== "")
                    parts.push("relay: " + root.relay);
                return parts.join("  •  ");
            }
            leftPadding: Math.round(Style.font.body * 0.6) + 8
            color: Color.muted
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.body * 0.85)
        }
    }
}
