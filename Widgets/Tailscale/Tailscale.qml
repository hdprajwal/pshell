import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import qs.Commons
import qs.Ui

// Tailscale state, read straight off the CLI.
//
// DankMaterialShell asks its Go daemon for this over IPC. There is no daemon
// here, and `tailscale status --json` already prints everything the panel
// needs, so this polls the command instead. Tailscale publishes no event
// stream worth holding open, and its state changes on the order of minutes,
// so a poll is the honest shape rather than a compromise.
Panel {
    id: root
    moduleName: "qsbar.tailscale"
    ipcTarget: "qsbar.tailscale"

    property var cfg: ({})

    // The whole parsed status document. Empty until the first poll lands.
    property var status: ({})
    property bool failed: false
    property string lastError: ""

    // Panel state, cleared once the panel closes so it never reopens
    // filtered.
    property string query: ""
    property string filter: "myOnline"

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

    // The exit-node dropdown's option list and value. Machines are addressed
    // by their first Tailscale IP, same as the CLI call itself, so the value
    // round-trips back into useExitNode() without a second lookup table.
    readonly property var exitNodeOptions: {
        const opts = [{
            value: "",
            label: "None"
        }];
        for (var i = 0; i < root.exitCandidates.length; i++) {
            const d = root.exitCandidates[i];
            opts.push({
                value: String((d.TailscaleIPs || [])[0] || ""),
                label: String(d.HostName || ""),
                description: root.ownerOf(d)
            });
        }
        return opts;
    }
    readonly property string activeExitValue: root.activeExit ? String((root.activeExit.TailscaleIPs || [])[0] || "") : ""

    function exitNodeForValue(value) {
        if (value === "")
            return null;
        return root.exitCandidates.find(d => String((d.TailscaleIPs || [])[0] || "") === value) || null;
    }

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
    }

    // -- separates the address from anything wl-copy might read as a flag.
    function copyText(text) {
        clipboard.command = ["wl-copy", "--", String(text)];
        clipboard.running = false;
        clipboard.running = true;
    }

    readonly property bool showLabel: root.showName && root.running && root.selfName !== ""

    // What the button paints, for Section's open-panel mark: the icon alone,
    // never the name label beside it.

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function press(mouseButton) {
        if (mouseButton !== Qt.LeftButton)
            return;
        root.toggle();
        if (root.opened)
            root.refresh();
    }

    onOpenedChanged: if (!root.opened) {
        root.lastError = "";
        root.query = "";
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

    // The Tailscale mark itself, shipped beside this file, rather than a
    // generic VPN glyph from the icon theme. It is one flat shape, so it tints
    // to the bar's foreground like everything else and state is carried by
    // colour: foreground connected, dimmed not, urgent when the CLI errored.
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconSource: Qt.resolvedUrl("tailscale.svg")
        label: root.showLabel ? root.selfName : ""
        iconColor: root.failed ? Color.urgent : (root.running ? Color.foreground : Color.muted)

        onPressed: b => root.press(b)
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(column.panelWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // Both a plain text field and the exit-node dropdown's embedded
            // search field want ordinary typing, not j/k turned into panel
            // navigation. Same rule the dropdowns themselves document for
            // their own popups.
            blocked: searchField.activeFocus || exitDropdown.popupOpen
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                readonly property int panelWidth: Math.round(Style.font.body * 26)

                // Header: the state, who you are, and the one action that
                // matters.
                PanelHero {
                    width: column.panelWidth
                    foreground: Color.popups.text
                    iconComponent: Component {
                        BarIcon {
                            iconSource: Qt.resolvedUrl("tailscale.svg")
                            size: Style.font.display
                            color: root.failed ? Color.urgent : (root.running ? Color.popups.text : Color.muted)
                        }
                    }
                    title: {
                        if (root.needsLogin)
                            return "Needs login";
                        if (root.running)
                            return "Connected";
                        return root.backendState === "" ? "Not running" : "Disconnected";
                    }
                    meta: root.loginName
                    trailingControl: Component {
                        Button {
                            text: root.running ? "Disconnect" : "Connect"
                            foreground: Color.popups.text
                            bordered: true
                            onClicked: root.running ? root.disconnect() : root.connect()
                        }
                    }
                }

                PanelSeparator {
                    width: column.panelWidth
                    foreground: Color.popups.text
                }

                // Exit node. A dropdown rather than a floating menu list of
                // our own: the kit's popup already does the searching and the
                // z-ordering, and unlike the panel itself it does not have to
                // reason about layer-shell focus.
                Column {
                    width: column.panelWidth
                    spacing: Style.spacing.sm

                    PanelSectionHeader {
                        text: "Exit node"
                        foreground: Color.popups.text
                    }

                    SearchableDropdown {
                        id: exitDropdown
                        width: column.panelWidth
                        showLabel: false
                        foreground: Color.popups.text
                        background: Color.popups.background
                        options: root.exitNodeOptions
                        value: root.activeExitValue
                        placeholderText: "Search exit nodes..."
                        emptyText: "No exit node candidates"
                        onChanged: value => root.useExitNode(root.exitNodeForValue(value))
                    }
                }

                PanelSeparator {
                    width: column.panelWidth
                    foreground: Color.popups.text
                }

                // Search, filters, and the device list. A manual refresh sits
                // beside the search field for when you have just changed
                // something on another machine and do not want to wait out a
                // poll.
                Column {
                    width: column.panelWidth
                    spacing: Style.spacing.sm

                    PanelSectionHeader {
                        text: "Devices"
                        foreground: Color.popups.text
                    }

                    Row {
                        width: column.panelWidth
                        spacing: Style.spacing.sm

                        TextField {
                            id: searchField
                            width: column.panelWidth - refreshButton.width - parent.spacing
                            text: root.query
                            placeholderText: "Search devices..."
                            foreground: Color.popups.text

                            onTextChanged: root.query = text
                            // Escape clears and hands focus back, so a
                            // mistyped search costs neither the panel nor the
                            // toggle.
                            Keys.onEscapePressed: {
                                text = "";
                                keyCatcher.forceActiveFocus();
                            }
                        }

                        PanelActionButton {
                            id: refreshButton
                            foreground: Color.popups.text
                            tooltipText: "Refresh"
                            onClicked: root.refresh()

                            BarIcon {
                                anchors.centerIn: parent
                                iconSource: Icons.first(["view-refresh-symbolic", "view-refresh"])
                                size: Style.font.icon
                                color: poll.running ? Color.accent : Color.muted
                            }
                        }
                    }

                    // Counts live on the chips because the useful question is
                    // usually "how many of mine are up", which the number
                    // answers without opening anything.
                    Row {
                        spacing: Style.spacing.sm

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
                        width: column.panelWidth
                        spacing: Style.spacing.sm

                        Repeater {
                            model: root.filtered.slice(0, root.maxNodes)

                            TailscaleDevice {
                                required property var modelData

                                width: column.panelWidth
                                device: modelData
                                isSelf: String(modelData.ID || "") === root.selfId
                                owner: root.ownerOf(modelData)
                                onCopyRequested: address => root.copyText(address)
                            }
                        }

                        Text {
                            visible: root.filtered.length === 0
                            text: root.query.trim() === "" ? "Nothing matches this filter" : "No device matches “" + root.query.trim() + "”"
                            color: Color.muted
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }

                        Text {
                            visible: root.filtered.length > root.maxNodes
                            text: "+" + (root.filtered.length - root.maxNodes) + " more"
                            color: Color.muted
                            font.family: Style.font.family
                            font.pixelSize: Math.round(Style.font.body * 0.85)
                        }
                    }
                }

                Column {
                    visible: root.health.length > 0
                    width: column.panelWidth
                    spacing: Style.spacing.xs

                    PanelSectionHeader {
                        text: "Health"
                        foreground: Color.urgent
                    }

                    Repeater {
                        model: root.health

                        Row {
                            required property string modelData

                            width: column.panelWidth
                            spacing: Style.spacing.sm

                            BarIcon {
                                anchors.top: parent.top
                                iconSource: Icons.first(["dialog-warning-symbolic", "dialog-warning"])
                                size: Style.font.body
                                color: Color.urgent
                            }

                            Text {
                                width: column.panelWidth - Style.font.body - Style.spacing.sm
                                wrapMode: Text.Wrap
                                text: parent.modelData
                                color: Color.urgent
                                opacity: 0.85
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * 0.8)
                            }
                        }
                    }
                }

                Text {
                    visible: root.lastError !== ""
                    width: column.panelWidth
                    wrapMode: Text.Wrap
                    text: root.lastError
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.body * 0.85)
                }
            }
        }
    }
}
