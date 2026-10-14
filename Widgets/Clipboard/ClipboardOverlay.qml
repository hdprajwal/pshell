import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Services/ClipboardHistory.js" as History

// The clipboard history panel: a list on the left, the selected entry in
// full on the right, typing filters, Enter pastes.
//
// Omarchy's clipboard plugin, keys and layout both, so the muscle memory
// carries over: Esc clears the filter and then closes, Shift+Enter copies
// without pasting, Delete forgets one entry and Shift+Delete all of them
// after asking. Drawn in pshell's palette from the menu tokens -- the same
// surface Omarchy's draws on, so a shell.toml that styles the one styles
// the other.
//
// Pins are pshell's own: Ctrl+P pins or unpins the selected entry. Ctrl,
// because every plain letter is already the filter's. Pinned entries are
// listed first with a pin beside them, Shift+Delete leaves them alone, and
// Delete on one asks first -- it was kept on purpose, so one stray key
// should not be enough to lose it.
//
// A fullscreen overlay with an exclusive keyboard grab rather than a bar
// popout, for the carousel's reason: it is opened by a keybind from inside
// some other window, and needs every key until it is gone.
PanelWindow {
    id: overlay

    screen: Clipboard.screen
    visible: Clipboard.visible
    color: "transparent"

    WlrLayershell.namespace: "pshell:clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ------------------------------------------------------------- state

    property string filter: ""
    property int selected: 0
    // "" when no question is up, "clear" for Shift+Delete, "forget" for
    // Delete on a pinned entry.
    property string confirming: ""
    // Which entry "forget" means, by what it is rather than where: a copy
    // landing while the question is up can move it.
    property string forgetKey: ""

    // At most fifty rows, as Omarchy draws: a history is searched, not
    // scrolled through, and fifty is more than a screen's worth.
    readonly property var rows: Clipboard.visible ? History.displayRows(Clipboard.history, overlay.filter, 50, overlay.formatTime) : []
    readonly property var current: overlay.rows.length > 0 ? overlay.rows[Math.min(overlay.selected, overlay.rows.length - 1)] : null

    // Images are decoded at the size they are drawn, in device pixels, not
    // at whatever size the screenshot was taken.
    readonly property real dpr: overlay.screen ? overlay.screen.devicePixelRatio : 1

    function formatTime(ms) {
        return Qt.formatDateTime(new Date(ms), "ddd HH:mm");
    }

    onVisibleChanged: {
        if (!visible)
            return;
        overlay.filter = "";
        overlay.selected = 0;
        overlay.confirming = "";
        pointerGate.reset();
        list.positionViewAtBeginning();
        keys.forceActiveFocus();
    }

    // A new copy landing, or a delete, can leave the cursor past the end.
    onRowsChanged: {
        if (overlay.selected >= overlay.rows.length)
            overlay.selected = Math.max(0, overlay.rows.length - 1);
    }

    function setFilter(text) {
        overlay.filter = text;
        overlay.selected = 0;
        pointerGate.reset();
        list.positionViewAtBeginning();
    }

    // Wraps on single steps, as Omarchy's does; a page or Home/End stops at
    // the edge, because overshooting a page and landing back at the top is
    // never what anyone meant.
    function move(delta, wrap) {
        const n = overlay.rows.length;
        if (n === 0)
            return;
        pointerGate.reset();
        const next = overlay.selected + delta;
        overlay.selected = wrap ? (next + n) % n : Math.max(0, Math.min(n - 1, next));
        list.positionViewAtIndex(overlay.selected, ListView.Contain);
    }

    function activate(copyOnly) {
        if (overlay.current)
            Clipboard.paste(overlay.current.index, copyOnly);
    }

    function removeSelected() {
        if (!overlay.current)
            return;
        if (overlay.current.pinned) {
            overlay.forgetKey = History.entryKey(Clipboard.history[overlay.current.index]);
            overlay.ask("forget");
            return;
        }
        Clipboard.remove(overlay.current.index);
        pointerGate.reset();
    }

    function requestClear() {
        if (Clipboard.history.length === Clipboard.pinnedCount)
            return;
        overlay.ask("clear");
    }

    // Cancel first, the PowerMenu rule: Return on a destructive question
    // must not answer it before anyone has read the sentence.
    function ask(what) {
        confirm.selectedIndex = 0;
        overlay.confirming = what;
    }

    function historyIndexOf(key) {
        for (var i = 0; i < Clipboard.history.length; i++) {
            if (History.entryKey(Clipboard.history[i]) === key)
                return i;
        }
        return -1;
    }

    // The cursor goes with the entry, which pinning moves to the end of the
    // pins and unpinning to the top of the rest -- otherwise Ctrl+P twice
    // would toggle two different entries.
    function togglePin() {
        if (!overlay.current)
            return;
        const key = History.entryKey(Clipboard.history[overlay.current.index]);
        Clipboard.togglePin(overlay.current.index);
        const at = overlay.historyIndexOf(key);
        for (var i = 0; i < overlay.rows.length; i++) {
            if (overlay.rows[i].index === at) {
                overlay.selected = i;
                list.positionViewAtIndex(i, ListView.Contain);
                break;
            }
        }
        pointerGate.reset();
    }

    // ------------------------------------------------------------ drawing

    Rectangle {
        anchors.fill: parent
        color: Commons.Color.menu.scrim
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (overlay.confirming !== "") {
                confirm.handleKey(event);
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_P && event.modifiers === Qt.ControlModifier) {
                overlay.togglePin();
                event.accepted = true;
                return;
            }

            const shift = event.modifiers & Qt.ShiftModifier;
            // Printable text goes to the filter; control characters and
            // Ctrl/Alt chords do not.
            const t = event.text;
            const printable = t && t.length === 1 && t.charCodeAt(0) >= 32 && t.charCodeAt(0) !== 127 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
            switch (event.key) {
            case Qt.Key_Escape:
                if (overlay.filter !== "")
                    overlay.setFilter("");
                else
                    Clipboard.close();
                break;
            case Qt.Key_Up:
                overlay.move(-1, true);
                break;
            case Qt.Key_Down:
                overlay.move(1, true);
                break;
            case Qt.Key_PageUp:
                overlay.move(-6, false);
                break;
            case Qt.Key_PageDown:
                overlay.move(6, false);
                break;
            case Qt.Key_Home:
                overlay.move(-overlay.rows.length, false);
                break;
            case Qt.Key_End:
                overlay.move(overlay.rows.length, false);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                overlay.activate(shift);
                break;
            case Qt.Key_Delete:
                if (shift)
                    overlay.requestClear();
                else
                    overlay.removeSelected();
                break;
            default:
                if (Util.editsFilter(event, overlay.filter)) {
                    overlay.setFilter(Util.editedFilter(event, overlay.filter));
                    break;
                }
                if (printable) {
                    overlay.setFilter(overlay.filter + t);
                    break;
                }
                return;
            }
            event.accepted = true;
        }

        // Anywhere off the card closes it, the way out every pshell overlay
        // offers the mouse.
        MouseArea {
            anchors.fill: parent
            onClicked: Clipboard.close()
        }

        BorderSurface {
            id: card

            anchors.centerIn: parent
            width: Math.min(Style.space(875), parent.width - Style.gapsOut * 2)
            height: Math.min(Style.space(600), parent.height - Style.gapsOut * 2)
            radius: Style.cornerRadius
            color: Commons.Color.menu.background
            borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.normalBorderWidth))
            padding: Style.spacing.panelPadding

            // Swallows clicks on the card, so only the scrim closes it.
            MouseArea {
                anchors.fill: parent
            }

            PointerMoveGate {
                id: pointerGate
                referenceItem: card
            }

            Item {
                id: content

                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset

                // The filter, or what typing does when there is none. No
                // TextField: every key already lands in the handler above,
                // and a second focus owner is how Escape ends up eaten.
                Text {
                    id: header

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Math.round(Style.font.heading * 2)
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: overlay.filter !== "" ? overlay.filter : "Type to search the clipboard"
                    color: overlay.filter !== "" ? Commons.Color.menu.text : Commons.Color.muted
                    elide: Text.ElideLeft
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                }

                Text {
                    id: footer

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    textFormat: Text.PlainText
                    text: "Enter paste      Shift+Enter copy      Ctrl+P pin      Del forget      Shift+Del forget all      Esc close"
                    color: Commons.Color.muted
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

                Item {
                    id: body

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: header.bottom
                    anchors.topMargin: Style.spacing.md
                    anchors.bottom: footer.top
                    anchors.bottomMargin: Style.spacing.md

                    ListView {
                        id: list

                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.round(parent.width / 2) - Style.spacing.panelPadding
                        model: overlay.rows
                        clip: true
                        spacing: Style.spacing.xs
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: CursorSurface {
                            id: row

                            required property var modelData
                            required property int index

                            // Sized from the data and the decode, never from
                            // the thumbnail's own visibility: binding a slot
                            // to a child's `visible` is a binding loop
                            // waiting for its first layout pass. A file
                            // copied from a file manager may since have
                            // moved, and then there is no picture to leave
                            // room for.
                            readonly property bool hasImage: row.modelData.previewImage !== "" && thumbnail.status !== Image.Error
                            readonly property int thumb: row.height - Style.spacing.md * 2

                            width: ListView.view.width
                            height: Math.round(Style.font.body * 2.6)
                            foreground: Commons.Color.menu.text
                            hasCursor: index === overlay.selected

                            Image {
                                id: thumbnail

                                anchors.left: parent.left
                                anchors.leftMargin: Style.spacing.rowPaddingX
                                anchors.verticalCenter: parent.verticalCenter
                                width: row.hasImage ? row.thumb : 0
                                height: row.thumb
                                visible: row.hasImage
                                source: row.modelData.previewImage !== "" ? Util.fileUrl(row.modelData.previewImage) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                sourceSize.width: Math.ceil(row.thumb * overlay.dpr)
                                sourceSize.height: Math.ceil(row.thumb * overlay.dpr)
                            }

                            Text {
                                anchors.left: thumbnail.right
                                anchors.leftMargin: row.hasImage ? Style.spacing.lg : 0
                                anchors.right: pinMark.left
                                anchors.rightMargin: row.modelData.pinned ? Style.spacing.md : 0
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: row.modelData.previewText
                                // Images and files are labels, not content,
                                // and read a step quieter than copied text.
                                color: row.hasCursor ? Commons.Color.menu.selectedText : (row.modelData.entryType === "text" ? Commons.Color.menu.text : Commons.Color.muted)
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                            }

                            // Sized from the row's data, not from its own
                            // visibility, for the thumbnail's reason.
                            MaterialIcon {
                                id: pinMark

                                anchors.right: parent.right
                                anchors.rightMargin: Style.spacing.rowPaddingX
                                anchors.verticalCenter: parent.verticalCenter
                                width: row.modelData.pinned ? implicitWidth : 0
                                visible: row.modelData.pinned
                                name: Glyphs.pin
                                filled: true
                                size: Style.font.body
                                color: row.hasCursor ? Commons.Color.menu.selectedText : Commons.Color.muted
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Only a pointer that actually moved takes
                                // the cursor, so a list scrolling under a
                                // resting mouse does not steal it from the
                                // arrow keys.
                                onPositionChanged: mouse => {
                                    if (pointerGate.moved(row, mouse))
                                        overlay.selected = row.index;
                                }
                                onClicked: {
                                    overlay.selected = row.index;
                                    overlay.activate(false);
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: divider

                        anchors.left: list.right
                        anchors.leftMargin: Style.spacing.panelPadding / 2
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Style.normalBorderWidth
                        color: Util.alpha(Commons.Color.menu.border, 0.28)
                        visible: overlay.rows.length > 0
                    }

                    // The selected entry in full -- or its first 8 KiB, which
                    // is all the panel ever holds -- or the image at the size
                    // the pane allows.
                    Item {
                        id: preview

                        anchors.left: divider.right
                        anchors.leftMargin: Style.spacing.panelPadding / 2
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        clip: true

                        readonly property string image: overlay.current ? overlay.current.previewImage : ""
                        // The row's reason, again: a path that no longer
                        // decodes falls back to showing the path.
                        readonly property bool showsImage: preview.image !== "" && bigImage.status !== Image.Error

                        Text {
                            anchors.fill: parent
                            visible: overlay.current !== null && !preview.showsImage
                            textFormat: Text.PlainText
                            text: overlay.current ? overlay.current.fullText : ""
                            color: Commons.Color.menu.text
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignTop
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }

                        Image {
                            id: bigImage

                            anchors.fill: parent
                            visible: preview.showsImage
                            source: preview.image !== "" ? Util.fileUrl(preview.image) : ""
                            // Shrunk to fit, never blown up past its own
                            // size: a copied icon stretched across half the
                            // card is a blur, not a preview.
                            fillMode: implicitWidth > width || implicitHeight > height ? Image.PreserveAspectFit : Image.Pad
                            horizontalAlignment: Image.AlignLeft
                            verticalAlignment: Image.AlignTop
                            asynchronous: true
                            smooth: true
                            sourceSize.width: Math.ceil(preview.width * overlay.dpr)
                            sourceSize.height: Math.ceil(preview.height * overlay.dpr)
                        }
                    }

                    // Nothing to list: say whether that is an empty history,
                    // a filter that matches nothing, or recording switched
                    // off -- a blank card looks broken in all three.
                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Style.spacing.md
                        visible: overlay.rows.length === 0

                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "content_paste"
                            size: Style.font.displayLarge
                            color: Commons.Color.muted
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            text: {
                                if (overlay.filter !== "")
                                    return "Nothing matches “" + overlay.filter + "”";
                                if (!Clipboard.recording)
                                    return "Clipboard history is off: clipboard.historySize is 0 in config.json.";
                                return "Nothing copied yet. Copies show up here as you make them.";
                            }
                            color: Commons.Color.menu.text
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }
                    }
                }
            }

            ConfirmDialog {
                id: confirm

                anchors.fill: parent
                z: 10
                opened: overlay.confirming !== ""
                message: {
                    if (overlay.confirming === "forget")
                        return "Forget this pinned copy? It was pinned to keep it.";
                    const rolling = Clipboard.history.length - Clipboard.pinnedCount;
                    return "Forget all " + rolling + " copies? Images saved with them are deleted too." + (Clipboard.pinnedCount > 0 ? " Pinned copies are kept." : "");
                }
                confirmText: overlay.confirming === "forget" ? "Forget" : "Forget all"
                background: Commons.Color.menu.background
                foreground: Commons.Color.menu.text
                scrim: Commons.Color.menu.scrim
                selectedBackground: Commons.Color.menu.selectedBackground
                selectedText: Commons.Color.menu.selectedText
                fontFamily: Style.font.family
                cornerRadius: Style.cornerRadius

                onCanceled: overlay.confirming = ""
                onConfirmed: {
                    const what = overlay.confirming;
                    overlay.confirming = "";
                    if (what === "clear") {
                        Clipboard.clear();
                        return;
                    }
                    const at = overlay.historyIndexOf(overlay.forgetKey);
                    if (at >= 0)
                        Clipboard.remove(at);
                    pointerGate.reset();
                }
            }
        }
    }
}
