import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const N = loadQmlJs("Services/Nightlight.js");

// ------------------------------------------------------------ temperature

test("clampTemperature defaults anything that is not a number to 4000", () => {
  for (const v of [undefined, null, "", "warm", NaN, Infinity, {}])
    assert.equal(N.clampTemperature(v), 4000, String(v));
});

test("clampTemperature keeps a value in range and rounds it", () => {
  assert.equal(N.clampTemperature(3500), 3500);
  assert.equal(N.clampTemperature("3500"), 3500);
  assert.equal(N.clampTemperature(3499.6), 3500);
});

test("clampTemperature pulls an out-of-range value to the nearest end", () => {
  assert.equal(N.clampTemperature(400), 1000);
  assert.equal(N.clampTemperature(-5), 1000);
  assert.equal(N.clampTemperature(9000), 6000);
});

// Zero is a number, so it clamps rather than falling back -- the opposite
// of what `value || 4000` would do.
test("clampTemperature treats zero as too warm, not as unset", () => {
  assert.equal(N.clampTemperature(0), 1000);
});

test("isValidTemperature accepts the whole range, ends included", () => {
  assert.equal(N.isValidTemperature(1000), true);
  assert.equal(N.isValidTemperature(4000), true);
  assert.equal(N.isValidTemperature(6000), true);
});

test("isValidTemperature refuses rather than guessing", () => {
  for (const v of [999, 6001, 400, 40000, 3500.5, NaN, "warm", undefined])
    assert.equal(N.isValidTemperature(v), false, String(v));
});

// --------------------------------------------------------------- parsing

test("parseTemperature reads hyprsunset's answer", () => {
  assert.equal(N.parseTemperature("4000"), 4000);
  assert.equal(N.parseTemperature("4000\n"), 4000);
  assert.equal(N.parseTemperature("  6000  "), 6000);
  assert.equal(N.parseTemperature("4000K"), 4000);
});

// Omarchy's parser takes the first digits anywhere, and this is where that
// goes wrong: the uid in the socket path reads as 1000K.
test("parseTemperature does not read hyprctl's error as a temperature", () => {
  const err = "Couldn't connect to /run/user/1000/hypr/abc_123/.hyprsunset.sock. (3)";
  assert.equal(N.parseTemperature(err), null);
});

test("parseTemperature answers null for nothing at all", () => {
  for (const v of [undefined, null, "", "\n", "ok", "-4000", "40 00"])
    assert.equal(N.parseTemperature(v), null, JSON.stringify(v));
});

// ----------------------------------------------------------------- clock

test("parseClock reads 24-hour times as minutes past midnight", () => {
  assert.equal(N.parseClock("00:00"), 0);
  assert.equal(N.parseClock("07:30"), 450);
  assert.equal(N.parseClock("7:30"), 450);
  assert.equal(N.parseClock(" 20:00 "), 1200);
  assert.equal(N.parseClock("23:59"), 1439);
});

test("parseClock refuses anything else", () => {
  for (const v of ["24:00", "12:60", "8pm", "20", "20:0", "", undefined, null, "-1:00", "120:00"])
    assert.equal(N.parseClock(v), -1, JSON.stringify(v));
});

test("hasSchedule wants two valid, different times", () => {
  assert.equal(N.hasSchedule("20:00", "07:00"), true);
  assert.equal(N.hasSchedule("20:00", "20:00"), false);
  assert.equal(N.hasSchedule("20:00", ""), false);
  assert.equal(N.hasSchedule("", ""), false);
  assert.equal(N.hasSchedule("dusk", "dawn"), false);
});

// -------------------------------------------------------------- schedule

const at = (h, m = 0) => h * 60 + m;

test("a schedule through midnight is on from the start to the end", () => {
  const on = m => N.scheduledOn(m, "20:00", "07:00");
  assert.equal(on(at(19, 59)), false);
  assert.equal(on(at(20, 0)), true);
  assert.equal(on(at(23, 59)), true);
  assert.equal(on(at(0, 0)), true);
  assert.equal(on(at(6, 59)), true);
  assert.equal(on(at(7, 0)), false);
  assert.equal(on(at(12, 0)), false);
});

test("a schedule inside one day is on between its two times", () => {
  const on = m => N.scheduledOn(m, "01:00", "05:30");
  assert.equal(on(at(0, 59)), false);
  assert.equal(on(at(1, 0)), true);
  assert.equal(on(at(5, 29)), true);
  assert.equal(on(at(5, 30)), false);
  assert.equal(on(at(22, 0)), false);
});

