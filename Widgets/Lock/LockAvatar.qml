import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Services

// The user's picture, drawn round.
//
// Every avatar anyone has ever saved to ~/.face is square, and a square one
// on a lockscreen looks like a bug. `clip` cannot do this -- Qt Quick clips
// to a rectangle regardless of `radius` -- so it takes a mask, which is why
// this is a file rather than four lines inline.
Item {
    id: root

    property string source: User.avatar
    property int diameter: 96

    implicitWidth: diameter
    implicitHeight: diameter

    Image {
        id: face

        anchors.fill: parent
        source: root.source !== "" ? "file://" + root.source : ""
        // Asked for at twice the drawn size so it stays sharp on a scaled
        // display, where the lock is the one surface you look at closely.
        sourceSize.width: root.diameter * 2
        sourceSize.height: root.diameter * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: face
        maskEnabled: true
        maskSource: mask
        visible: face.status === Image.Ready
    }

    // A hairline ring, so a dark photograph does not dissolve into a dark
    // wallpaper and leave the name below it floating.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: Commons.Color.lock.border
    }
}
