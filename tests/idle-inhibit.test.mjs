import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const I = loadQmlJs("Services/IdleInhibit.js");

// 2026-10-29 14:00 local, a fixed "now" for every clock test.
const now = new Date(2026, 9, 29, 14, 0, 0).getTime();

// ------------------------------------------------------------ clock time

test("endOfClock reads a later time today as today", () => {
    assert.equal(I.endOfClock("18:30", now), new Date(2026, 9, 29, 18, 30).getTime());
});

test("endOfClock reads a time already past as tomorrow", () => {
    assert.equal(I.endOfClock("09:15", now), new Date(2026, 9, 30, 9, 15).getTime());
});

test("endOfClock reads the current minute as tomorrow, never as zero time", () => {
    assert.equal(I.endOfClock("14:00", now), new Date(2026, 9, 30, 14, 0).getTime());
});

test("endOfClock takes a one-digit hour and surrounding space", () => {
    assert.equal(I.endOfClock(" 9:05 ", now), new Date(2026, 9, 30, 9, 5).getTime());
});

test("endOfClock refuses anything that is not a 24-hour HH:MM", () => {
    for (const v of ["", "18", "18:3", "24:00", "12:60", "6pm", "18:30:00", undefined, null])
        assert.equal(I.endOfClock(v, now), -1, String(v));
});

// ------------------------------------------------------------- time left

test("formatLeft rounds up to whole minutes", () => {
    assert.equal(I.formatLeft(1), "1m");
    assert.equal(I.formatLeft(59 * 1000), "1m");
    assert.equal(I.formatLeft(45 * 60000), "45m");
});

test("formatLeft splits hours and drops a zero minute part", () => {
    assert.equal(I.formatLeft(72 * 60000), "1h 12m");
    assert.equal(I.formatLeft(120 * 60000), "2h");
    assert.equal(I.formatLeft(119 * 60000 + 1), "2h");
});

test("formatLeft says nothing is left at or past the end", () => {
    assert.equal(I.formatLeft(0), "0m");
    assert.equal(I.formatLeft(-5000), "0m");
});
