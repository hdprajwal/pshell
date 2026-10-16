import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const qml = readFileSync(join(repo, "Widgets/Bluetooth/Bluetooth.qml"), "utf8");

// The bar slot once bound to a `root.iconSource` that no longer existed and a
// label that was "" either way, so the icon was blank and showCount did
// nothing. QML resolves those bindings to undefined without complaint, so
// these pin the two bindings to what they must read from.

test("bluetooth bar icon comes from Icons.bluetooth", () => {
    assert.match(qml, /iconSource:\s*Icons\.bluetooth\(root\.enabled,\s*root\.connectedDevices\.length > 0\)/);
    assert.doesNotMatch(qml, /iconSource:\s*root\.iconSource/);
});

test("bluetooth label shows the connected-device count when showCount is on", () => {
    assert.match(qml, /label:\s*root\.showCount \? String\(root\.connectedDevices\.length\) : ""/);
});
