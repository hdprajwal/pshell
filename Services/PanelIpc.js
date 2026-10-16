.pragma library

// Deciding which bar's panel an IPC call lands on.
//
// Kept pure -- no Quickshell, no panel items -- so node can test it.
// Services/PanelIpc.qml hands in one entry per live panel for a target, as
// `{ screen, open }`, plus the focused monitor's name, and acts on the plan
// this returns.
//
// The rules are the ones the singleton services (Keybinds, Weather,
// PowerMenu) already follow, so `pshell network toggle` behaves like
// `pshell keybinds toggle`:
//
//   * open lands on the focused monitor's panel. If that monitor's bar has
//     no such widget -- sections can differ per screen, or the focus is on a
//     monitor with no bar -- the first registered one stands in, because a
//     command that answers somewhere beats one that silently does nothing.
//   * toggle closes when the panel is open anywhere, rather than opening a
//     second copy on the focused screen; only one popout is up at a time.
//   * close closes every open copy, whichever screen it is on.

// Index of the entry on `focused`, else 0, else -1 for an empty list.
function pick(entries, focused) {
    if (!entries || entries.length === 0)
        return -1;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i] && entries[i].screen === focused)
            return i;
    }
    return 0;
}

function openIndices(entries) {
    var out = [];
    for (var i = 0; i < (entries ? entries.length : 0); i++) {
        if (entries[i] && entries[i].open)
            out.push(i);
    }
    return out;
}

// `{ close: [indices], open: index or -1 }` for an IPC method name. Unknown
// methods plan nothing.
function plan(method, entries, focused) {
    var opened = openIndices(entries);
    if (method === "close" || method === "hide")
        return { close: opened, open: -1 };

    if (method === "toggle" && opened.length > 0)
        return { close: opened, open: -1 };

    if (method === "open" || method === "show" || method === "toggle") {
        var at = pick(entries, focused);
        if (at < 0)
            return { close: [], open: -1 };
        // Already open where it should be: leave it, and close any stray
        // copy elsewhere, so `open` is idempotent instead of a flicker.
        return { close: opened.filter(function (i) { return i !== at; }), open: opened.indexOf(at) >= 0 ? -1 : at };
    }

    return { close: [], open: -1 };
}
