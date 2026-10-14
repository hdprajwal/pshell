import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
// Qualified as well, for the Notifications singleton -- the sibling-shadow
// collision this directory shares with Toast.qml.
import qs.Services as Services
import qs.Commons
import qs.Commons as Commons

// The toast layer: one window per screen, in the corner opposite the bar.
// Shaped like Widgets/Wallpaper/Wallpaper.qml -- a Variants over the screens
// that shell.qml declares once -- and, like it, a view only: which toasts
// are up and for how long is the Notifications singleton's state, so every
// screen shows the same stack and a toast dismissed on one leaves all of
// them.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: stackWindow

        required property var modelData

        screen: modelData

        // "auto" is the corner opposite the bar, so a toast never covers
        // the widget counting it. A vertical bar leaves both corners free
        // and the bottom reads as the conventional place.
        readonly property bool atTop: {
            const p = Config.notifications.position;
            if (p === "top")
                return true;
            if (p === "bottom")
                return false;
            return Config.position === "bottom";
        }

        readonly property int popupCount: Services.Notifications.popupIds.length
        readonly property int overflow: Math.max(0, popupCount - Config.notifications.maxVisible)

        // Whether any current toast could take a reply. The surface asks
        // for OnDemand keyboard focus only then, and OnDemand only grants
        // it when the field is actually clicked -- a popup that steals the
        // keyboard mid-sentence is the single most hated behaviour in this
        // category, so the default is None, always.
        readonly property bool anyReply: {
            const ids = Services.Notifications.popupIds;
            for (var i = 0; i < ids.length; i++) {
                const n = Services.Notifications.liveById(ids[i]);
                if (n && n.hasInlineReply)
                    return true;
            }
            return false;
        }

        // Held through the leave animation, or the window unmaps mid-fade
        // and the last toast snaps out instead of going the way the rest
        // did.
        onPopupCountChanged: {
            if (popupCount === 0)
                exitHold.restart();
        }

        Timer {
            id: exitHold
            interval: 450
        }

        visible: popupCount > 0 || exitHold.running
        color: "transparent"

        WlrLayershell.namespace: "pshell:notifications"
        // Overlay so a toast is visible over a fullscreen window -- the
        // idle inhibitor's reasoning: the moment something goes fullscreen
        // is exactly when a popup on the Top layer would vanish.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: anyReply ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Mandatory -- the wallpaper window's trap: an anchored layer
        // surface reserves the space it covers by default, and without
        // Ignore the compositor would shove every window aside to keep this
        // corner clear.
        //
        // `ExclusionMode.Normal` with `exclusiveZone: 0` looks like the
        // tidier answer -- the protocol's own "reserve nothing, but honour
        // what others reserved" -- and it does fix the overlap at the top.
        // It was tried and reverted: with the stack anchored to the bottom
        // the surface still maps at the right geometry and then paints
        // nothing at all. Measured, not guessed -- `hyprctl layers` reported
        // `xywh: 1534 1000 380 74, a: 1` for a toast that was not on screen.
        // Whatever that is, the cost of finding out is a blank notification
        // area, so the exclusion stays as it was and the gap below is done
        // by hand.
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: atTop
            bottom: !atTop
            right: true
        }

        // Clear the bar by hand on whichever edge it occupies.
        //
        // The stack ignores exclusive zones (above), which is what stops it
        // shoving every window aside -- but ignoring them means ignoring the
        // bar's too. Anchored to the same edge as the bar, it drew straight
        // over the bar's right end and hid the tray, the clock, and the very
        // unread count the toast was announcing.
        //
        // `barDetached` matters: a bar lifted off the screen edge occupies
        // its margin as well as its own height, and a toast tucked under a
        // floating bar should clear both.
        readonly property int barClearance: Style.bar.sizeHorizontal + Style.spacing.barMarginTop
        readonly property int barBottomClearance: Style.bar.sizeHorizontal + Style.spacing.barMarginBottom

        margins {
            top: atTop ? Style.gapsOut + (Config.position === "top" ? barClearance : 0) : 0
            bottom: atTop ? 0 : Style.gapsOut + (Config.position === "bottom" ? barBottomClearance : 0)
            right: Style.gapsOut
        }

        implicitWidth: Style.space(380)
        implicitHeight: column.implicitHeight

        Column {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: stackWindow.atTop ? parent.top : undefined
            anchors.bottom: stackWindow.atTop ? undefined : parent.bottom

            // Two copies of the overflow row so it can sit at the stack's
            // inner edge -- after the toasts when they grow downward, before
            // them when they grow up -- without reordering Column children
            // at runtime.
            OverflowRow {
                shownHere: !stackWindow.atTop
            }

            // A ListView over the tracked model rather than a Repeater over
            // an array: the model inserts and removes incrementally, so an
            // arriving toast animates in without every existing delegate
            // being torn down and rebuilt mid-fade. Delegates whose toast
            // is over collapse to zero height inside Toast itself.
            ListView {
                id: list

                width: parent.width
                implicitHeight: contentHeight
                height: implicitHeight
                interactive: false

                model: Services.Notifications.trackedModel

                // The tracked model runs oldest to newest. Newest belongs
                // at the outside edge -- the screen corner -- growing
                // inward, which is bottom-last when the stack hangs from
                // the bottom and top-last when it hangs from the top.
                verticalLayoutDirection: stackWindow.atTop ? ListView.BottomToTop : ListView.TopToBottom

                delegate: Toast {
                    required property var modelData

                    width: list.width
                    notification: modelData
                }
            }

            OverflowRow {
                shownHere: stackWindow.atTop
            }
        }

        // "+N more" instead of filling the screen: the cap is
        // Config.notifications.maxVisible and everything past it waits its
        // turn as older toasts leave.
        component OverflowRow: Text {
            property bool shownHere: false

            width: parent.width
            visible: shownHere && stackWindow.overflow > 0
            text: "+" + stackWindow.overflow + " more"
            color: Commons.Color.muted
            horizontalAlignment: Text.AlignRight
            rightPadding: Style.spacing.lg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
}
