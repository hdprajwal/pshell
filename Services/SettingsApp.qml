pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Widgets.Settings

// The one settings window, and the only thing allowed to own it.
//
// Bar widgets are instantiated once per monitor under `Variants`, so a window
// declared inside the settings bar widget would exist once per screen: three
// monitors, three windows, three copies of the same unsaved edit. The window
// lives here instead, and the widget, the control centre and IPC all call
// open().
//
// LazyLoader rather than a plain declaration because a window nobody has
// opened should not have been built. Once built it is kept: `active` stays
// true and only `visible` goes false on close, so reopening is instant and
// the scroll position is where you left it.
Singleton {
    id: root

    readonly property string defaultTab: "wallpaper"

    // Every page the sidebar draws, in the order it draws them. This is the
    // authority on what a valid tab id is; the sidebar builds its list from
    // the same ids. A tab id Prefs remembered from a build that still had the
    // network pages -- "network.wifi", say -- is not in here, so setTab
    // refuses it and currentTab falls back to the default rather than
    // resolving to a page that no longer exists.
    readonly property var tabIds: ["wallpaper", "theme", "about"]

    property string currentTab: Prefs.settingsTab !== "" && tabIds.indexOf(Prefs.settingsTab) >= 0 ? Prefs.settingsTab : defaultTab
    property bool visible: false

    function setTab(tabId) {
        if (tabIds.indexOf(tabId) < 0)
            return;
        root.currentTab = tabId;
        Prefs.setSettingsTab(tabId);
    }

    // An empty tabId means "wherever I was", which is what the bar button and
    // the control-centre gear want. A named one is what IPC and the control
    // centre's Wi-Fi link use to land you on a specific page.
    function open(tabId) {
        if (tabId !== undefined && String(tabId) !== "")
            setTab(String(tabId));
        loader.active = true;
        root.visible = true;
    }

    function close() {
        root.visible = false;
    }

    function toggle() {
        if (root.visible)
            close();
        else
            open("");
    }

    // Declared, not loaded by URL. The plan called for
    // `source: "../Widgets/Settings/SettingsWindow.qml"` to keep Services
    // from importing a module that imports Services back, and that is a real
    // concern -- but it does not work. A file Quickshell loads by URL is not
    // a member of the module its directory forms, so it cannot see its own
    // siblings: SettingsWindow.qml came up as "SettingsSidebar is not a
    // type", and adding `import qs.Widgets.Settings` to it only moved the
    // complaint to "module is not installed", because the module is not
    // registered until a file that *is* in the module tree imports it.
    //
    // Importing it here fixes both at once and the cycle is harmless: QML
    // resolves module imports lazily per type, and qs.Services is already
    // imported by two dozen files under qs.Widgets.
    LazyLoader {
        id: loader
        active: false

        SettingsWindow {}
    }

    IpcHandler {
        target: "pshell.settings"

        // Quickshell dispatches by name, so the no-argument form needs a name
        // of its own. `show` is kept because every other panel in the repo
        // has one and a script should not have to remember which targets do.
        //
        // It cannot be reached from the command line, though, and that is not
        // this handler's fault: `qs ipc call <target> show` collides with the
        // `qs ipc show` subcommand and prints the target listing instead of
        // calling anything. The same is true of pshell.calendar and every
        // other Ui/Panel target, so it predates this file. Reach for
        // `toggle`, or `open <tab>`, from a terminal.
        function open(tab: string): void {
            root.open(tab);
        }

        function show(): void {
            root.open("");
        }

        function close(): void {
            root.close();
        }

        function toggle(): void {
            root.toggle();
        }
    }
}
