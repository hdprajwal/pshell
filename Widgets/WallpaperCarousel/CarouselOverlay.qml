import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The carousel itself: one row of big cards over a scrim, arrows to browse,
// Enter to apply, Escape to leave with nothing changed.
//
// Its own directory rather than Widgets/Wallpaper, because of the collision
// shell.qml already records: a file in that module would resolve `Wallpaper`
// to its sibling widget, shadowing the qs.Services singleton this file calls
// set() on. A one-file module is cheaper than qualifying every reference.
//
// Browsing here previews nothing on the desktop, and that is a decision, not
// a gap. Wallpaper.set() is the only way to change the wallpaper, and every
// set() re-runs matugen and rewrites every theme template -- a live preview
// would do that once per arrow press. The upstream plugin this is modelled
// on made the same call: highlight freely, commit once.
PanelWindow {
    id: overlay

    screen: WallpaperCarousel.screen
    visible: WallpaperCarousel.visible
    color: "transparent"

    WlrLayershell.namespace: "pshell:wallpaper-carousel"
    // Overlay rather than Top: the point of a fullscreen picker is to appear
    // over whatever is up, including a fullscreen window.
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive while mapped, so Escape works no matter which window the
    // compositor thinks has focus. Unmapped, the grab does not exist.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // Covers the screen without claiming it -- the same trap the wallpaper
    // window documents: an anchored layer surface reserves what it covers
    // by default, and this one covers everything.
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // A third of the screen per card: the highlighted image is big enough to
    // judge, and both neighbours stay on screen so "next" is a place you can
    // see, not a guess.
    readonly property int cardWidth: Math.round(width * 0.34)
    readonly property int cardHeight: Math.round(cardWidth * 9 / 16)

    onVisibleChanged: {
        if (visible)
            sync();
    }

    // Open on the wallpaper that is up, positioned instantly.
    // positionViewAtIndex rather than letting StrictlyEnforceRange animate
    // there: on open the view is wherever it was left, and a 250ms sweep
    // across the whole directory reads as the overlay lurching, not opening.
    function sync() {
        const at = Wallpaper.entries.indexOf(Wallpaper.current);
        list.currentIndex = Math.max(0, at);
        list.positionViewAtIndex(list.currentIndex, ListView.Center);
        keys.forceActiveFocus();
    }

    // Arrows wrap. A directory is a ring when you are flipping through it --
    // hitting a wall at the last file makes "keep going" a dead key -- and
    // Wallpaper._step() already cycles for the same reason.
    function step(delta) {
        const n = Wallpaper.entries.length;
        if (n === 0)
            return;
        list.currentIndex = (list.currentIndex + delta + n) % n;
    }

    function apply(index) {
        if (index >= 0 && index < Wallpaper.entries.length)
            Wallpaper.set(Wallpaper.entries[index]);
        // Closed immediately: the crossfade the background window runs is
        // the confirmation, and the scrim would only hide it.
        WallpaperCarousel.close();
    }

    // Scrim, not blackout: enough of the desktop's colour survives that the
    // overlay reads as part of the session, and the cards stay the brightest
    // thing on screen.
    Rectangle {
        anchors.fill: parent
        color: Util.alpha(Commons.Color.background, 0.85)
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                WallpaperCarousel.close();
                break;
            case Qt.Key_Left:
            case Qt.Key_H:
                overlay.step(-1);
                break;
            case Qt.Key_Right:
            case Qt.Key_L:
                overlay.step(1);
                break;
            case Qt.Key_Home:
                if (Wallpaper.entries.length > 0)
                    list.currentIndex = 0;
                break;
            case Qt.Key_End:
                if (Wallpaper.entries.length > 0)
                    list.currentIndex = Wallpaper.entries.length - 1;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                overlay.apply(list.currentIndex);
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // Anywhere off a card is the way out for the mouse, the same
        // exit-by-defocus every panel popout offers. Declared before the
        // list so the cards sit above it and take their clicks first.
        MouseArea {
            anchors.fill: parent
            onClicked: WallpaperCarousel.close()
        }

        // The wheel moves the highlight one card per notch, never the view
        // directly -- the same model as the keys, so the two inputs cannot
        // disagree about what "current" means.
        WheelHandler {
            onWheel: event => {
                const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                overlay.step(d < 0 ? 1 : -1);
            }
        }

        ListView {
            id: list

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            // Headroom for the scale-up, or the highlighted card's top and
            // bottom edges clip against the view.
            height: Math.round(overlay.cardHeight * 1.15)

            orientation: ListView.Horizontal
            model: Wallpaper.entries
            spacing: Style.space(24)

            // Every input drives currentIndex and the view follows; the view
            // is never driven directly. Leaving the Flickable interactive
            // would add a second mover -- drag and its own wheel grab -- that
            // can leave the highlight parked off-centre, which is exactly the
            // ambiguity a single-focus carousel exists to remove.
            interactive: false
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: width / 2 - overlay.cardWidth / 2
            preferredHighlightEnd: width / 2 + overlay.cardWidth / 2
            // Fixed duration, not the default velocity-based move: a wrap
            // from last back to first crosses the whole directory, and at a
            // constant velocity that is seconds of scrolling for one press.
            highlightMoveDuration: 250

            // Three cards of decode-ahead per side. The default 320 pixels
            // is less than half a card, so every arrow press would land on
            // a delegate that does not exist yet.
            cacheBuffer: overlay.cardWidth * 3

            delegate: Item {
                id: card

                required property var modelData
                required property int index

                readonly property bool onDesktop: modelData === Wallpaper.current
                readonly property int dist: Math.abs(index - list.currentIndex)
                // Quadratic falloff: the neighbours read as "next" and
                // "previous", everything further is context, not choice.
                readonly property real falloff: 1 / (1 + dist * dist)

                width: overlay.cardWidth
                height: overlay.cardHeight
                y: (list.height - height) / 2

                scale: 0.78 + 0.22 * falloff
                opacity: 0.35 + 0.65 * falloff
                // The scaled-up centre card overlaps its neighbours; without
                // the z ramp whichever delegate was created later would paint
                // on top, and the highlight could sit *under* a side card.
                z: 10 - dist

                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }

                // Under the image until it decodes: async loading means a
                // freshly scrolled-to card is briefly empty, and a faint
                // plate reads as "loading" where bare scrim reads as "gone".
                Rectangle {
                    anchors.fill: parent
                    color: Util.alpha(Commons.Color.foreground, 0.06)
                    radius: Style.cornerRadius
                }

                Image {
                    anchors.fill: parent
                    source: "file://" + card.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    // The carousel's answer to decode cost, sized for its
                    // job: the grid's 480x270 thumbs would be visibly soft
                    // stretched over a third of the screen, and native size
                    // means decoding whole 4K photographs to flip past them.
                    // 1280x720 covers the card crisply up to a wide monitor
                    // at a ninth of a 4K decode. Fixed rather than bound to
                    // cardWidth so a resolution change or fractional scale
                    // does not re-decode the whole row.
                    sourceSize.width: 1280
                    sourceSize.height: 720
                }

                // Accent marks the wallpaper that is on the desktop, exactly
                // as the settings grid marks it. The centre of the carousel
                // is the cursor; the accent border is the state.
                BorderSurface {
                    anchors.fill: parent
                    color: "transparent"
                    radius: Style.cornerRadius
                    borderSpec: card.onDesktop ? Border.flat(Commons.Color.accent, 2) : Border.none()
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // A click is a pick, as upstream has it -- pointing at a
                    // visible picture is already the whole decision, and a
                    // select-then-confirm dance would make the mouse slower
                    // than the keyboard.
                    onClicked: overlay.apply(card.index)
                }
            }
        }

        // Which file, and where in the directory. The counter is what makes
        // a wrap comprehensible -- "1 of 40" appearing after "40 of 40" says
        // the ring closed, where a bare filename says nothing moved.
        Column {
            anchors.top: list.bottom
            anchors.topMargin: Style.space(24)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.xs
            visible: Wallpaper.entries.length > 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const at = list.currentIndex;
                    if (at < 0 || at >= Wallpaper.entries.length)
                        return "";
                    return Wallpaper.entries[at].split("/").pop();
                }
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (list.currentIndex + 1) + " of " + Wallpaper.entries.length
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(48)
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← →  browse      Enter  apply      Esc  close"
            color: Commons.Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }

        // The same sentence the settings grid shows for an empty directory,
        // for the same reason: a blank overlay looks broken, and the fix is
        // only obvious if the message names the directory.
        Text {
            anchors.centerIn: parent
            width: Math.round(parent.width / 2)
            visible: Wallpaper.entries.length === 0
            text: Config.wallpaperDir + " holds no images. Drop wallpapers there and they appear here."
            color: Commons.Color.foreground
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
    }
}
