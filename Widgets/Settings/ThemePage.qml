import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The matugen palette, picked visually. Scheme, prefer and mode go through
// the Theme service's own setters, never Config.set() from here: the setters
// validate against matugen's real value lists, and writing the key directly
// would route around that validation and leave the page free to store a value
// matugen rejects on every refresh.
//
// Laid out after DankMaterialShell's theme tab (MIT): a section that opens
// on the theme in use with the source as a centred choice under it, mode as
// a centred choice of its own, and the palette spread across a row. Only the
// arrangement came over; it is drawn in the same kit as every other page,
// and every control here is one pshell already had.
SettingsPage {
    id: page

    title: "Theme"

    readonly property bool wallpaperTheme: Config.theme === "wallpaper"

    // Dropdown labels derived from the service's list, never a list of their
    // own: "scheme-tonal-spot" reads as "tonal spot", but the value emitted
    // is the exact string the setter validates.
    function schemeOptions() {
        return Theme.schemes.map(s => ({
            value: s,
            label: s.replace("scheme-", "").replace(/-/g, " ")
        }));
    }

    FormSection {
        title: "Theme"
        icon: Glyphs.palette
        help: page.wallpaperTheme ? "Scheme and Prefer set how matugen picks colours from the wallpaper." : "Scheme and Prefer only apply to colours from the wallpaper."

        // Which theme is up, said before anything asks you to change it --
        // DMS opens its theme card the same way. Left-aligned with the
        // buttons and rows under it, as everything else in the window is.
        Column {
            width: parent.width
            topPadding: Style.spacing.sm
            bottomPadding: Style.spacing.md
            spacing: Style.spacing.xs

            Text {
                text: "Current theme: " + (page.wallpaperTheme ? "Wallpaper" : "Manual")
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: page.wallpaperTheme ? "Matugen restyles the shell, terminal and GTK apps from the wallpaper." : "The colours in config.json."
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }

            Item {
                width: 1
                height: Style.spacing.md
            }

            // Two states of one key, so a choice of two instead of a switch:
            // a switch says "on or off", and manual is not wallpaper switched
            // off -- it is a palette of its own. The value written is the one
            // the switch wrote, and only when it differs, so picking the
            // current source writes nothing.
            ButtonGroup {
                options: [
                    {
                        value: "wallpaper",
                        label: "Wallpaper"
                    },
                    {
                        value: "manual",
                        label: "Manual"
                    }
                ]
                value: page.wallpaperTheme ? "wallpaper" : "manual"
                onChanged: v => {
                    if (v !== value)
                        Config.set("theme", v);
                }
            }
        }

        // Visibly inert on manual, not hidden: a control that vanishes reads
        // as a missing feature, and one that looks live but does nothing is
        // worse than either. enabled stops the input; the opacity says so.
        Column {
            width: parent.width
            enabled: page.wallpaperTheme
            opacity: page.wallpaperTheme ? 1 : 0.4

            FormRow {
                label: "Scheme"

                Dropdown {
                    showLabel: false
                    options: page.schemeOptions()
                    value: Config.matugenScheme
                    onChanged: v => Theme.setScheme(v)
                }
            }

            FormRow {
                label: "Prefer"

                Dropdown {
                    showLabel: false
                    options: Theme.prefers
                    value: Config.matugenPrefer
                    onChanged: v => Theme.setPrefer(v)
                }
            }
        }
    }

    FormSection {
        title: "Mode"
        icon: Glyphs.contrast
        // Live even on manual colours: mode is not matugen's alone -- the AI
        // usage widget picks its provider marks by it, and the About page
        // reports it.
        help: "Follow desktop tracks the GTK colour scheme and the Dark Mode tile."

        Item {
            width: parent.width
            height: modeGroup.height

            ButtonGroup {
                id: modeGroup

                // Not Config.mode: that property resolves the fallback, so it
                // never says "auto". Whether the key is pinned is only visible
                // in the raw data.
                readonly property string pinned: Config.data.mode === "light" || Config.data.mode === "dark" ? Config.data.mode : "auto"

                options: [
                    {
                        value: "light",
                        label: "Light"
                    },
                    {
                        value: "dark",
                        label: "Dark"
                    },
                    {
                        value: "auto",
                        label: "Follow desktop"
                    }
                ]
                value: pinned
                onChanged: v => Theme.setMode(v)
            }
        }
    }

    FormSection {
        title: "Current palette"
        icon: Glyphs.swatches

        // The swatches read Config's resolved colours, which already update
        // when matugen re-runs -- changing the scheme repaints this row with
        // no machinery of its own. That feedback loop is the whole point of
        // the page: the palette is seen, not guessed.
        //
        // Spread across the row in equal columns, the way DMS spreads its
        // swatches, rather than packed at the left edge.
        Row {
            id: swatches

            readonly property int count: 5
            readonly property real tileWidth: (width - spacing * (count - 1)) / count

            width: parent.width
            spacing: Style.spacing.lg

            Repeater {
                model: [
                    {
                        name: "background",
                        value: Config.bg
                    },
                    {
                        name: "foreground",
                        value: Config.fg
                    },
                    {
                        name: "accent",
                        value: Config.accent
                    },
                    {
                        name: "urgent",
                        value: Config.urgent
                    },
                    {
                        name: "dim",
                        value: Config.dim
                    }
                ]

                Column {
                    id: swatch

                    required property var modelData

                    width: swatches.tileWidth
                    spacing: Style.spacing.xs

                    BorderSurface {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(40)
                        height: Style.space(40)
                        radius: Style.cornerRadius
                        color: swatch.modelData.value
                        // A hairline in the foreground, or the background
                        // swatch disappears into the page it sits on.
                        borderSpec: Border.flat(Util.alpha(Commons.Color.foreground, 0.25), 1)
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: swatch.modelData.name
                        color: Commons.Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: swatch.modelData.value
                        color: Commons.Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }
            }
        }
    }
}
