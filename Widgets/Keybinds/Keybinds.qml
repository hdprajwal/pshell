import QtQuick
import Quickshell.Io
import qs.Services
import qs.Commons
import qs.Ui
import "../../Services/Keybinds.js" as K

// The keybind cheat sheet, read out of the compositor.
//
// `hyprctl binds -j` rather than a config file, because which keys are bound
// is a fact Hyprland owns and a parsed config is a guess that goes stale the
// moment somebody binds something at runtime.
//
// What it cannot tell us, and what this panel does about it: every bind on a
// Hyprland driven from Lua reports `dispatcher: "__lua"` with an opaque
// number, because a Lua bind's action is a closure. 115 of the 119 binds here
// are like that. So the panel never prints the dispatcher, prefers Hyprland's
// own `description`, falls back to the user's `keybinds.labels`, and says out
// loud how many rows nobody has described yet. The decoding is all in
// Services/Keybinds.js, where node can test it.
//
// Re-read on open, not on a timer: binds change when the config does, and
// nobody consults a cheat sheet in a loop.
Panel {
    id: root

    moduleName: "pshell.keybinds"
    ipcTarget: "pshell.keybinds"

    property var cfg: ({})

    readonly property int panelWidth: cfg.panelWidth || Style.space(520)
    readonly property int listHeight: cfg.listHeight || Style.space(420)

    // The parsed `hyprctl binds -j` array, and why the last read failed if it
    // did. Empty and "" respectively until the first open.
    property var binds: []
    property string lastError: ""

    property string query: ""

    readonly property var groups: K.group(root.binds, Config.keybinds.labels)
    readonly property var shown: K.filter(root.groups, root.query)
    readonly property var counted: K.countUnlabelled(root.groups)

    function refresh() {
        reader.running = false;
        reader.running = true;
    }

    onOpenedChanged: {
        if (opened)
            root.refresh();
        else
            root.query = "";
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // Shelling out the way Services/WidgetRegistry.qml does. hyprctl is a
    // program, not a socket this shell should be speaking to by hand: the IPC
    // socket's framing is Hyprland's business and hyprctl is the supported
    // way to ask it anything.
    Process {
        id: reader

        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (raw === "")
                    return;
                try {
                    const parsed = JSON.parse(raw);
                    root.binds = parsed instanceof Array ? parsed : [];
                    root.lastError = "";
                } catch (e) {
                    // Keep whatever was read last rather than blanking the
                    // sheet: an old list of binds is still true about most of
                    // them, and a panel that empties itself looks broken.
                    root.lastError = "hyprctl did not answer with JSON";
                    console.warn("pshell: could not read hyprctl binds —", e);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = String(text || "").trim();
                if (message !== "")
                    root.lastError = message;
            }
        }

        // A machine with no hyprctl at all -- another compositor, or Hyprland
        // not on this shell's PATH -- said in words. Checked on exit rather
        // than on stderr, because a program that was never found never writes
        // any. The empty-state sentence below covers it a second time in case
        // the process fails so early that this never fires: an empty panel is
        // the one outcome that must not happen.
        onExited: (code, status) => {
            if (code !== 0 && root.binds.length === 0 && root.lastError === "")
                root.lastError = "hyprctl exited " + code + ". Is Hyprland running, and is hyprctl on this shell's PATH?";
        }
    }

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        iconName: Glyphs.keybinds
        tooltipText: "Keybinds"

        onPressed: b => {
            if (b === Qt.LeftButton)
                root.toggle();
        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(root.panelWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            // The filter field wants ordinary typing, not j/k turned into
            // scrolling. Same rule Tailscale's search field documents.
            blocked: searchField.activeFocus
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)
            // The list is the only thing here to move through, and it is far
            // taller than the panel, so the arrows scroll it rather than
            // walking a cursor over 119 rows one at a time.
            onMoveRequested: (dx, dy) => {
                if (dy === 0)
                    return;
                const step = Math.round(Style.font.body * 3);
                list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + dy * step));
            }
            // "/" is the search key everywhere else a list is filtered, so it
            // is the one here too.
            onTextKey: t => {
                if (t === "/")
                    searchField.forceActiveFocus();
            }

            Column {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.lg

                Row {
                    width: parent.width
                    spacing: Style.spacing.sm

                    TextField {
                        id: searchField

                        width: column.width - refreshButton.width - parent.spacing
                        text: root.query
                        placeholderText: "Filter keys or descriptions..."
                        foreground: Color.popups.text

                        onTextChanged: root.query = text
                        // Escape clears and hands focus back, so a mistyped
                        // filter costs neither the panel nor the sheet.
                        Keys.onEscapePressed: {
                            text = "";
                            keyCatcher.forceActiveFocus();
                        }
                    }

                    PanelActionButton {
                        id: refreshButton

                        foreground: Color.popups.text
                        tooltipText: "Re-read hyprctl binds"
                        onClicked: root.refresh()

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: Glyphs.refresh
                            size: Style.font.icon
                            color: reader.running ? Color.accent : Color.muted
                        }
                    }
                }

                // How much of this sheet is actually a sheet. Said out loud
                // because the alternative is a panel that quietly shows 115
                // rows of key combinations with nothing beside them and lets
                // the reader work out why on their own.
                Text {
                    width: parent.width
                    visible: root.counted.total > 0
                    wrapMode: Text.WordWrap
                    text: {
                        const total = root.counted.total;
                        const missing = root.counted.unlabelled;
                        if (missing === 0)
                            return total + " binds, all described.";
                        return total + " binds, " + missing + " with no description. Hyprland only knows what a bind does when the bind says so — a Lua bind's action is a closure it cannot read. Name them with `description` on the bind itself, or in config.json under `keybinds.labels`, keyed by the combination printed on the row.";
                    }
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }

                // Whatever went wrong reading them. Its own line rather than
                // replacing the list: a stale list plus the reason it is
                // stale beats either one alone.
                Text {
                    width: parent.width
                    visible: root.lastError !== ""
                    wrapMode: Text.WordWrap
                    text: root.lastError
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }

                Text {
                    width: parent.width
                    visible: !reader.running && root.counted.total === 0
                    wrapMode: Text.WordWrap
                    text: "No binds to show. `hyprctl binds -j` returned none — either Hyprland has none, or it could not be asked."
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                Text {
                    width: parent.width
                    visible: root.counted.total > 0 && root.shown.length === 0
                    text: "Nothing matches “" + root.query.trim() + "”"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                PanelSeparator {
                    visible: root.shown.length > 0
                    foreground: Color.popups.text
                }

                Flickable {
                    id: list

                    width: parent.width
                    height: Math.min(root.listHeight, groupColumn.implicitHeight)
                    visible: root.shown.length > 0
                    contentWidth: width
                    contentHeight: groupColumn.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: groupColumn

                        width: parent.width
                        spacing: Style.spacing.xl

                        Repeater {
                            model: root.shown

                            Column {
                                id: group

                                required property var modelData

                                width: groupColumn.width
                                spacing: Style.spacing.xs

                                PanelSectionHeader {
                                    text: group.modelData.title
                                    foreground: Color.popups.text
                                }

                                Repeater {
                                    model: group.modelData.rows

                                    Item {
                                        id: row

                                        required property var modelData

                                        width: group.width
                                        implicitHeight: Math.round(Style.font.body * 1.7)

                                        // The combination is printed exactly
                                        // as Services/Keybinds.js normalises
                                        // it, which is exactly the key a
                                        // `keybinds.labels` entry uses. Prettier
                                        // spacing here would mean copying a
                                        // label key off the screen no longer
                                        // works.
                                        Text {
                                            id: combo

                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.round(row.width * 0.42)
                                            text: row.modelData.combo
                                            color: Color.popups.text
                                            elide: Text.ElideRight
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.bodySmall
                                        }

                                        Text {
                                            anchors.left: combo.right
                                            anchors.leftMargin: Style.spacing.lg
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.description
                                            // Muted and italic for the rows
                                            // nobody has described, so the
                                            // sheet shows at a glance which
                                            // half of it is missing.
                                            color: row.modelData.source === "none" ? Color.muted : Color.popups.text
                                            font.italic: row.modelData.source === "none"
                                            elide: Text.ElideRight
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.bodySmall
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
