import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// A bar button that opens the settings window. Deliberately not a qs.Ui.Panel
// like Network or Calendar: those own a popup and its open/close lifecycle,
// and this widget owns nothing -- the window belongs to SettingsApp, because
// the widget itself exists once per monitor and the window must not.
//
// So there is no ipcTarget here either. `pshell.settings` is registered by the
// singleton, which is the thing that can actually service it.
Item {
    id: root

    property QtObject bar: null
    property var cfg: ({})

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconName: Glyphs.settings
        // Lit while the window is up. WidgetButton's default `activeColor` is
        // the bar's urgent colour, which is right for the privacy indicator
        // and wrong here -- a red gear reads as "something is wrong", not as
        // "this is open". Accent is what the idle inhibitor already uses for
        // the same "switched on" meaning.
        active: SettingsApp.visible
        activeColor: Color.accent

        // Every button toggles. Right-click used to open straight onto the
        // Wi-Fi page; with one page there is nowhere else to land.
        onPressed: b => SettingsApp.toggle()
    }
}
