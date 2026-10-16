import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const H = loadQmlJs("Services/NotificationHistory.js");

const rec = (over = {}) => ({
  appName: "app",
  desktopEntry: "app",
  summary: "summary",
  body: "body",
  time: 0,
  ...over
});

// ------------------------------------------------------------------ append

test("append puts the new record first", () => {
  const out = H.append([rec({ summary: "old" })], rec({ summary: "new" }), 10);
  assert.equal(out.length, 2);
  assert.equal(out[0].summary, "new");
  assert.equal(out[1].summary, "old");
});

test("append holds the cap at exactly cap", () => {
  let history = [];
  for (let i = 0; i < 7; i++)
    history = H.append(history, rec({ summary: String(i) }), 5);
  assert.equal(history.length, 5);
  // Newest five survive, oldest two fell off the end.
  assert.deepEqual(history.map(r => r.summary), ["6", "5", "4", "3", "2"]);
});

test("append with a cap of 1 keeps only the newest", () => {
  const out = H.append([rec({ summary: "old" })], rec({ summary: "new" }), 1);
  assert.deepEqual(out.map(r => r.summary), ["new"]);
});

test("append with a cap of 0 keeps nothing", () => {
  const out = H.append([rec()], rec(), 0);
  assert.deepEqual(out, []);
});

test("append does not mutate the array it was given", () => {
  const before = [rec({ summary: "old" })];
  H.append(before, rec({ summary: "new" }), 10);
  assert.equal(before.length, 1);
  assert.equal(before[0].summary, "old");
});

test("append treats a missing history as empty", () => {
  const out = H.append(undefined, rec(), 5);
  assert.equal(out.length, 1);
});

// ------------------------------------------------------------------- merge

test("merge keeps notifications that arrived before the file loaded", () => {
  const file = [rec({ id: 2, time: 200, summary: "b" }), rec({ id: 1, time: 100, summary: "a" })];
  const early = [rec({ id: 3, time: 300, summary: "c" })];
  const out = H.merge(file, early, 10);
  assert.deepEqual(out.map(r => r.summary), ["c", "b", "a"]);
});

test("merge orders newest first by arrival, wherever each record came from", () => {
  const file = [rec({ id: 9, time: 500, summary: "file-new" }), rec({ id: 8, time: 100, summary: "file-old" })];
  const carried = [rec({ id: 4, time: 300, summary: "carried" })];
  assert.deepEqual(H.merge(file, carried, 10).map(r => r.summary), ["file-new", "carried", "file-old"]);
});

test("merge drops a duplicate and keeps the newer copy from extra", () => {
  const saved = rec({ id: 1, time: 100, closeReason: 0 });
  const closed = rec({ id: 1, time: 100, closeReason: 2 });
  const out = H.merge([saved], [closed], 10);
  assert.equal(out.length, 1);
  assert.equal(out[0], closed);
});

test("merge dedupes within extra itself, last copy winning", () => {
  const a = rec({ id: 1, time: 100, closeReason: 0 });
  const b = rec({ id: 1, time: 100, closeReason: 1 });
  const out = H.merge([], [a, b], 10);
  assert.equal(out.length, 1);
  assert.equal(out[0], b);
});

test("merge does not treat a reused id from another session as a duplicate", () => {
  const out = H.merge([rec({ id: 1, time: 100 })], [rec({ id: 1, time: 900 })], 10);
  assert.equal(out.length, 2);
});

test("merge respects the history cap, dropping the oldest", () => {
  const file = [rec({ id: 2, time: 200, summary: "b" }), rec({ id: 1, time: 100, summary: "a" })];
  const early = [rec({ id: 3, time: 300, summary: "c" })];
  assert.deepEqual(H.merge(file, early, 2).map(r => r.summary), ["c", "b"]);
  assert.deepEqual(H.merge(file, early, 0), []);
});

test("merge keeps same-millisecond records in their existing order", () => {
  const out = H.merge([], [rec({ id: 2, time: 100, summary: "x" }), rec({ id: 1, time: 100, summary: "y" })], 10);
  assert.deepEqual(out.map(r => r.summary), ["x", "y"]);
});

test("merge returns the record objects themselves and leaves its inputs alone", () => {
  const live = rec({ id: 5, time: 500 });
  const file = [rec({ id: 1, time: 100 })];
  const extra = [live];
  const out = H.merge(file, extra, 10);
  assert.equal(out[0], live);
  assert.equal(file.length, 1);
  assert.equal(extra.length, 1);
});

test("merge skips junk entries and missing lists", () => {
  assert.deepEqual(H.merge(null, undefined, 10), []);
  const out = H.merge([null, 3, rec({ time: 1 })], ["x"], 10);
  assert.equal(out.length, 1);
});

// -------------------------------------------------------------- groupByApp

