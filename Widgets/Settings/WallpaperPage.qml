import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The wallpaper picker: every image in Config.wallpaperDir as a thumbnail
// (cached ones, from Wallpaper.thumbs), the one on screen marked. Clicking
// one goes through Wallpaper.set(), so a click here is the same single
// config write as `pshell wallpaper set` and the palette re-derives with it.
//
// Pages, not a scrolling column. The grid used to scroll with the rest of
// the page, and a directory of forty images was a long way down past two
// paragraphs of help. Now the grid is cut into pages that exactly fill the
// pane, and a page is one wheel notch, one swipe or one key away. The shape
// is DankMaterialShell's wallpaper tab (MIT): a horizontal ListView that
// snaps one page at a time, each page a fixed grid, and arrow keys that walk
// off the edge of a page onto the next. The code is pshell's own.
SettingsPage {
    id: page

    title: "Wallpaper"
    scrolls: false

    // ------------------------------------------------------------ geometry
    //
    // Four across, whatever the window width -- a fixed thumbnail size would
    // leave a ragged right edge on wide windows and overflow narrow ones.
    readonly property int columns: 4
    readonly property int gap: Style.spacing.lg
    readonly property int toolbarGap: Style.spacing.lg
    readonly property int footerHeight: Style.space(26)

    // The keyboard ring sits outside its cell, so each page keeps this much
    // room around its grid. The pager clips (it has to, or the neighbouring
    // pages would show), and a ring drawn to the clip edge would lose a side.
    readonly property int ringWidth: 2
    readonly property int ringOut: Style.spacing.xxs + ringWidth

    readonly property int count: Wallpaper.entries.length
    readonly property int innerWidth: Math.max(0, pager.width - 2 * ringOut)
    readonly property int cellWidth: Math.max(1, Math.floor((innerWidth - (columns - 1) * gap) / columns))
    // Whatever floor() left over, split either side, so the grid is centred
    // rather than a few pixels short on the right.
    readonly property int gridX: ringOut + Math.floor((innerWidth - (columns * cellWidth + (columns - 1) * gap)) / 2)

    // Rows are counted from a true 16:9 cell and then stretched to fill the
    // height exactly, so there is never a half row cut off at the bottom or
    // a strip of dead space under the last one. round(), not floor(): the
    // stretch is then never more than half a row either way, which keeps the
    // cells close to 16:9 at any window height. Two rows at least, or a
    // short window would page one row at a time.
    //
    // The footer only exists when there is more than one page, and whether
    // there is depends on how many rows fit -- so both cases are worked out
    // here from the body height alone, rather than from the grid area, whose
    // height depends on the footer. Reading the grid area would be a binding
    // loop.
    readonly property real _nominalHeight: cellWidth * 9 / 16
    readonly property real _heightNoFooter: bodyHeight - toolbar.height - toolbarGap - 2 * ringOut
    readonly property int _rowsNoFooter: _fit(_heightNoFooter)
    readonly property bool paged: count > columns * _rowsNoFooter
    readonly property real gridHeight: paged ? _heightNoFooter - footerHeight : _heightNoFooter
    readonly property int rows: paged ? _fit(gridHeight) : _rowsNoFooter
    readonly property int cellHeight: Math.max(1, Math.floor((gridHeight - (rows - 1) * gap) / rows))
    readonly property int perPage: columns * rows
    readonly property int pageCount: count === 0 ? 0 : Math.ceil(count / perPage)

    function _fit(height) {
        return Math.max(2, Math.round((height + gap) / (_nominalHeight + gap)));
    }

    // --------------------------------------------------------------- state
    //
    // `shown` is the page on screen and `cursor` the keyboard selection, as
    // an index into Wallpaper.entries. The cursor is always on the shown
    // page: every way of turning a page carries it along, so a resize can
    // find the page again from the cursor alone.
    property int shown: 0
    property int cursor: 0

    // The keyboard ring appears once a key is used and goes again when the
    // mouse moves, the way a browser's focus-visible does. Shown all the
    // time it would sit on the current wallpaper from the moment the page
    // opens, doubling the accent ring for no reason.
    property bool keyboardUsed: false
    property point _lastPointer: Qt.point(-1, -1)

    property bool _animate: true
    property real _wheelAccumulator: 0
    property bool _swipeSpent: false

    property bool editingDir: false
    property bool _cancelEdit: false

    readonly property string dirLabel: tildePath(Config.wallpaperDir)

    function tildePath(path) {
        const home = Quickshell.env("HOME");
        const p = String(path || "");
        if (home && (p === home || p.startsWith(home + "/")))
            return "~" + p.substring(home.length);
        return p;
    }

    function itemsOn(p) {
        return Math.max(0, Math.min(perPage, count - p * perPage));
    }

    // Instant for opening and resizing, where a slide would read as the page
    // lurching; animated, by the pager's own snap motion, for a page turn.
    function showPage(p, animated) {
        if (pageCount === 0)
            return;
        p = Math.max(0, Math.min(pageCount - 1, p));
        shown = p;
        if (animated) {
            pager.currentIndex = p;
            return;
        }
        _animate = false;
        pager.currentIndex = p;
        pager.positionViewAtIndex(p, ListView.Beginning);
        _animate = true;
    }

    // A page turn keeps the cursor in the same slot, or on the last image if
    // the new page is short of that slot. Jumping it to the first cell would
    // make PageDown, PageUp a round trip that loses your place.
    function turnTo(p) {
        if (pageCount === 0 || p < 0 || p >= pageCount)
            return;
        const slot = Math.max(0, cursor - shown * perPage);
        cursor = p * perPage + Math.min(slot, itemsOn(p) - 1);
        showPage(p, true);
    }

    function select(index) {
        if (count === 0)
            return;
        cursor = index;
        keyboardUsed = true;
        const p = Math.floor(index / perPage);
        if (p !== shown)
            showPage(p, true);
    }

    function apply(index) {
        if (index < 0 || index >= count)
            return;
        cursor = index;
        Wallpaper.set(Wallpaper.entries[index]);
    }

    // Open on the page holding the wallpaper that is up, cursor on it.
    function sync() {
        cursor = Math.max(0, Wallpaper.entries.indexOf(Wallpaper.current));
        keyboardUsed = false;
        reposition();
        if (!editingDir)
            keys.forceActiveFocus();
    }

    // After a resize or a rescan: the page count and size have changed under
    // the cursor, so find its page again and put the view there at once.
    function reposition() {
        if (count === 0) {
            cursor = 0;
            shown = 0;
            return;
        }
        cursor = Math.min(cursor, count - 1);
        showPage(Math.floor(cursor / perPage), false);
    }

    // The Up and Down rules are DMS's: off the bottom row onto the same
    // column of the next page, off the top onto the last row of the one
    // before, and round from the last page to the first. Left and Right just
    // walk the list, which crosses pages the same way.
    function step(key) {
        const n = count;
        const p = Math.floor(cursor / perPage);
        const slot = cursor - p * perPage;
        const col = slot % columns;
        const onPage = itemsOn(p);
        const lastRow = Math.ceil(onPage / columns) - 1;

        switch (key) {
        case Qt.Key_Left:
        case Qt.Key_H:
            select((cursor - 1 + n) % n);
            return;
        case Qt.Key_Right:
        case Qt.Key_L:
            select((cursor + 1) % n);
            return;
        case Qt.Key_Down:
        case Qt.Key_J:
            if (Math.floor(slot / columns) < lastRow) {
                select(p * perPage + Math.min(slot + columns, onPage - 1));
            } else if (pageCount > 1) {
                const np = (p + 1) % pageCount;
                select(np * perPage + Math.min(col, itemsOn(np) - 1));
            }
            return;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (slot >= columns) {
                select(cursor - columns);
            } else if (pageCount > 1) {
                const pp = (p - 1 + pageCount) % pageCount;
                const c = itemsOn(pp);
                const ppLastRow = Math.ceil(c / columns) - 1;
                select(pp * perPage + Math.min(ppLastRow * columns + col, c - 1));
            }
            return;
        }
    }

    // A click on the chip swaps it for a field in place. No form section and
    // no help paragraph: the folder icon and the path say what it is.
    function beginEdit() {
        _cancelEdit = false;
        dirField.text = Config.data.wallpaperDir || "~/wallpapers";
        editingDir = true;
        dirField.forceActiveFocus();
        dirField.selectAll();
    }

    function finishEdit() {
        if (!editingDir)
            return;
        // editingFinished fires on every focus loss, changed or not, and an
        // unchanged write would still rewrite config.json and rescan the
        // directory for nothing. It also fires a second time when focus
        // leaves the field after Enter, which the guard above swallows.
        if (!_cancelEdit && dirField.text !== (Config.data.wallpaperDir || "~/wallpapers"))
            Config.set("wallpaperDir", dirField.text);
        editingDir = false;
        keys.forceActiveFocus();
    }

    Component.onCompleted: Qt.callLater(page.sync)
    onPerPageChanged: Qt.callLater(page.reposition)

    Connections {
        target: Wallpaper

        // A new directory, or a rescan: start again from the wallpaper that
        // is up.
        function onEntriesChanged() {
            Qt.callLater(page.sync);
        }
    }

    // The window is hidden, not destroyed, so this page can outlive a close.
    // Reopening it should land on the current wallpaper like a fresh open.
    Connections {
        target: SettingsApp

        function onVisibleChanged() {
            if (SettingsApp.visible)
                Qt.callLater(page.sync);
        }
    }

    Item {
        id: keys

        width: parent.width
        height: page.bodyHeight
        focus: true

        Keys.onPressed: event => {
            // Keys the directory field leaves unhandled bubble up to here;
            // Up and Down in a text field must not move the grid.
            if (page.editingDir || page.count === 0)
                return;
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right:
            case Qt.Key_Up:
            case Qt.Key_Down:
            case Qt.Key_H:
            case Qt.Key_J:
            case Qt.Key_K:
            case Qt.Key_L:
                page.step(event.key);
                break;
            case Qt.Key_PageDown:
                page.keyboardUsed = true;
                page.turnTo((page.shown + 1) % page.pageCount);
                break;
            case Qt.Key_PageUp:
                page.keyboardUsed = true;
                page.turnTo((page.shown - 1 + page.pageCount) % page.pageCount);
                break;
            case Qt.Key_Home:
                page.select(0);
                break;
            case Qt.Key_End:
                page.select(page.count - 1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                page.apply(page.cursor);
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // ---------------------------------------------------------- toolbar

        Item {
            id: toolbar

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: dirField.implicitHeight

            // The directory, shortened to ~ and elided in the middle, where a
            // long path keeps both the root you recognise and the folder name
            // that matters. A Button so it hovers like every other control.
            Button {
                id: dirChip

                readonly property real textMax: toolbar.width - actions.width - Style.spacing.lg - 2 * horizontalPadding - folderIcon.width - editIcon.width - 2 * chipRow.spacing

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !page.editingDir
                height: toolbar.height
                width: chipRow.implicitWidth + 2 * horizontalPadding
                tooltipText: "Change directory"
                onClicked: page.beginEdit()

                Row {
                    id: chipRow

                    x: dirChip.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.md

                    MaterialIcon {
                        id: folderIcon

                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.folder
                        size: Math.round(Style.font.body * 1.1)
                        color: Commons.Color.muted
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, Math.min(implicitWidth, dirChip.textMax))
                        text: page.dirLabel
                        elide: Text.ElideMiddle
                        color: Commons.Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }

                    // A pencil, not a dropdown arrow: the chip turns into a
                    // text field, it does not open a list.
                    MaterialIcon {
                        id: editIcon

                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.edit
                        size: Style.font.bodySmall
                        color: Commons.Color.muted
                    }
                }
            }

            // Enter or clicking away saves; Escape puts the chip back as it
            // was.
            TextField {
                id: dirField

                anchors.left: parent.left
                anchors.right: actions.left
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                visible: page.editingDir
                onEditingFinished: page.finishEdit()

                Keys.onEscapePressed: {
                    page._cancelEdit = true;
                    page.finishEdit();
                }
            }

            Row {
                id: actions

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                PanelActionButton {
                    size: toolbar.height
                    tooltipText: "Shuffle"
                    enabled: page.count > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: Wallpaper.random()

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: Glyphs.shuffle
                        size: Style.font.icon
                        color: Commons.Color.foreground
                    }
                }

                // The grid's fullscreen sibling, one click away. The carousel
                // is not a mode of this page -- it is its own overlay
                // surface, because it wants the whole screen and an exclusive
                // keyboard grab, which a page inside an xdg toplevel cannot
                // have. It opens over this window, and Escape lands you back
                // here. Disabled, not hidden, on an empty directory, so it
                // reads as "nothing to browse" rather than a removed feature.
                PanelActionButton {
                    size: toolbar.height
                    tooltipText: "Carousel"
                    enabled: page.count > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: WallpaperCarousel.open()

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: Glyphs.carousel
                        size: Style.font.icon
                        color: Commons.Color.foreground
                    }
                }
            }
        }

        // ------------------------------------------------------------- grid

        Item {
            id: gridArea

            anchors.top: toolbar.bottom
            anchors.topMargin: page.toolbarGap
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top

            // A sentence, not a blank pane: an empty grid looks like the
            // picker is broken, and naming the directory makes the fix
            // obvious.
            Text {
                anchors.centerIn: parent
                width: parent.width
                visible: page.count === 0
                text: "No images in " + page.dirLabel
                color: Commons.Color.muted
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            ListView {
                id: pager

                anchors.fill: parent
                orientation: ListView.Horizontal
                model: page.pageCount

                // One page per screen, and a drag or flick always comes to
                // rest on one. The page turn is the view's own snap motion,
                // fixed at 150ms so a wrap from the last page to the first
                // is no slower than the next page over, and quick enough that
                // a run of wheel notches does not queue up behind it.
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: width
                highlightMoveDuration: page._animate ? 150 : 0
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                keyNavigationEnabled: false
                activeFocusOnTab: false

                // The pages either side are built ahead, so a swipe slides
                // in thumbnails rather than empty plates.
                cacheBuffer: Math.max(0, Math.round(width))

                // A drag moves currentIndex as it goes; follow it so the dots
                // and the cursor keep up with the finger.
                onCurrentIndexChanged: {
                    if (!moving || currentIndex < 0 || currentIndex === page.shown)
                        return;
                    const slot = Math.max(0, page.cursor - page.shown * page.perPage);
                    page.cursor = currentIndex * page.perPage + Math.min(slot, page.itemsOn(currentIndex) - 1);
                    page.shown = currentIndex;
                }

                onCountChanged: Qt.callLater(page.reposition)
                onWidthChanged: Qt.callLater(page.reposition)
                onHeightChanged: Qt.callLater(page.reposition)

                // One page per wheel notch, at once. Each notch retargets the
                // view from wherever the last turn's slide has got to, so a
                // quick spin is never held back waiting for it to settle. A
                // high resolution wheel's small events add up to 120 a notch
                // and the remainder carries over, so eight of them turn one
                // page and not eight.
                //
                // A touchpad (it reports pixel deltas too) is one page per
                // flick instead. Its deltas arrive as a stream for as long as
                // the fingers move, so a third of a notch is enough to turn,
                // and then the rest of that flick is ignored -- summing it
                // would fly through the directory on a single gesture.
                WheelHandler {
                    target: null
                    onWheel: event => {
                        const d = Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x) ? event.angleDelta.y : event.angleDelta.x;
                        const touchpad = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
                        let steps = 0;
                        if (touchpad) {
                            swipeQuiet.restart();
                            if (page._swipeSpent)
                                return;
                            page._wheelAccumulator += d;
                            if (Math.abs(page._wheelAccumulator) < 40)
                                return;
                            steps = page._wheelAccumulator;
                            page._wheelAccumulator = 0;
                            page._swipeSpent = true;
                        } else {
                            const r = Util.wheelSteps(page._wheelAccumulator, d);
                            page._wheelAccumulator = r.remainder;
                            steps = r.steps;
                        }
                        if (steps === 0)
                            return;
                        // Down and right are forward. No wrap: the wheel
                        // stops at the ends, where the keys go round.
                        page.turnTo(page.shown + (steps < 0 ? 1 : -1));
                    }
                }

                // 150ms with no input ends a flick: the next movement is a
                // new one.
                Timer {
                    id: swipeQuiet

                    interval: 150
                    onTriggered: {
                        page._swipeSpent = false;
                        page._wheelAccumulator = 0;
                    }
                }

                delegate: Item {
                    id: pageItem

                    required property int index

                    readonly property int start: index * page.perPage

                    width: pager.width
                    height: pager.height

                    Repeater {
                        model: Wallpaper.entries.slice(pageItem.start, pageItem.start + page.perPage)

                        Item {
                            id: thumb

                            required property var modelData
                            required property int index

                            readonly property int flat: pageItem.start + index
                            readonly property bool current: modelData === Wallpaper.current
                            readonly property bool hasCursor: page.keyboardUsed && keys.activeFocus && page.cursor === thumb.flat
                            readonly property bool hovered: cellMouse.containsMouse === true && !page.keyboardUsed

                            x: page.gridX + (index % page.columns) * (page.cellWidth + page.gap)
                            y: page.ringOut + Math.floor(index / page.columns) * (page.cellHeight + page.gap)
                            width: page.cellWidth
                            height: page.cellHeight

                            // Under the image until it is ready, the
                            // carousel's plate: a faint shape reads as
                            // "loading" where an empty cell reads as a
                            // missing file.
                            Rectangle {
                                anchors.fill: parent
                                color: Util.alpha(Commons.Color.foreground, 0.06)
                                radius: Style.cornerRadius
                            }

                            // The cached 640x360 copy from Wallpaper.thumbs,
                            // never the original. Decoding a directory of 4K
                            // PNGs here, even with a small sourceSize, queued
                            // them all on Qt's single image thread -- most of
                            // twenty seconds for this grid, paid again on
                            // every visit, because the settings window
                            // rebuilds the page each time its tab is chosen.
                            // The thumbnails are made once, in parallel, by
                            // Services/wallpaper-thumbs.sh, and load near
                            // instantly. Until one exists the plate shows.
                            Image {
                                id: image

                                readonly property string cached: Wallpaper.thumb(thumb.modelData)

                                anchors.fill: parent
                                source: image.cached !== "" ? "file://" + image.cached : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // Faded in rather than popped, so a page of
                                // cells filling in over a cold first scan
                                // reads as one motion, not flicker.
                                opacity: image.status === Image.Ready ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 150
                                    }
                                }
                            }

                            // The mark for "this one is on screen": an accent
                            // border, which is how the sidebar says "current"
                            // too -- accent chrome, never a second fill
                            // fighting the image.
                            BorderSurface {
                                anchors.fill: parent
                                color: "transparent"
                                radius: Style.cornerRadius
                                borderSpec: thumb.current ? Border.flat(Commons.Color.accent, 2) : (thumb.hovered ? Border.flat(Commons.Color.foreground, 1) : Border.none())
                            }

                            // And a check in the corner, because on a
                            // monochrome palette the accent ring alone is
                            // hard to tell from the keyboard's.
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: Style.spacing.md
                                visible: thumb.current
                                width: Style.space(18)
                                height: width
                                radius: width / 2
                                color: Commons.Color.accent

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: Glyphs.check
                                    size: Style.font.bodySmall
                                    color: Commons.Color.background
                                }
                            }

                            // The file's name, only for the cell being
                            // pointed at. On every cell it would be a page of
                            // captions over the pictures you came to look at.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Style.spacing.sm
                                visible: thumb.hovered || thumb.hasCursor
                                height: fileName.implicitHeight + 2 * Style.spacing.xs
                                radius: Style.cornerRadius
                                color: Util.alpha(Commons.Color.background, 0.75)

                                Text {
                                    id: fileName

                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: Style.spacing.md
                                    anchors.rightMargin: Style.spacing.md
                                    text: String(thumb.modelData).split("/").pop().replace(/\.[^.]+$/, "")
                                    elide: Text.ElideMiddle
                                    color: Commons.Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }
                            }

                            // The keyboard cursor: foreground, and outside
                            // the cell with a gap, so it never looks like the
                            // accent ring that means "on screen" -- the two
                            // can sit on the same cell and both still read.
                            BorderSurface {
                                anchors.fill: parent
                                anchors.margins: -page.ringOut
                                visible: thumb.hasCursor
                                color: "transparent"
                                radius: Style.cornerRadius + page.ringOut
                                borderSpec: Border.flat(Commons.Color.foreground, page.ringWidth)
                            }

                            MouseArea {
                                id: cellMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    page.keyboardUsed = false;
                                    page.apply(thumb.flat);
                                    keys.forceActiveFocus();
                                }
                                // Only a pointer that really moved hands the
                                // highlight back to the mouse. A page turned
                                // under a still pointer sends hover events
                                // too, and those must not wipe the keyboard
                                // ring the turn was made with.
                                onPositionChanged: mouse => {
                                    const at = mapToItem(keys, mouse.x, mouse.y);
                                    if (at.x !== page._lastPointer.x || at.y !== page._lastPointer.y) {
                                        if (page._lastPointer.x >= 0)
                                            page.keyboardUsed = false;
                                        page._lastPointer = Qt.point(at.x, at.y);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------------- footer
        //
        // Where you are, and a way to jump. Gone entirely on a single page,
        // where it would only say "1 / 1".
        Item {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: page.paged ? page.footerHeight : 0
            visible: page.paged

            // The arrows wrap, the same as PageUp and PageDown: from the
            // last page, next is the first.
            Row {
                anchors.centerIn: parent
                spacing: Style.spacing.sm

                PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: footer.height
                    tooltipText: "Previous page"
                    onClicked: {
                        page.turnTo((page.shown - 1 + page.pageCount) % page.pageCount);
                        keys.forceActiveFocus();
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: Glyphs.previous
                        size: Style.font.icon
                        color: Commons.Color.foreground
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    // A huge directory would push the dots under the counter;
                    // the arrows and the counter are enough then.
                    visible: implicitWidth <= footer.width - 2 * (counter.implicitWidth + Style.spacing.lg + footer.height + Style.spacing.sm)

                    Repeater {
                        model: page.pageCount

                        Item {
                            id: dot

                            required property int index

                            width: Style.space(14)
                            height: footer.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: Style.space(6)
                                height: width
                                radius: width / 2
                                color: dot.index === page.shown ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, dotMouse.containsMouse ? 0.5 : 0.25)
                            }

                            MouseArea {
                                id: dotMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    page.turnTo(dot.index);
                                    keys.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: footer.height
                    tooltipText: "Next page"
                    onClicked: {
                        page.turnTo((page.shown + 1) % page.pageCount);
                        keys.forceActiveFocus();
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: Glyphs.next
                        size: Style.font.icon
                        color: Commons.Color.foreground
                    }
                }
            }

            Text {
                id: counter

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (page.shown + 1) + " / " + page.pageCount
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }
}
