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

    // About is the only page, so it is declared rather than routed. There was
    // a Loader here keyed on SettingsApp.currentTab, which is the right shape
    // for a switch over several pages and pure ceremony over one; the tab id
    // still exists, because the sidebar has something to highlight and Prefs
    // has something to remember, but nothing branches on it any more.
    AboutPage {
        anchors.left: divider.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }
}
