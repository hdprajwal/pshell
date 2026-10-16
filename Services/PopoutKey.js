.pragma library

// Which object a popup registers with PopoutManager. Kept out of the QML so
// `node --test` can load it the way tests/load-qml-js.mjs loads the other
// libraries.

// PopoutManager closes whatever is open by calling close() on what was
// registered, and skips anything without one. A popup's `owner` is often a
// qs.Ui.Panel, which has close(), but it can be any item: the tray menu hands
// over its BarWidget, and an Omarchy widget may hand over anything at all.
// Registering one of those left the popup open on top of the next panel, its
// full-screen dismiss layer eating the following click. So the owner only
// stands in for the popup when it can actually be closed.
function canClose(target) {
    return !!target && typeof target.close === "function";
}

function coordinatorKey(owner, popup) {
    return canClose(owner) ? owner : popup;
}
