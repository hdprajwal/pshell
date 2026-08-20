import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Services
import qs.Components

// Tailscale state, read straight off the CLI.
//
// DankMaterialShell asks its Go daemon for this over IPC. There is no daemon
// here, and `tailscale status --json` already prints everything the panel
// needs, so this polls the command instead. Tailscale publishes no event
// stream worth holding open, and its state changes on the order of minutes,
// so a poll is the honest shape rather than a compromise.
BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    // The whole parsed status document. Empty until the first poll lands.
    property var status: ({})
    property bool failed: false
    property string lastError: ""

    // Panel state, cleared on dismiss so it never reopens filtered.
    property string query: ""
    property string filter: "myOnline"
    property bool exitMenuOpen: false
    // True only while the search field is in use. The popout ties its
    // keyboard focus to this rather than holding focus for its whole life.
    property bool searching: false

    readonly property int interval: (cfg.interval || 10) * 1000
    readonly property bool showName: cfg.showName === true
    readonly property int maxNodes: cfg.maxNodes || 8

    readonly property string backendState: String(status.BackendState || "")
    readonly property bool running: backendState === "Running"
    readonly property bool needsLogin: backendState === "NeedsLogin"

    readonly property var self: status.Self || ({})
    readonly property string selfId: String(self.ID || "")
    readonly property string selfName: String(self.HostName || "")

    // Whose tailnet this is. Self.UserID indexes into the User map, which is
    // the only place the login name appears.
    readonly property string loginName: {
        const users = status.User || ({});
        const me = users[String(self.UserID || "")];
        if (me && me.LoginName)
            return String(me.LoginName);
        const tailnet = status.CurrentTailnet || ({});
        return String(tailnet.Name || "");
    }

    // Self and the peers as one list. The chip counts include this machine, so
    // it has to be a device like any other rather than something the header
    // mentions and the list leaves out.
    readonly property var devices: {
        const out = [];
        if (root.selfId !== "")
            out.push(root.self);
        const raw = status.Peer || ({});
        for (var k in raw)
            out.push(raw[k]);
        out.sort((a, b) => {
            const aSelf = String(a.ID || "") === root.selfId;
            const bSelf = String(b.ID || "") === root.selfId;
            if (aSelf !== bSelf)
                return aSelf ? -1 : 1;
            if (!!a.Online !== !!b.Online)
                return a.Online ? -1 : 1;
            return String(a.HostName || "").localeCompare(String(b.HostName || ""));
        });
        return out;
    }

    // "Mine" is by owner, not by machine. A tailnet can be shared, and two
    // accounts on one can easily give a machine the same name.
    readonly property var mine: devices.filter(d => String(d.UserID || "") === String(self.UserID || ""))
    readonly property var onlineDevices: devices.filter(d => d.Online === true)
    readonly property var myOnline: mine.filter(d => d.Online === true)

    readonly property var filtered: {
        var base = root.devices;
        if (root.filter === "myOnline")
            base = root.myOnline;
        else if (root.filter === "online")
            base = root.onlineDevices;

        const q = root.query.trim().toLowerCase();
        if (q === "")
            return base;
        // Hostname and address both, since you may be hunting either.
        return base.filter(d => {
            const host = String(d.HostName || "").toLowerCase();
            const ips = (d.TailscaleIPs || []).join(" ").toLowerCase();
            return host.indexOf(q) >= 0 || ips.indexOf(q) >= 0;
        });
    }

    // Only machines advertising themselves as exit nodes can be chosen as one,
    // and routing through yourself is not a thing.
    readonly property var exitCandidates: devices.filter(d => d.ExitNodeOption && String(d.ID || "") !== root.selfId)
    readonly property var activeExit: devices.find(d => d.ExitNode) || null

    // The owner of a device, empty when it is one of yours. It is what tells
    // two similarly named machines apart on a shared tailnet.
    function ownerOf(device) {
        const uid = String(device.UserID || "");
        if (uid === "" || uid === String(self.UserID || ""))
            return "";
        const users = status.User || ({});
        const user = users[uid];
        if (!user)
            return "";
        // The display name, not the login. A person's name says whose machine
        // it is in half the width of the address they registered with.
        return String(user.DisplayName || user.LoginName || "");
    }

    // Whatever tailscaled is unhappy about. It is the reason a tailnet quietly
    // half-works, so it belongs in front of you rather than behind a CLI call.
    readonly property var health: {
        const raw = status.Health;
        if (!raw)
            return [];
        return (raw instanceof Array ? raw : [raw]).map(h => String(h)).filter(h => h !== "");
    }

    function refresh() {
        poll.running = false;
        poll.running = true;
    }

    // Actions go through the CLI and are followed by a refresh, since none of
    // them report the resulting state themselves.
    function run(args) {
        action.command = ["tailscale"].concat(args);
        action.running = false;
        action.running = true;
    }

    function connect() {
        root.run(["up"]);
    }

    function disconnect() {
        root.run(["down"]);
    }

    function useExitNode(node) {
        root.run(["set", "--exit-node=" + (node ? String(node.TailscaleIPs[0]) : "")]);
        root.exitMenuOpen = false;
    }

    // -- separates the address from anything wl-copy might read as a flag.
    function copyText(text) {
        clipboard.command = ["wl-copy", "--", String(text)];
        clipboard.running = false;
        clipboard.running = true;
    }

    // The Tailscale mark itself, shipped beside this file, rather than a
    // generic VPN glyph from the icon theme. It is one flat shape, so it tints
    // to the bar's foreground like everything else and state is carried by
    // colour: foreground connected, dimmed not, urgent when the CLI errored.
    iconSource: Qt.resolvedUrl("tailscale.svg")
    iconColor: root.failed ? Config.urgent : (root.running ? Config.fg : Config.dim)
    text: root.showName && root.running ? root.selfName : ""
    active: PopoutManager.current === panel

    onClicked: button => {
        if (button !== Qt.LeftButton)
            return;
        panel.toggle(root);
        if (panel.opened)
            root.refresh();
    }

    Process {
        id: poll
        running: true
        command: ["tailscale", "status", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = JSON.parse(String(text));
                    root.failed = false;
                    root.lastError = "";
                } catch (e) {
                    // A non-JSON reply usually means the daemon is not up, so
                    // the previous status is dropped rather than left to look
                    // current.
                    root.status = ({});
                    root.failed = true;
                    root.lastError = "tailscale status did not return JSON";
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = String(text).trim();
                if (message !== "") {
                    root.failed = true;
                    root.lastError = message;
                }
            }
        }
    }

    // Actions can fail for reasons worth showing: `up` may want a login, and
    // some setups need elevation. Surfacing stderr beats a click that
    // silently does nothing.
    Process {
        id: action

        stderr: StdioCollector {
            onStreamFinished: {
                const message = String(text).trim();
                root.lastError = message;
                root.failed = message !== "";
            }
        }

        onExited: root.refresh()
    }

    Process {
        id: clipboard
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        onTriggered: if (!poll.running)
            poll.running = true
    }

    Popout {
        id: panel
        bar: root.bar
        // Focus is held only while the search field is in use, never for the
        // life of the panel. A focused layer surface takes clicks away from
        // the bar behind it, so a panel holding focus throughout can be opened
        // from its widget but not closed from it.
        //
        // Exclusive rather than OnDemand, for the same reason PasswordPrompt
        // uses it: OnDemand grants focus only on a click, and the click that
        // starts a search is already delivered by the time this flips, which
        // leaves the field showing a cursor and receiving nothing.
        keyboardFocus: root.searching ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onDismissed: {
            root.lastError = "";
            root.query = "";
            root.exitMenuOpen = false;
            root.searching = false;
        }

        Column {
            id: content
            spacing: 12

            readonly property int panelWidth: Math.round(Config.fontSize * 26)

            // Header: the state, who you are, and the one action that matters.
            Item {
                width: content.panelWidth
                height: Math.max(headerText.implicitHeight, connectButton.height)

                Column {
                    id: headerText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: {
                            if (root.needsLogin)
                                return "Needs login";
                            if (root.running)
                                return "Connected";
                            return root.backendState === "" ? "Not running" : "Disconnected";
                        }
                        color: Config.fg
                        font.family: Config.fontFamily
                        font.pixelSize: Math.round(Config.fontSize * 1.15)
                    }

                    Text {
                        visible: root.loginName !== ""
                        text: root.loginName
                        color: Config.dim
                        font.family: Config.fontFamily
                        font.pixelSize: Math.round(Config.fontSize * 0.9)
                    }
                }

                Rectangle {
                    id: connectButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: connectRow.implicitWidth + 18
                    height: Math.round(Config.fontSize * 2.2)
                    radius: height / 2
                    color: connectPointer.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)

                    Row {
                        id: connectRow
                        anchors.centerIn: parent
                        spacing: 6

                        BarIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            iconSource: Icons.first(root.running ? ["network-offline-symbolic", "network-vpn-disconnected-symbolic"] : ["network-vpn-symbolic", "network-vpn"])
                            size: Math.round(Config.fontSize * 1.1)
                            color: Config.fg
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.running ? "Disconnect" : "Connect"
                            color: Config.fg
                            font.family: Config.fontFamily
                            font.pixelSize: Math.round(Config.fontSize * 0.95)
                        }
                    }

                    MouseArea {
                        id: connectPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.running ? root.disconnect() : root.connect()
                    }
                }
            }

            // Exit node. Expands in place rather than floating a menu over the
            // panel, which would mean a second window and a second z-order to
            // reason about for a list that is usually one line long.
            Column {
                width: content.panelWidth
                spacing: 6

                Item {
                    width: parent.width
                    height: Math.round(Config.fontSize * 2.4)

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Exit node"
                        color: Config.fg
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(content.panelWidth * 0.52)
                        height: parent.height
                        radius: 5
                        // Recessed rather than lifted, so it reads as a field
                        // you change and not a card you look at.
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.width: 1
                        border.color: exitPointer.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.activeExit ? String(root.activeExit.HostName) : "None"
                            color: root.activeExit ? Config.fg : Config.dim
                            font.family: Config.fontFamily
                            font.pixelSize: Config.fontSize
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.exitMenuOpen ? "⌃" : "⌄"
                            color: Config.dim
                            font.family: Config.fontFamily
                            font.pixelSize: Config.fontSize
                        }

                        MouseArea {
                            id: exitPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.exitMenuOpen = !root.exitMenuOpen
                        }
                    }
                }

                Column {
                    visible: root.exitMenuOpen
                    width: parent.width
                    spacing: 0

                    TailscaleExitOption {
                        width: parent.width
                        label: "None"
                        selected: root.activeExit === null
                        onPicked: root.useExitNode(null)
                    }

                    Repeater {
                        model: root.exitCandidates

                        TailscaleExitOption {
                            required property var modelData

                            width: parent.width
                            label: String(modelData.HostName || "")
                            selected: modelData.ExitNode === true
                            onPicked: root.useExitNode(modelData)
                        }
                    }

                    Text {
                        visible: root.exitCandidates.length === 0
                        // Said plainly, because an empty dropdown reads as a
                        // bug when the truth is that nobody is offering.
                        text: "No machine here advertises an exit node"
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Config.dim
                        font.family: Config.fontFamily
                        font.pixelSize: Math.round(Config.fontSize * 0.85)
                    }
                }
            }

            // Search, and a manual refresh for when you have just changed
            // something on another machine and do not want to wait out a poll.
            Item {
                width: content.panelWidth
                height: Math.round(Config.fontSize * 2.6)

                Rectangle {
                    id: searchBox
                    anchors.left: parent.left
                    anchors.right: refreshButton.left
                    anchors.rightMargin: 8
                    height: parent.height
                    radius: 5
                    color: Qt.rgba(0, 0, 0, 0.35)
                    border.width: 1
                    border.color: field.activeFocus ? Config.accent : Qt.rgba(1, 1, 1, 0.12)

                    BarIcon {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: Icons.first(["system-search-symbolic", "edit-find-symbolic"])
                        size: Math.round(Config.fontSize * 1.1)
                        color: Config.dim
                    }

                    TextInput {
                        id: field
                        anchors.left: searchIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Config.fg
                        selectionColor: Config.accent
                        selectedTextColor: Config.bg
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize

                        onTextChanged: root.query = text
                        // Escape clears and hands focus back, so a mistyped
                        // search costs neither the panel nor the toggle.
                        Keys.onEscapePressed: {
                            text = "";
                            root.searching = false;
                            focus = false;
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: field.text === ""
                            text: "Search devices..."
                            color: Config.dim
                            font.family: Config.fontFamily
                            font.pixelSize: Config.fontSize
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            root.searching = true;
                            field.forceActiveFocus();
                        }
                    }
                }

                Rectangle {
                    id: refreshButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height
                    height: parent.height
                    radius: 5
                    color: refreshPointer.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                    BarIcon {
                        anchors.centerIn: parent
                        iconSource: Icons.first(["view-refresh-symbolic", "view-refresh"])
                        size: Math.round(Config.fontSize * 1.2)
                        color: poll.running ? Config.accent : Config.dim
                    }

                    MouseArea {
                        id: refreshPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refresh()
                    }
                }
            }

            // Counts live on the chips because the useful question is usually
            // "how many of mine are up", which the number answers without
            // opening anything.
            Row {
                spacing: 6

                TailscaleChip {
                    label: "My Online"
                    count: root.myOnline.length
                    selected: root.filter === "myOnline"
                    onPicked: root.filter = "myOnline"
                }

                TailscaleChip {
                    label: "Online"
                    count: root.onlineDevices.length
                    selected: root.filter === "online"
                    onPicked: root.filter = "online"
                }

                TailscaleChip {
                    label: "All"
                    count: root.devices.length
                    selected: root.filter === "all"
                    onPicked: root.filter = "all"
                }
            }

            Column {
                spacing: 6

                Repeater {
                    model: root.filtered.slice(0, root.maxNodes)

                    TailscaleDevice {
                        required property var modelData

                        device: modelData
                        isSelf: String(modelData.ID || "") === root.selfId
                        owner: root.ownerOf(modelData)
                        onCopyRequested: address => root.copyText(address)
                    }
                }

                Text {
                    visible: root.filtered.length === 0
                    text: root.query.trim() === "" ? "Nothing matches this filter" : "No device matches “" + root.query.trim() + "”"
                    color: Config.dim
                    font.family: Config.fontFamily
                    font.pixelSize: Config.fontSize
                }

                Text {
                    visible: root.filtered.length > root.maxNodes
                    text: "+" + (root.filtered.length - root.maxNodes) + " more"
                    color: Config.dim
                    font.family: Config.fontFamily
                    font.pixelSize: Math.round(Config.fontSize * 0.85)
                }
            }

            Column {
                visible: root.health.length > 0
                width: content.panelWidth
                spacing: 3

                Repeater {
                    model: root.health

                    Row {
                        required property string modelData

                        spacing: 6

                        BarIcon {
                            anchors.top: parent.top
                            iconSource: Icons.first(["dialog-warning-symbolic", "dialog-warning"])
                            size: Math.round(Config.fontSize * 1.1)
                            color: Config.urgent
                        }

                        Text {
                            width: content.panelWidth - Math.round(Config.fontSize * 1.1) - 6
                            wrapMode: Text.Wrap
                            text: parent.modelData
                            color: Config.urgent
                            opacity: 0.85
                            font.family: Config.fontFamily
                            font.pixelSize: Math.round(Config.fontSize * 0.8)
                        }
                    }
                }
            }

            Text {
                visible: root.lastError !== ""
                width: content.panelWidth
                wrapMode: Text.Wrap
                text: root.lastError
                color: Config.urgent
                font.family: Config.fontFamily
                font.pixelSize: Math.round(Config.fontSize * 0.85)
            }
        }
    }
}
