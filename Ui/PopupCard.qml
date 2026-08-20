import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The panel a bar widget opens beside itself.
//
// Omarchy's original is an xdg-popup parented to the bar window. That places
// the card from the output's origin rather than the bar's own, so the moment
// another shell's bar sits above this one the card is drawn that much too
// high — over the bar it belongs under. It also fixes its position at map
// time, before the content has settled on a height.
//
// This is a layer-shell surface anchored to all four edges that honours
// exclusive zones instead, so the compositor sizes it to the region every bar
// on screen has left over. Its 0,0 is therefore already just past the bar:
// there is no bar height to add, no output origin to correct, and no size to
// know in advance. KeyboardPanel positions itself the same way.
//
// The API is unchanged, so an Omarchy widget written against the original
// needs no edit.
PanelWindow {
    id: root

    required property Item anchorItem
    required property QtObject bar
    property var owner: null
    property int margin: Style.gapsOut
    property int padding: Style.spacing.popupPadding
    property int contentWidth: Style.space(280)
    property int contentHeight: Style.space(200)
    property color borderColor: Color.popups.border
    property var borderSpec: Border.localOrSurfaceSpec("popups", "border", borderColor, Color.popups.border, Math.max(1, Style.space(2)))
    property bool open: false
    property bool centerOnBar: false
    // "click" — clicking outside dismisses the card.
    // "hover" — passive overlay; the owning widget controls `open` itself and
    // the surface stays entirely click-through.
    property string triggerMode: "click"
    property int gap: Style.gapsOut

    default property alias contentItem: contentHolder.children

    readonly property var coordinatorKey: owner || root
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
    readonly property bool containsMouse: cardHover.hovered
    readonly property string barPos: bar ? bar.position : "top"

    function close() {
        if (owner && "close" in owner)
            owner.close();
        else
            root.open = false;
    }

    // --- surface -----------------------------------------------------------

    screen: popupScreen
    visible: open || card.opacity > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Normal

    WlrLayershell.namespace: "qsbar:popup-card"
    // Top rather than Overlay: on Overlay this sits above other shells'
    // dialogs and its dismissal layer swallows clicks meant for them.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // A hover-driven card must never take a click that was meant for the
    // window behind it.
    mask: root.triggerMode === "hover" ? emptyRegion : null

    Region {
        id: emptyRegion
    }

    // --- geometry ----------------------------------------------------------

    // The surface, not the output: the compositor already subtracted every
    // bar, so this is the room the card actually has.
    readonly property real surfaceW: root.width
    readonly property real surfaceH: root.height
    readonly property real anchorW: anchorItem ? anchorItem.width : 0
    readonly property real anchorH: anchorItem ? anchorItem.height : 0
    readonly property real availableCardWidth: surfaceW > 0 ? Math.max(120, surfaceW - margin * 2) : 0
    readonly property real availableCardHeight: surfaceH > 0 ? Math.max(120, surfaceH - margin * 2) : 0
    readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

    function fittedContentWidth(width, cap) {
        var desired = Math.max(1, Number(width) || 1);
        var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired;
        if (cap !== undefined && Number(cap) > 0)
            maxWidth = Math.min(maxWidth, Number(cap));
        return Math.round(Math.min(desired, maxWidth));
    }

    function fittedContentHeight(implicitHeight, cap) {
        var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset);
        var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired;
        if (cap !== undefined && Number(cap) > 0)
            maxHeight = Math.min(maxHeight, Number(cap));
        return Math.round(Math.min(desired, maxHeight));
    }

    function cappedContentHeight(height) {
        var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2);
        var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired;
        return Math.round(Math.min(desired, maxHeight));
    }

    // Track every layout change between the bar's content surface and the
    // anchor, so the position binding stays live; mapToItem alone is a
    // one-shot reading.
    TransformWatcher {
        id: anchorWatcher
        a: root.anchorWindow ? root.anchorWindow.contentItem : null
        b: root.anchorItem
    }

    // Where the anchor sits along the bar. The bar spans its whole screen
    // edge on that axis, so this doubles as the surface coordinate.
    readonly property point anchorBarPos: {
        anchorWatcher.transform;
        if (!anchorItem || !anchorWindow)
            return Qt.point(0, 0);
        return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0);
    }

    // Top-left of the card within the surface. The edge the bar sits on is
    // already the surface's own edge, so the away-from-bar axis is just `gap`.
    readonly property point cardOrigin: {
        if (!anchorItem || !bar)
            return Qt.point(margin, margin);
        var x = 0, y = 0;
        if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
            x = surfaceW / 2 - contentWidth / 2;
            y = barPos === "bottom" ? surfaceH - contentHeight - gap : gap;
        } else if (centerOnBar) {
            x = barPos === "left" ? gap : surfaceW - contentWidth - gap;
            y = surfaceH / 2 - contentHeight / 2;
        } else if (barPos === "bottom") {
            x = anchorBarPos.x + anchorW / 2 - contentWidth / 2;
            y = surfaceH - contentHeight - gap;
        } else if (barPos === "left") {
            x = gap;
            y = anchorBarPos.y + anchorH / 2 - contentHeight / 2;
        } else if (barPos === "right") {
            x = surfaceW - contentWidth - gap;
            y = anchorBarPos.y + anchorH / 2 - contentHeight / 2;
        } else {
            x = anchorBarPos.x + anchorW / 2 - contentWidth / 2;
            y = gap;
        }
        x = Math.max(margin, Math.min(x, surfaceW - contentWidth - margin));
        y = Math.max(margin, Math.min(y, surfaceH - contentHeight - margin));
        return Qt.point(Math.round(x), Math.round(y));
    }

    // --- popout coordination ------------------------------------------------

    onOpenChanged: {
        if (!bar)
            return;
        if (open)
            bar.requestPopout(coordinatorKey);
        else if (bar.activePopout === coordinatorKey)
            bar.releasePopout(coordinatorKey);
    }

    // --- dismissal ----------------------------------------------------------

    // The surface stops at the bar, so a click on a bar icon lands on that
    // icon and the popout coordinator swaps panels by itself. Nothing here
    // needs to recognise the bar or forward anything to it.
    MouseArea {
        anchors.fill: parent
        enabled: root.open && root.triggerMode === "click"
        acceptedButtons: Qt.AllButtons
        onClicked: root.close()
    }

    // --- card ---------------------------------------------------------------

    BorderSurface {
        id: card
        x: root.cardOrigin.x
        y: root.cardOrigin.y
        width: root.contentWidth
        height: root.contentHeight
        color: Color.popups.background
        borderSpec: root.borderSpec
        padding: root.padding
        radius: Style.cornerRadius
        opacity: root.open ? 1.0 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        // Swallow clicks on the card so they do not reach the dismissal
        // layer behind it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Item {
            id: contentHolder
            anchors.fill: parent
            anchors.topMargin: card.contentTopInset
            anchors.rightMargin: card.contentRightInset
            anchors.bottomMargin: card.contentBottomInset
            anchors.leftMargin: card.contentLeftInset
        }

        HoverHandler {
            id: cardHover
        }
    }
}
