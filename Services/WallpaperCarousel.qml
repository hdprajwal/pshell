pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Widgets.WallpaperCarousel as CarouselLayer

// The fullscreen wallpaper carousel: whether it is up, and on which screen.
//
// The interaction is motor-dev's wallpaperCarousel plugin for DMS and
// Noctalia -- a keyboard-driven overlay over the whole desktop, applied on
// Enter, gone on Escape. That wants a real surface of its own, not a mode
// inside the settings window: exclusive keyboard focus and a screen-wide
// scrim are things a page in an xdg toplevel cannot ask for. The grid in
// Widgets/Settings/WallpaperPage.qml stays as the browse-and-compare view;
// this is the pick-one-now view, and both call the same Wallpaper.set().
//
// A singleton for the reason SettingsApp.qml already gives for its window:
// anything declared inside a per-screen widget exists once per screen, and
// "is the carousel open" is one fact per session. It also gives the overlay
// an owner with no widget attached, so a keybind can raise it on a bar that
// has no wallpaper UI at all.
//
// No IpcHandler here, deliberately. The door is `pshell wallpaper carousel`,
// which lands on Services/Wallpaper.qml's existing pshell.wallpaper target --
// one wallpaper noun on the command line, not two. That handler referencing
// this singleton is also what brings it to life on first call, so shell.qml
// needs no keep-alive line for it.
Singleton {
    id: root

    property bool visible: false

    // Captured once per open(), never bound. A binding to the focused
    // monitor would drag the overlay to whatever screen the mouse wanders
    // onto while it is up, taking the keyboard grab with it mid-browse.
    property var screen: null

    function open() {
        root.screen = _focusedScreen();
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
            open();
    }

    // HyprlandMonitor carries the output's name but not its ShellScreen, so
    // the match goes through the name. No Hyprland -- a nested compositor,
    // say -- means no focus answer, and the first screen is the honest
    // fallback rather than no carousel at all.
    function _focusedScreen() {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        if (mon) {
            for (var i = 0; i < screens.length; i++) {
                if (screens[i].name === mon.name)
                    return screens[i];
            }
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // Built on first open, kept after: same lifecycle as the settings
    // window, and for the same reason -- a surface nobody has asked for
    // should not exist, but rebuilding it on every open would re-decode
    // every card each time.
    LazyLoader {
        id: loader
        active: false

        CarouselLayer.CarouselOverlay {}
    }
}
