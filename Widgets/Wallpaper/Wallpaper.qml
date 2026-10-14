import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Commons
import qs.Commons as Commons

// The desktop background, painted by pshell itself. Nothing else on this
// machine draws one -- no swww, no swaybg, no hyprpaper -- so this window is
// not decoration, it is the wallpaper.
//
// The middle of three weighed options: Omarchy restarts swaybg on every
// change, which is an extra process and a visible flash; DMS ships eleven
// hundred lines of shader transitions. This is one window per screen, two
// Images and an opacity crossfade -- no shaders, no process, no flash.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bgWindow

        required property var modelData

        screen: modelData

        // Background, not Bottom: Bottom still sits above other layer
        // surfaces that expect to be on the floor. Background is the floor.
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "pshell:wallpaper"

        // Mandatory, and the trap of this whole file: an anchored layer
        // surface reserves the space it covers by default, and this one
        // covers the entire screen -- so without Ignore the compositor
        // pushes every other window into a zero-sized strip and the desktop
        // is gone. The wallpaper must occupy the screen without claiming it.
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // Which of the two slots is on top. Flipping it is the crossfade:
        // both opacities are bound to it and both carry the Behavior below.
        property bool frontIsA: true

        function show(path) {
            const url = path !== "" ? "file://" + path : "";
            const showing = bgWindow.frontIsA ? a : b;
            const incoming = bgWindow.frontIsA ? b : a;
            if (String(showing.source) === url)
                return;
            incoming.source = url;
            // A cleared wallpaper never reaches Image.Ready, so fade to the
            // fallback rectangle now. A cached image may already be Ready
            // with no status change coming, so flip for that case here too;
            // everything else flips from onStatusChanged when the decode
            // lands.
            if (url === "" || incoming.status === Image.Ready)
                bgWindow.frontIsA = !bgWindow.frontIsA;
        }

        Component.onCompleted: show(Config.wallpaperPath)

        // wallpaperPath, not wallpaper -- the same trap Theme.qml records:
        // the change signal for the key being edited arrives before the
        // property derived from it has re-evaluated, so watching `wallpaper`
        // would repaint the picture just replaced.
        Connections {
            target: Config

            function onWallpaperPathChanged() {
                bgWindow.show(Config.wallpaperPath);
            }
        }

        // Underneath both images, always. An unset wallpaper, a typo in the
        // path and a file that is not an image all land here, and all three
        // must leave a desktop in the theme's colour rather than a black
        // hole.
        Rectangle {
            anchors.fill: parent
            color: Commons.Color.background
        }

        Slot {
            id: a
            shown: bgWindow.frontIsA
        }

        Slot {
            id: b
            shown: !bgWindow.frontIsA
        }

        component Slot: Image {
            // Whether this slot is the one on top. The Behavior turns every
            // flip of bgWindow.frontIsA into the crossfade -- one slot animates
            // 0 to 1 while the other runs the same curve down, so no state
            // machine is needed.
            property bool shown: false

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            // Decoded off-thread so a 4K photograph never stalls the shell,
            // and cached so switching back to a recent wallpaper skips the
            // decode entirely. The same choices LockBackground makes, for
            // the same reasons.
            asynchronous: true
            cache: true

            opacity: shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.InOutQuad
                }
            }

            // The fade starts only once the incoming image has decoded.
            // Fading toward an image that is not ready shows the fallback
            // colour through the gap and reads as a flash -- the exact thing
            // the crossfade exists to avoid.
            onStatusChanged: {
                if (status === Image.Ready && !shown)
                    bgWindow.frontIsA = !bgWindow.frontIsA;
            }
        }
    }
}
