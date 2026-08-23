import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui
import qs.Widgets.Settings.Network

// A plain xdg-toplevel, not a layer-shell surface. The settings window is an
// application window and should behave like one: placed by whatever Hyprland
// rule the user already has for application windows, with their own
// decoration. qsbar deliberately passes no floating hint of its own --
// guessing at window management is the compositor's job.
FloatingWindow {
    id: win

    title: "qsbar settings"
    color: Color.background
    visible: SettingsApp.visible

    // Prefs remembers the last size; zero means never opened.
    implicitWidth: Prefs.settingsWidth > 0 ? Prefs.settingsWidth : Style.space(960)
    implicitHeight: Prefs.settingsHeight > 0 ? Prefs.settingsHeight : Style.space(680)
    minimumSize: Qt.size(Style.space(720), Style.space(460))

    // Closing from the titlebar is the same as closing from the bar button:
    // hidden, not destroyed. Rebuilding would throw away the scroll position
    // and any half-typed field for no gain.
    onClosed: SettingsApp.close()

    // The data layer idles while nothing is looking. Holding the reference on
    // window *visibility* rather than on construction is what makes that
    // true: the window object outlives the first close.
    onVisibleChanged: {
        if (win.visible)
            Nm.addRef();
        else
            Nm.removeRef();
    }

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

    Loader {
        id: content
        anchors.left: divider.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // One Loader keyed on the current tab, the way
        // Components/Section.qml resolves a widget type. DMS gives each tab
        // its own Loader gated on an index, which keeps every visited page
        // resident; that is the right trade when a page is expensive and the
        // wrong one here, where a page is a Column of rows and rebuilding it
        // is free.
        sourceComponent: {
            switch (SettingsApp.currentTab) {
            case "network.status":
                return statusComponent;
            case "network.wifi":
                return wifiComponent;
            case "about":
                return aboutComponent;
            default:
                return null;
            }
        }
    }

    Component {
        id: statusComponent
        StatusTab {}
    }

    Component {
        id: wifiComponent
        WifiTab {}
    }

    Component {
        id: aboutComponent
        AboutPage {}
    }
}
