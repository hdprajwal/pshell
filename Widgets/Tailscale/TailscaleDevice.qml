import QtQuick
import qs.Services
import qs.Components

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

    readonly property color onlineColor: "#3fb950"

    width: Math.round(Config.fontSize * 26)
    height: body.implicitHeight + 16
    radius: 6
    color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

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
                width: Math.round(Config.fontSize * 0.6)
                height: width
                radius: width / 2
                color: root.online ? root.onlineColor : Config.dim
                opacity: root.online ? 1 : 0.6
            }

            Text {
                id: nameLabel
                anchors.left: dot.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.hostName
                color: Config.fg
                opacity: root.online ? 1 : 0.6
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.isSelf || root.owner !== ""
                text: root.isSelf ? "This device" : root.owner
                color: Config.dim
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 0.85)
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Math.round(Config.fontSize * 12))
                horizontalAlignment: Text.AlignRight
            }
        }

        Item {
            width: parent.width
            height: ipLabel.implicitHeight

            Text {
                id: ipLabel
                anchors.left: parent.left
                anchors.leftMargin: Math.round(Config.fontSize * 0.6) + 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.ip
                color: Config.dim
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 0.9)
            }

            // The address is the one thing you open this panel to take away
            // with you, so copying it is a click rather than a selection.
            Rectangle {
                id: copyButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.ip !== ""
                width: Math.round(Config.fontSize * 1.7)
                height: width
                radius: 4
                color: copyPointer.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                BarIcon {
                    anchors.centerIn: parent
                    iconSource: Icons.first(["edit-copy-symbolic", "edit-copy"])
                    size: Math.round(Config.fontSize * 1.1)
                    color: copied.running ? root.onlineColor : Config.dim
                }

                MouseArea {
                    id: copyPointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.copyRequested(root.ip);
                        copied.restart();
                    }
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
            leftPadding: Math.round(Config.fontSize * 0.6) + 8
            color: Config.dim
            opacity: 0.8
            font.family: Config.fontFamily
            font.pixelSize: Math.round(Config.fontSize * 0.85)
        }
    }
}
