import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const C = loadQmlJs("Services/CapsLock.js");

// ------------------------------------------------------------- discovery

test("parseLedDirs keeps capslock LEDs, sorted", () => {
  const out = "/sys/class/leds/input10::capslock\n/sys/class/leds/input4::capslock\n";
  assert.deepEqual(C.parseLedDirs(out), ["/sys/class/leds/input10::capslock", "/sys/class/leds/input4::capslock"]);
});

test("parseLedDirs drops other LEDs, repeats and blank lines", () => {
  const out = [
    "/sys/class/leds/input4::numlock",
    "",
    "  /sys/class/leds/input4::capslock  ",
    "/sys/class/leds/input4::capslock",
    "/sys/class/leds/input4::scrolllock",
  ].join("\n");
  assert.deepEqual(C.parseLedDirs(out), ["/sys/class/leds/input4::capslock"]);
});

// What sh prints for a glob that matched nothing, if the script ever forgets
// to check: it must not become a path to read.
test("parseLedDirs drops an unexpanded glob", () => {
  assert.deepEqual(C.parseLedDirs("/sys/class/leds/*::capslock\n"), []);
});

test("parseLedDirs drops paths outside /sys/class/leds", () => {
  assert.deepEqual(C.parseLedDirs("/tmp/x::capslock\nrelative::capslock"), []);
});

test("parseLedDirs answers nothing with an empty list", () => {
  for (const v of [undefined, null, "", "\n\n"])
    assert.deepEqual(C.parseLedDirs(v), [], String(v));
});

// -------------------------------------------------------------- reading

test("isLit reads a brightness above zero as lit", () => {
  assert.equal(C.isLit("1\n"), true);
  assert.equal(C.isLit("255"), true);
});

test("isLit reads zero, junk and nothing as dark", () => {
  for (const v of ["0\n", "0", "", "  ", "on", undefined, null, "-1"])
    assert.equal(C.isLit(v), false, String(v));
});

test("anyLit is on when any one keyboard is lit", () => {
  assert.equal(C.anyLit([false, true]), true);
  assert.equal(C.anyLit([true]), true);
});

test("anyLit is off with no keyboards, all dark or unread", () => {
  assert.equal(C.anyLit([]), false);
  assert.equal(C.anyLit(null), false);
  assert.equal(C.anyLit([false, false]), false);
  assert.equal(C.anyLit([undefined, null]), false);
});
