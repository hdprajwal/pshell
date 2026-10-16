import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./load-qml-js.mjs";

const P = loadQmlJs("Services/PanelIpc.js");
const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// Two monitors, each bar with its own copy of the panel, in the order the
// bars happened to load. Issue #12: the first-loaded bar won every call.
const closed = [{ screen: "DP-1", open: false }, { screen: "HDMI-A-1", open: false }];

test("open and toggle land on the focused monitor, not the first bar", () => {
    for (const method of ["open", "show", "toggle"])
        assert.deepEqual(P.plan(method, closed, "HDMI-A-1"), { close: [], open: 1 }, method);
    assert.deepEqual(P.plan("toggle", closed, "DP-1"), { close: [], open: 0 });
});

test("a focused monitor without the widget falls back to the first copy", () => {
    assert.deepEqual(P.plan("toggle", closed, "eDP-1"), { close: [], open: 0 });
    assert.deepEqual(P.plan("open", closed, ""), { close: [], open: 0 });
});

test("toggle closes the panel wherever it is open", () => {
    const openOnFirst = [{ screen: "DP-1", open: true }, { screen: "HDMI-A-1", open: false }];
    assert.deepEqual(P.plan("toggle", openOnFirst, "HDMI-A-1"), { close: [0], open: -1 });
    assert.deepEqual(P.plan("toggle", openOnFirst, "DP-1"), { close: [0], open: -1 });
});

test("open moves the panel to the focused monitor and is idempotent there", () => {
    const openOnFirst = [{ screen: "DP-1", open: true }, { screen: "HDMI-A-1", open: false }];
    assert.deepEqual(P.plan("open", openOnFirst, "HDMI-A-1"), { close: [0], open: 1 });
    assert.deepEqual(P.plan("open", openOnFirst, "DP-1"), { close: [], open: -1 });
});

test("close and hide close every open copy", () => {
    const both = [{ screen: "DP-1", open: true }, { screen: "HDMI-A-1", open: true }];
    assert.deepEqual(P.plan("close", both, "DP-1"), { close: [0, 1], open: -1 });
    assert.deepEqual(P.plan("hide", closed, "DP-1"), { close: [], open: -1 });
});

test("no registered panels and unknown methods plan nothing", () => {
    assert.deepEqual(P.plan("toggle", [], "DP-1"), { close: [], open: -1 });
    assert.equal(P.pick([], "DP-1"), -1);
    assert.deepEqual(P.plan("frobnicate", closed, "DP-1"), { close: [], open: -1 });
});

// The defect was a handler per bar on a shared target. Keep Ui/Panel.qml
// from growing one back: it registers with the router instead.
test("Ui/Panel.qml registers with the router rather than owning an IpcHandler", () => {
    const src = readFileSync(join(repo, "Ui", "Panel.qml"), "utf8");
    assert.doesNotMatch(src, /\bIpcHandler\s*\{/);
    assert.match(src, /Services\.PanelIpc\.register\(/);
    assert.match(src, /Services\.PanelIpc\.unregister\(/);
});