test("no schedule is never on", () => {
  for (let m = 0; m < 1440; m += 37)
    assert.equal(N.scheduledOn(m, "", ""), false);
  assert.equal(N.scheduledOn(at(21), "20:00", "20:00"), false);
});

test("scheduledOn wraps minutes outside one day", () => {
  assert.equal(N.scheduledOn(at(21) + 1440, "20:00", "07:00"), true);
  assert.equal(N.scheduledOn(-60, "20:00", "07:00"), true);
});

test("minutesOfDay reads the local clock", () => {
  assert.equal(N.minutesOfDay(new Date(2026, 9, 14, 21, 15, 59)), at(21, 15));
  assert.equal(N.minutesOfDay(new Date(2026, 9, 14, 0, 0, 0)), 0);
});

// ---------------------------------------------------------------- status

const base = { available: true, on: false, temperature: 4000, reported: null, owned: false, start: "", end: "" };

test("statusLine names the fix when hyprsunset is missing", () => {
  const line = N.statusLine({ ...base, available: false });
  assert.match(line, /^unavailable:/);
  assert.match(line, /sudo pacman -S hyprsunset/);
});

test("statusLine says off, and nothing about hyprsunset's number", () => {
  assert.equal(N.statusLine({ ...base, reported: 6000 }), "off");
});

test("statusLine says who is running hyprsunset while it is on", () => {
  assert.equal(N.statusLine({ ...base, on: true, owned: true, reported: 4000 }),
    "on 4000K, hyprsunset started by pshell, hyprsunset reports 4000K");
  assert.equal(N.statusLine({ ...base, on: true, temperature: 3200 }),
    "on 3200K, hyprsunset already running");
});

test("statusLine mentions a schedule only when there is one", () => {
  assert.equal(N.statusLine({ ...base, start: "20:00", end: "07:00" }), "off, schedule 20:00-07:00");
  assert.equal(N.statusLine({ ...base, start: "20:00", end: "nope" }), "off");
});

// ------------------------------------------------------ state transitions

test("seededActive: a running hyprsunset below 6000K with identity off is on", () => {
  assert.equal(N.seededActive("false", "4000"), true);
  assert.equal(N.seededActive("false\n", "\n3500\n"), true);
});

test("seededActive: identity on, 6000K or above, or nothing answering is off", () => {
  assert.equal(N.seededActive("true", "4000"), false);
  assert.equal(N.seededActive("false", "6000"), false);
  assert.equal(N.seededActive("false", "6500"), false);
  assert.equal(N.seededActive("", ""), false);
  assert.equal(N.seededActive("Couldn't connect to /run/user/1000/hypr/x/.hyprsunset.sock. (3)", ""), false);
  assert.equal(N.seededActive(undefined, null), false);
});

test("afterApply: a failed set with nothing of ours running starts one", () => {
  assert.equal(N.afterApply("set", 1, true, false), "start");
});

test("afterApply: a failed set while our child is still up starts no second one", () => {
  assert.equal(N.afterApply("set", 1, true, true), "none");
});

test("afterApply: a set that worked, or one no longer wanted, starts nothing", () => {
  assert.equal(N.afterApply("set", 0, true, false), "none");
  assert.equal(N.afterApply("set", 1, false, false), "none");
});

test("afterApply: a release stops the child only if still off", () => {
  assert.equal(N.afterApply("release", 0, false, true), "stop");
  assert.equal(N.afterApply("release", 0, true, true), "none");
});

test("afterApply: an identity sent to someone else's hyprsunset stops nothing", () => {
  assert.equal(N.afterApply("identity", 0, false, false), "none");
});

// The review's off-then-on race: the release has stopped the child, an on
// arrives while it is still exiting, its `temperature` goes to the dying
// process (and either "works" or fails with the child still counted as
// running), and nothing is started. The child's own exit has to send it
// again.
test("off then on while our hyprsunset is still exiting ends with it started again", () => {
  // The on's set, sent while the dying child still counts as running.
  assert.equal(N.afterApply("set", 0, true, true), "none");
  assert.equal(N.afterApply("set", 1, true, true), "none");
  // Then the child goes: it was asked to, but the nightlight is wanted on.
  assert.equal(N.afterChildExit(true, true), "reapply");
  // And the reapplied set finds nothing, so a new child starts.
  assert.equal(N.afterApply("set", 1, true, false), "start");
});

test("afterChildExit: a child asked to go while off is simply gone", () => {
  assert.equal(N.afterChildExit(true, false), "none");
});

test("afterChildExit: a child that went on its own while wanted is lost", () => {
  assert.equal(N.afterChildExit(false, true), "lost");
  assert.equal(N.afterChildExit(false, false), "none");
});
