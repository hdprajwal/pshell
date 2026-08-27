import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// A plain xdg-toplevel, not a layer-shell surface. The settings window is an
// application window and should behave like one: placed by whatever Hyprland
// rule the user already has for application windows, with their own
// decoration. pshell deliberately passes no floating hint of its own --
// guessing at window management is the compositor's job.
FloatingWindow {
    id: win

    title: "pshell settings"
    color: Color.background
    visible: SettingsApp.visible

    // Prefs remembers the last size; zero means never opened.
    implicitWidth: Prefs.settingsWidth > 0 ? Prefs.settingsWidth : Style.space(960)
    implicitHeight: Prefs.settingsHeight > 0 ? Prefs.settingsHeight : Style.space(680)
    minimumSize: Qt.size(Style.space(720), Style.space(460))

    // Closing from the titlebar is the same as closing from the bar button:
    // hidden, not destroyed. Rebuilding would throw away the scroll position
    // for no gain.
    onClosed: SettingsApp.close()

    // A resize is a stream of width changes, and writing state.json on each
    // one would hammer the disk for the length of a drag.
    onWidthChanged: sizeSaver.restart()
    onHeightChanged: sizeSaver.restart()

    Timer {
        id: sizeSaver
        interval: 500
        repeat: false
        onTriggered: Prefs.setSettingsSize(win.width, win.height)
    }

    SettingsSidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: implicitWidth
    }

    PanelSeparator {
        id: divider
        anchors.left: sidebar.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.spacing.hairline
    }

    // The Loader is back. It was removed when About became the only page --
    // a switch over one case is ceremony -- and returns now that there are
    // three. A later phase's page is one sidebar entry, one tab id and one
    // case here; the default is About so an id this build does not know
    // still lands somewhere rather than on a blank pane.
    Loader {
        anchors.left: divider.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        sourceComponent: {
            switch (SettingsApp.currentTab) {
            case "wallpaper":
                return wallpaperPage;
            case "theme":
                return themePage;
            case "notifications":
                return notificationsPage;
            default:
                return aboutPage;
            }
        }
    }

    Component {
        id: wallpaperPage

        WallpaperPage {}
    }

    Component {
        id: themePage

        ThemePage {}
    }

    Component {
        id: notificationsPage

        NotificationsPage {}
    }

    Component {
        id: aboutPage

        AboutPage {}
    }
}
