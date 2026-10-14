import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Services

// Wallpaper, blurred, under a scrim.
//
// The image is Config.lock.wallpaper, which defaults to the bar's own
// `wallpaper` -- the same file the Theme service hands matugen. That is
// deliberate: the lock's colours are derived from this picture, so showing a
// different one would put a palette next to the image it disagrees with.
Item {
    id: root

    property string source: Config.lock.wallpaperPath

    // Underneath everything, always. An unset wallpaper, a path with a typo
    // and a file that is not an image all land here, and all of them have to
    // leave a lock you can still read a password prompt on.
    Rectangle {
        anchors.fill: parent
        color: Commons.Color.background
    }

    Image {
        id: picture

        anchors.fill: parent
        source: root.source !== "" ? "file://" + root.source : ""
        fillMode: Image.PreserveAspectCrop

        // Cached and loaded off-thread: the lock surface has to be up the
        // instant the compositor asks for it, and a synchronous decode of a
        // 4K photograph is a visible stall at exactly the wrong moment. The
        // fallback above covers the gap, and the cache means every lock
        // after the first has no gap at all.
        asynchronous: true
        cache: true

        // Drawn by the effect below instead. Image is a texture provider in
        // its own right, so MultiEffect can consume it directly and no
        // layer.enabled is needed.
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: picture
        visible: picture.status === Image.Ready

        blurEnabled: Config.lock.blur
        blur: Config.lock.blurAmount
        // Omarchy asks hyprlock for 3 blur passes. This is the equivalent
        // reach -- enough that the wallpaper reads as colour and shape
        // rather than as detail competing with the text on top of it.
        blurMax: 64
    }

    // What makes the text legible. A pale wallpaper and a light palette will
    // otherwise put near-white on near-white, and no amount of blur fixes
    // that -- blur removes detail, not brightness.
    Rectangle {
        anchors.fill: parent
        color: Util.alpha(Commons.Color.background, Config.lock.dim)
    }
}
