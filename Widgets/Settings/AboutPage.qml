import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import qs.Commons
import qs.Ui

SettingsPage {
    id: page

    title: "About"
    subtitle: "A Quickshell bar where widgets are programs."

    // The same facts neofetch prints, gathered here rather than by shelling
    // out to neofetch. Parsing another program's human-facing output would
    // make a settings page depend on a tool most machines do not have, and on
    // it not changing its layout.
    //
    // Read once, when you open the page. Nothing here changes fast enough to
    // poll for, and a settings window nobody has opened should cost nothing --
    // the same reason SettingsApp builds the window behind a LazyLoader.
    property var sys: ({})

    // Every field is optional and `emit` drops the empty ones, so a machine
    // with no lspci, no pacman or no DMI product name loses those rows rather
    // than showing "unknown" -- which would be a fact about the tooling, not
    // about the machine.
    //
    // `\\t` and `\\n` rather than `\t` and `\n`: QML resolves its own escapes
    // first, and printf has to receive the two characters, not a tab and a
    // newline already expanded into its format string.
    readonly property string probe: '. /etc/os-release 2>/dev/null
emit() { [ -n "$2" ] && printf \'%s\\t%s\\n\' "$1" "$2"; }
emit os "$PRETTY_NAME"
emit host "$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)"
emit kernel "$(uname -r)"
emit uptime "$(uptime -p 2>/dev/null | sed \'s/^up //\')"
emit packages "$(command -v pacman >/dev/null 2>&1 && pacman -Qq 2>/dev/null | wc -l)"
emit shell "$(basename "$SHELL" 2>/dev/null)"
emit compositor "$(hyprctl version 2>/dev/null | head -1 | sed \'s/ built from.*//\')"
emit cpu "$(awk -F\': \' \'/model name/{print $2; exit}\' /proc/cpuinfo 2>/dev/null)"
emit gpu "$(lspci 2>/dev/null | grep -Ei \'vga|3d controller|display\' | head -1 | sed \'s/.*: //\')"
emit memory "$(free -h --si 2>/dev/null | awk \'/^Mem:/{print $3" / "$2}\')"'

    // Drawn in neofetch's order: what the machine is, then what it runs, then
    // what it is made of.
    readonly property var fields: [
        {
            key: "os",
            label: "OS"
        },
        {
            key: "host",
            label: "Host"
        },
        {
            key: "kernel",
            label: "Kernel"
        },
        {
            key: "uptime",
            label: "Uptime"
        },
        {
            key: "packages",
            label: "Packages"
        },
        {
            key: "shell",
            label: "Shell"
        },
        {
            key: "compositor",
            label: "Compositor"
        },
        {
            key: "cpu",
            label: "CPU"
        },
        {
            key: "gpu",
            label: "GPU"
        },
        {
            key: "memory",
            label: "Memory"
        }
    ]

    function apply(text) {
        const next = ({});
        const lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            const tab = lines[i].indexOf("\t");
            if (tab < 0)
                continue;
            next[lines[i].slice(0, tab)] = lines[i].slice(tab + 1).trim();
        }
        page.sys = next;
    }

    Process {
        running: true
        command: ["sh", "-c", page.probe]
        stdout: StdioCollector {
            onStreamFinished: page.apply(text)
        }
    }

    Column {
        width: parent.width
        spacing: Style.spacing.xxl

        FormSection {
            title: "System"

            Repeater {
                model: page.fields

                AboutRow {
                    required property var modelData

                    label: modelData.label
                    value: page.sys[modelData.key] || ""
                    // A row for a fact this machine cannot report is not an
                    // empty row, it is no row. Column leaves invisible
                    // children out of its layout, so the gap closes itself.
                    visible: value !== ""
                }
            }
        }

        FormSection {
            title: "pshell"

            AboutRow {
                label: "Config"
                value: Quickshell.env("HOME") + "/.config/pshell/config.json"
            }

            AboutRow {
                label: "State"
                value: Quickshell.env("HOME") + "/.config/pshell/state.json"
            }

            AboutRow {
                label: "Theme"
                value: Config.theme === "wallpaper" ? "wallpaper (matugen)" : "manual"
            }

            AboutRow {
                label: "Colour scheme"
                value: Config.mode
            }

            AboutRow {
                label: "Font"
                value: Style.font.resolvedFamily + "  " + Style.font.baseSize + "px"
            }
        }
    }

    component AboutRow: Row {
        id: aboutRow

        property string label: ""
        property string value: ""

        width: parent ? parent.width : 0
        spacing: Style.spacing.lg

        Text {
            width: Style.space(140)
            text: aboutRow.label
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Text {
            width: aboutRow.width - Style.space(140) - aboutRow.spacing
            text: aboutRow.value
            color: Color.foreground
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
    }
}
