import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./load-qml-js.mjs";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const K = loadQmlJs("Services/PopoutKey.js");

const popup = { close() {} };

test("an owner with close() stands in for the popup", () => {
  const panel = { close() {} };
  assert.equal(K.coordinatorKey(panel, popup), panel);
});

// The tray menu's owner is its BarWidget, which has no close(). Registering
// that left PopoutManager unable to close the menu when another panel opened.
test("an owner without close() falls back to the popup", () => {
  const barWidget = { moduleName: "pshell.tray" };
  assert.equal(K.coordinatorKey(barWidget, popup), popup);
});

test("a close that is not a function does not count", () => {
  assert.equal(K.coordinatorKey({ close: true }, popup), popup);
});

test("no owner falls back to the popup", () => {
  assert.equal(K.coordinatorKey(null, popup), popup);
  assert.equal(K.coordinatorKey(undefined, popup), popup);
});

// Both popup surfaces must register through the helper, not `owner || root`.
for (const file of ["Ui/PopupCard.qml", "Ui/KeyboardPanel.qml"]) {
  test(`${file} registers a key PopoutManager can close`, () => {
    const source = readFileSync(join(repo, file), "utf8");
    assert.match(source, /coordinatorKey:\s*PopoutKey\.coordinatorKey\(owner, root\)/);
    assert.doesNotMatch(source, /coordinatorKey:\s*owner\s*\|\|\s*root/);
  });
}
