import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The wallpaper picker: every image in Config.wallpaperDir as a thumbnail,
// the one on screen marked. Clicking one goes through Wallpaper.set(), so a
// click here is the same single config write as `pshell wallpaper set` and
// the palette re-derives with it.
SettingsPage {
    id: page

    title: "Wallpaper"
    subtitle: Config.wallpaperDir

    FormSection {
        title: "Directory"
        help: "Where to look for images. PNG, JPEG and WebP files in it appear below."

        TextField {
            width: parent.width
            text: Config.data.wallpaperDir || "~/wallpapers"

            // editingFinished fires on every focus loss, changed or not, and
            // an unchanged write would still rewrite config.json and rescan
            // the directory for nothing.
            onEditingFinished: {
                if (text !== (Config.data.wallpaperDir || "~/wallpapers"))
                    Config.set("wallpaperDir", text);
            }
        }
    }

    // The grid's fullscreen sibling, one click away. The carousel is not a
    // mode of this page -- it is its own overlay surface, because it wants
    // the whole screen and an exclusive keyboard grab, which a page inside
    // an xdg toplevel cannot have. It opens over this window, and Escape
    // lands you back here.
    FormSection {
        title: "Carousel"
        help: "Browse the same images fullscreen, one at a time. Arrow keys move, Enter applies, Escape returns here. Also on `pshell wallpaper carousel`."

        Button {
            id: carouselButton

            text: "Open carousel"
            bordered: true
            // Disabled, not hidden, on an empty directory: the sentence
            // below already explains why there is nothing to browse, and a
            // button that vanishes with it would look like a removed
            // feature rather than an empty folder.
            enabled: Wallpaper.entries.length > 0
            opacity: carouselButton.enabled ? 1 : 0.4
            onClicked: WallpaperCarousel.open()
        }
    }

    // A sentence, not a blank page: an empty grid without it looks like the
    // picker is broken rather than the directory being empty, and it has to
    // say which directory so the fix is obvious.
    Text {
        width: parent.width
        visible: Wallpaper.entries.length === 0
        text: Config.wallpaperDir + " holds no images. Drop wallpapers there and they appear here."
        color: Commons.Color.muted
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }

    Flow {
        id: grid

        width: parent.width
        spacing: Style.spacing.md

        // Three across, whatever the window width. A fixed thumbnail size
        // would leave a ragged right edge on wide windows and overflow
        // narrow ones.
        readonly property int cell: Math.floor((width - 2 * spacing) / 3)

        Repeater {
            model: Wallpaper.entries

            Item {
                id: thumb

                required property var modelData

                readonly property bool current: modelData === Wallpaper.current

                width: grid.cell
                height: Math.round(grid.cell * 9 / 16)

                Image {
                    anchors.fill: parent
                    source: "file://" + thumb.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true

                    // The one line keeping this page cheap: without a
                    // sourceSize the Image decodes the file at its native
                    // resolution, and a directory of 4K photographs becomes
                    // that many full-size textures for a grid of thumbnails.
                    // Fixed rather than bound to the cell so a window resize
                    // does not re-decode every image.
                    sourceSize.width: 480
                    sourceSize.height: 270
                }

                // The mark for "this one is on screen": an accent border,
                // which is how the sidebar says "current" too -- accent
                // chrome, never a second fill fighting the image.
                BorderSurface {
                    anchors.fill: parent
                    color: "transparent"
                    radius: Style.cornerRadius
                    borderSpec: thumb.current ? Border.flat(Commons.Color.accent, 2) : (hover.containsMouse ? Border.flat(Commons.Color.foreground, 1) : Border.none())
                }

                MouseArea {
                    id: hover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Wallpaper.set(thumb.modelData)
                }
            }
        }
    }
}
