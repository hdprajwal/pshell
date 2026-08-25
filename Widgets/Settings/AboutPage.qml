import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

SettingsPage {
    id: page

    title: "About"
    subtitle: "A Quickshell bar where widgets are programs."

    Column {
        width: parent.width
        spacing: Style.spacing.md

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
