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
        title: "Colours"

        Toggle {
            width: parent.width
            label: "Colours from the wallpaper"
            description: "Derive the palette from the wallpaper with matugen and restyle the terminal, GTK apps and the rest with it. Off, the colours in config.json are used as written."
            checked: page.wallpaperTheme
            onClicked: Config.set("theme", page.wallpaperTheme ? "manual" : "wallpaper")
        }
    }

    FormSection {
        title: "Palette"
        help: page.wallpaperTheme ? "Which of the wallpaper's colours matugen builds the palette from, and how." : "On manual colours these do nothing -- matugen never runs. Turn on wallpaper colours above to use them."

        // Visibly inert on manual, not hidden: a control that vanishes reads
        // as a missing feature, and one that looks live but does nothing is
        // worse than either. enabled stops the input; the opacity says so.
        Column {
            width: parent.width
            spacing: Style.spacing.lg
            enabled: page.wallpaperTheme
            opacity: page.wallpaperTheme ? 1 : 0.4

            Dropdown {
                width: parent.width
                label: "Scheme"
                options: page.schemeOptions()
                value: Config.matugenScheme
                onChanged: v => Theme.setScheme(v)
            }

            Dropdown {
                width: parent.width
                label: "Prefer"
                options: Theme.prefers
                value: Config.matugenPrefer
                onChanged: v => Theme.setPrefer(v)
            }
        }
    }

    FormSection {
        title: "Mode"
        // Live even on manual colours: mode is not matugen's alone -- the AI
        // usage widget picks its provider marks by it, and the About page
        // reports it.
        help: "Follow desktop reads the GTK colour-scheme, so the control centre's Dark Mode tile restyles the shell too. Picking light or dark pins it and the desktop is ignored."

        ButtonGroup {
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

    FormSection {
        title: "Current palette"
        help: "What the choices above resolve to. These are the colours the bar is wearing right now."

        // The swatches read Config's resolved colours, which already update
        // when matugen re-runs -- changing the scheme repaints this row with
        // no machinery of its own. That feedback loop is the whole point of
        // the page: the palette is seen, not guessed.
        Row {
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

                    spacing: Style.spacing.xs

                    BorderSurface {
                        width: Style.space(56)
                        height: Style.space(56)
                        radius: Style.cornerRadius
                        color: swatch.modelData.value
                        // A hairline in the foreground, or the background
                        // swatch disappears into the page it sits on.
                        borderSpec: Border.flat(Util.alpha(Commons.Color.foreground, 0.25), 1)
                    }

                    Text {
                        text: swatch.modelData.name
                        color: Commons.Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    Text {
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
