pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "PanelIpc.js" as P

// One IPC handler per panel target, for the Ui/Panel widgets (network,
// battery, calendar, bluetooth, tailscale, controlcenter, aiusage, and any
// plugin that sets `ipcTarget`).
//
// Those panels used to carry their own IpcHandler. A bar is built per
// monitor under Variants, so every screen registered the same target and
// Quickshell kept whichever came first: `pshell network toggle` opened on
// that bar, not on the monitor you were looking at. Keybinds, Weather and
// PowerMenu dodge it by owning their IPC in a singleton; these panels keep
// their open state per widget, so this one routes instead -- each panel
// registers itself here, and a call goes to the panel on the focused screen.
// The choice itself is in PanelIpc.js, where node can test it.
Singleton {
    id: root

    // target -> list of live Panel items, one per bar that has the widget.
    property var panels: ({})
    // The targets with at least one panel, as the handlers' model. Only
    // reassigned when a target appears or goes, so Variants keeps the
    // existing handlers rather than re-registering all of them each time a
    // bar comes and goes.
    property var targets: []

    function register(target, panel) {
        if (!target || !panel)
            return;
        const map = root.panels;
        const list = map[target] || [];
        if (list.indexOf(panel) < 0)
            list.push(panel);
        map[target] = list;
        root.panels = map;
        if (root.targets.indexOf(target) < 0)
            root.targets = root.targets.concat([target]);
    }

    function unregister(target, panel) {
        const map = root.panels;
        const list = map[target] || [];
        const at = list.indexOf(panel);
        if (at >= 0)
            list.splice(at, 1);
        if (list.length > 0) {
            map[target] = list;
        } else {
            delete map[target];
            root.targets = root.targets.filter(t => t !== target);
        }
        root.panels = map;
    }

    function dispatch(target, method) {
        const list = (root.panels[target] || []).filter(p => p);
        const entries = list.map(p => ({
                    screen: p.bar && p.bar.screen ? p.bar.screen.name : "",
                    open: !!p.opened
                }));
        const plan = P.plan(method, entries, root._focusedScreenName());
        for (const i of plan.close)
            list[i].close();
        if (plan.open >= 0)
            list[plan.open].open();
    }

    // Same resolution Keybinds, Weather and PowerMenu use, for the same
    // reason: IPC has no widget to ask, and the focused monitor is where the
    // eyes are.
    function _focusedScreenName() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            return mon.name;
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    Variants {
        model: root.targets

        IpcHandler {
            required property var modelData

            target: modelData

            function open(): void {
                root.dispatch(target, "open");
            }

            function close(): void {
                root.dispatch(target, "close");
            }

            function show(): void {
                root.dispatch(target, "show");
            }

            function hide(): void {
                root.dispatch(target, "hide");
            }

            function toggle(): void {
                root.dispatch(target, "toggle");
            }
        }
    }
}
