import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const B = loadQmlJs("Services/BatteryAlert.js");
const next = (percent, last) => B.nextAlert(percent, last, 20, 5);

test("alertLevel groups a charge into its five-point step", () => {
    assert.equal(B.alertLevel(21, 20, 5), -1);
    assert.equal(B.alertLevel(20, 20, 5), 20);
    assert.equal(B.alertLevel(16, 20, 5), 20);
    assert.equal(B.alertLevel(15, 20, 5), 15);
    assert.equal(B.alertLevel(11, 20, 5), 15);
    assert.equal(B.alertLevel(10, 20, 5), 10);
    assert.equal(B.alertLevel(0, 20, 5), 0);
});

test("nextAlert stays quiet above the threshold", () => {
    assert.equal(next(50, -1), -1);
    assert.equal(next(21, -1), -1);
});

test("nextAlert warns once per step as the charge falls", () => {
    let last = -1;
    const sent = [];
    for (let p = 25; p >= 3; p--) {
        const level = next(p, last);
        if (level >= 0) {
            sent.push(p);
            last = level;
        }
    }
    assert.deepEqual(sent, [20, 15, 10, 5]);
});

test("nextAlert gives one warning for a jump across several steps", () => {
    assert.equal(next(12, -1), 15);
    assert.equal(next(12, 15), -1);
    assert.equal(next(10, 15), 10);
});

test("nextAlert does not repeat when the charge wobbles back up", () => {
    assert.equal(next(19, 15), -1);
    assert.equal(next(15, 15), -1);
});
