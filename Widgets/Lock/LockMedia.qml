import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Commons as Commons
import qs.Services
import qs.Ui

// What is playing, and the three keys DMS puts beside it on its lockscreen:
// previous, play/pause, next.
//
// Mpris straight from Quickshell rather than through playerctl: the player
// list and every property on it are live D-Bus bindings already, so there
// is nothing to poll and nothing to spawn while the screen is locked.
//
// These keys work without a password, deliberately -- pausing the music on
// a locked laptop is the thing you most often want to do to one. The
// `lock.showMedia` setting takes the whole segment away for anyone who
// would rather it did not.
Row {
    id: root

    // The player worth showing: one that is playing, else the first that
    // has a track at all. A browser tab that once played a video and now
    // sits paused on nothing should not win over the music.
    readonly property var player: {
        const list = Mpris.players.values;
        var fallback = null;
        for (var i = 0; i < list.length; i++) {
            if (list[i].isPlaying)
                return list[i];
            if (fallback === null && list[i].trackTitle)
                fallback = list[i];
        }
        return fallback;
    }

    readonly property bool active: player !== null
    readonly property bool playing: active && player.isPlaying
    readonly property int maxTitleWidth: Math.round(Style.font.body * 22)

    spacing: Style.spacing.lg

    MaterialIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: Glyphs.music
        size: Style.font.icon
        color: root.playing ? Commons.Color.lock.borderActive : Commons.Color.lock.placeholder
    }

    // "Title • Artist", DMS's form, elided rather than wrapped: the row is
    // one line high and stays that way.
    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.maxTitleWidth)
        text: {
            if (!root.active || !root.player.trackTitle)
                return "";
            return root.player.trackArtist ? root.player.trackTitle + " • " + root.player.trackArtist : root.player.trackTitle;
        }
        color: Commons.Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        LockKey {
            width: Math.round(Style.font.body * 2.2)
            height: width
            filledGlyph: true
            litColor: Commons.Color.lock.text
            glyph: Glyphs.skipPrevious
            enabled: root.active && root.player.canGoPrevious
            onClicked: root.player.previous()
        }

        LockKey {
            width: Math.round(Style.font.body * 2.2)
            height: width
            filledGlyph: true
            litColor: Commons.Color.lock.text
            glyph: root.playing ? Glyphs.pause : Glyphs.play
            lit: root.playing
            enabled: root.active && root.player.canTogglePlaying
            onClicked: root.player.togglePlaying()
        }

        LockKey {
            width: Math.round(Style.font.body * 2.2)
            height: width
            filledGlyph: true
            litColor: Commons.Color.lock.text
            glyph: Glyphs.skipNext
            enabled: root.active && root.player.canGoNext
            onClicked: root.player.next()
        }
    }
}