test("groupByApp groups by desktopEntry and falls back to appName", () => {
  const groups = H.groupByApp([
    rec({ desktopEntry: "firefox", appName: "Firefox", summary: "a" }),
    rec({ desktopEntry: "", appName: "notify-send", summary: "b" }),
    rec({ desktopEntry: "firefox", appName: "Firefox", summary: "c" }),
    rec({ desktopEntry: "", appName: "notify-send", summary: "d" })
  ]);
  assert.equal(groups.length, 2);
  assert.equal(groups[0].key, "firefox");
  assert.deepEqual(groups[0].entries.map(r => r.summary), ["a", "c"]);
  assert.equal(groups[1].key, "notify-send");
  assert.deepEqual(groups[1].entries.map(r => r.summary), ["b", "d"]);
});

test("groupByApp orders groups by their newest member", () => {
  // History is newest first: slack's newest sits above firefox's newest,
  // so slack's group comes first even though firefox has more entries.
  const groups = H.groupByApp([
    rec({ desktopEntry: "slack", summary: "1" }),
    rec({ desktopEntry: "firefox", summary: "2" }),
    rec({ desktopEntry: "firefox", summary: "3" }),
    rec({ desktopEntry: "firefox", summary: "4" })
  ]);
  assert.deepEqual(groups.map(g => g.key), ["slack", "firefox"]);
});

test("groupByApp preserves newest-first order within a group", () => {
  const groups = H.groupByApp([
    rec({ desktopEntry: "mail", summary: "newest" }),
    rec({ desktopEntry: "mail", summary: "middle" }),
    rec({ desktopEntry: "mail", summary: "oldest" })
  ]);
  assert.deepEqual(groups[0].entries.map(r => r.summary), ["newest", "middle", "oldest"]);
});

test("groupByApp merges the same desktopEntry across casings", () => {
  const groups = H.groupByApp([
    rec({ desktopEntry: "Firefox" }),
    rec({ desktopEntry: "firefox" })
  ]);
  assert.equal(groups.length, 1);
});

// ----------------------------------------------------------------- isMuted

test("isMuted matches on desktopEntry", () => {
  assert.equal(H.isMuted(rec({ desktopEntry: "slack" }), ["slack"]), true);
  assert.equal(H.isMuted(rec({ desktopEntry: "slack" }), ["firefox"]), false);
});

test("isMuted is case-insensitive both ways", () => {
  assert.equal(H.isMuted(rec({ desktopEntry: "Slack" }), ["slack"]), true);
  assert.equal(H.isMuted(rec({ desktopEntry: "slack" }), ["Slack"]), true);
});

test("isMuted falls back to appName when desktopEntry is empty", () => {
  assert.equal(H.isMuted(rec({ desktopEntry: "", appName: "notify-send" }), ["notify-send"]), true);
});

test("isMuted with an empty or missing list mutes nothing", () => {
  assert.equal(H.isMuted(rec(), []), false);
  assert.equal(H.isMuted(rec(), undefined), false);
});

// --------------------------------------------------------------- summarise

test("summarise joins app, summary and body on one line", () => {
  assert.equal(H.summarise(rec({ appName: "mail", summary: "New message", body: "hello" })), "mail: New message — hello");
});

test("summarise flattens newlines so one record stays one line", () => {
  assert.equal(H.summarise(rec({ appName: "mail", summary: "a", body: "b\nc\nd" })), "mail: a — b c d");
});

test("summarise with an empty summary and body still names the app", () => {
  const line = H.summarise(rec({ appName: "mail", summary: "", body: "" }));
  assert.equal(line, "mail");
  assert.notEqual(line.trim(), "");
});

test("summarise drops only the missing half", () => {
  assert.equal(H.summarise(rec({ appName: "mail", summary: "s", body: "" })), "mail: s");
  assert.equal(H.summarise(rec({ appName: "mail", summary: "", body: "b" })), "mail: b");
});

// ------------------------------------------------------------ relativeTime

test("relativeTime bands into now, minutes, hours, yesterday, days", () => {
  const now = Date.parse("2026-08-27T12:00:00Z");
  const ago = s => now - s * 1000;
  assert.equal(H.relativeTime(ago(30), now), "now");
  assert.equal(H.relativeTime(ago(3 * 60), now), "3m");
  assert.equal(H.relativeTime(ago(2 * 3600), now), "2h");
  assert.equal(H.relativeTime(ago(30 * 3600), now), "yesterday");
  assert.equal(H.relativeTime(ago(3 * 86400), now), "3d");
});

test("relativeTime holds at its band edges", () => {
  const now = 1000000000000;
  assert.equal(H.relativeTime(now - 59 * 1000, now), "now");
  assert.equal(H.relativeTime(now - 60 * 1000, now), "1m");
  assert.equal(H.relativeTime(now - 3599 * 1000, now), "59m");
  assert.equal(H.relativeTime(now - 3600 * 1000, now), "1h");
  assert.equal(H.relativeTime(now - 86400 * 1000, now), "yesterday");
  assert.equal(H.relativeTime(now - 172800 * 1000, now), "2d");
});
