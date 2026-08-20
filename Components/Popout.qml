import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Commons

// Deprecated. qs.Ui.KeyboardPanel is the panel surface now; this stays
// only until the last widget has moved across.
//
// The panel a bar widget opens beneath itself.
//
// This is a full-screen layer-shell window rather than a PopupWindow anchored
// to the bar. A PopupWindow looks simpler, but nothing outside it receives the
// click that should dismiss it: HyprlandFocusGrab is the usual answer and it
// did not fire here. Covering the screen means the dismiss click lands on a
// plain MouseArea, which works the same on any compositor.
//
// The card is positioned by hand against the trigger widget, since covering
// the screen gives up anchor.item.
PanelWindow {
    id: popup

    property var bar: null
    property Item anchorItem: null
    property bool opened: false
    property int keyboardFocus: WlrKeyboardFocus.None

    readonly property int padding: Style.spacing.popupPadding
    readonly property int gap: Style.gapsOut

    default property alias content: container.data

    signal dismissed

    function toggle(item) {
        if (opened && anchorItem === item) {
            close();
            return;
        }
        anchorItem = item;
        opened = true;
        PopoutManager.open(popup);
    }

    function close() {
        if (!opened)
            return;
        opened = false;
        PopoutManager.release(popup);
        popup.dismissed();
    }

    // Where the trigger sits inside the bar window. The bar spans its whole
    // screen edge, so this doubles as the screen coordinate on that axis.
    readonly property real anchorX: anchorItem ? anchorItem.mapToItem(null, 0, 0).x : 0
    readonly property real anchorY: anchorItem ? anchorItem.mapToItem(null, 0, 0).y : 0
    readonly property real anchorW: anchorItem ? anchorItem.width : 0
    readonly property real anchorH: anchorItem ? anchorItem.height : 0

    readonly property bool vertical: Config.position === "left" || Config.position === "right"

    screen: bar ? bar.screen : null
    visible: opened && anchorItem !== null
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Honouring exclusive zones is what makes the positioning work. Anchored
    // to all four edges with no zone of its own, the compositor sizes this to
    // the area left over by every bar on screen, including other shells. So
    // 0,0 here is already just below the bar, with no offsets to compute, and
    // the bars stay clickable because this window never covers them.
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "qsbar:popout"
    // Top, not Overlay. On Overlay this window sits above other shells'
    // dialogs, so its dismiss layer swallowed clicks meant for them: clicking
    // a wifi password field closed this panel and never reached the field.
    // DMS defaults its popouts to Top for the same reason.
    WlrLayershell.layer: WlrLayer.Top
    // None by default: a panel that only has things to click must never take
    // the keyboard away from whatever you were typing in. A panel carrying a
    // text field raises this for as long as that field is in use.
    WlrLayershell.keyboardFocus: popup.opened ? popup.keyboardFocus : WlrKeyboardFocus.None

    // Anything not on the card dismisses.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: popup.close()
    }

    Rectangle {
        id: card

        // Centred on the trigger, then pulled back inside the screen so a
        // widget near the end of the bar does not push its panel off-screen.
        x: {
            if (popup.vertical)
                return Config.position === "left" ? popup.gap : popup.width - width - popup.gap;
            const centred = popup.anchorX + popup.anchorW / 2 - width / 2;
            return Math.max(popup.gap, Math.min(popup.width - width - popup.gap, centred));
        }
        y: {
            if (!popup.vertical)
                return Config.position === "bottom" ? popup.height - height - popup.gap : popup.gap;
            const centred = popup.anchorY + popup.anchorH / 2 - height / 2;
            return Math.max(popup.gap, Math.min(popup.height - height - popup.gap, centred));
        }

        width: Math.max(220, container.childrenRect.width + popup.padding * 2)
        height: container.childrenRect.height + popup.padding * 2

        color: Color.background
        radius: Style.cornerRadius
        border.width: Style.spacing.hairline
        border.color: Color.popups.border

        opacity: popup.opened ? 1 : 0
        scale: popup.opened ? 1 : 0.92
        transformOrigin: Config.position === "bottom" ? Item.Bottom : Item.Top

        Behavior on opacity {
            NumberAnimation {
                duration: 130
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 130
                easing.type: Easing.OutCubic
            }
        }

        // Swallow clicks so they do not reach the dismiss layer underneath.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        Item {
            id: container
            anchors.fill: parent
            anchors.margins: popup.padding
        }
    }
}
