import test from "node:test";
import assert from "node:assert/strict";
import { loadConfigPath } from "./load-qml-js.mjs";

const Cfg = loadConfigPath();

test("setPath writes a top-level key", () => {
  const next = Cfg.setPath({ position: "top" }, "position", "bottom");
  assert.equal(next.position, "bottom");
});

test("setPath does not mutate the object it was given", () => {
  const before = { position: "top" };
  Cfg.setPath(before, "position", "bottom");
  assert.equal(before.position, "top");
});

test("setPath writes into an existing nested object", () => {
  const next = Cfg.setPath({ shell: { "popups.border": "foreground" } }, "shell.popups.border", "accent");
  assert.equal(next.shell["popups.border"], "accent");
});

test("setPath creates the intermediate object when it is missing", () => {
  const next = Cfg.setPath({}, "shell.popups.border", "accent");
  assert.deepEqual(next, { shell: { "popups.border": "accent" } });
});

test("setPath copies siblings rather than dropping them", () => {
  const next = Cfg.setPath({ size: 30, shell: { a: 1 } }, "shell.b", 2);
  assert.equal(next.size, 30);
  assert.equal(next.shell.a, 1);
  assert.equal(next.shell.b, 2);
});

test("setPath refuses to walk through a non-object and leaves the config alone", () => {
  const before = { margin: 4 };
  const next = Cfg.setPath(before, "margin.top", 8);
  assert.deepEqual(next, { margin: 4 });
});

test("getPath reads a nested value and returns undefined for a missing one", () => {
  assert.equal(Cfg.getPath({ shell: { a: 1 } }, "shell.a"), 1);
  assert.equal(Cfg.getPath({ shell: { a: 1 } }, "shell.b"), undefined);
  assert.equal(Cfg.getPath({}, "a.b.c"), undefined);
});

// ---------------------------------------------------------- widget entries

const LAYOUT = {
  left: [{ type: "workspaces" }],
  center: [{ type: "calendar", format: "HH:mm" }],
  right: [{ type: "network", showName: true }, { type: "clock" }]
};

test("findWidget locates a built-in by its type", () => {
  assert.deepEqual(Cfg.findWidget(LAYOUT, "network"), { section: "right", index: 0 });
  assert.deepEqual(Cfg.findWidget(LAYOUT, "workspaces"), { section: "left", index: 0 });
});

test("findWidget locates an on-disk widget by its id", () => {
  const data = { right: [{ id: "acme.weather", type: "weather" }] };
  assert.deepEqual(Cfg.findWidget(data, "acme.weather"), { section: "right", index: 0 });
});

test("findWidget returns null for a widget that is not in the bar", () => {
  assert.equal(Cfg.findWidget(LAYOUT, "bluetooth"), null);
});

test("setWidgetSetting rewrites only the entry it found", () => {
  const next = Cfg.setWidgetSetting(LAYOUT, "network", "maxNetworks", 12);
  assert.equal(next.right[0].maxNetworks, 12);
  assert.equal(next.right[0].showName, true);
  assert.equal(next.right[1].type, "clock");
  assert.equal(next.center[0].format, "HH:mm");
});

test("setWidgetSetting does not mutate the config it was given", () => {
  Cfg.setWidgetSetting(LAYOUT, "network", "maxNetworks", 12);
  assert.equal(LAYOUT.right[0].maxNetworks, undefined);
});

test("setWidgetSetting on an absent widget returns the config unchanged", () => {
  const next = Cfg.setWidgetSetting(LAYOUT, "bluetooth", "x", 1);
  assert.deepEqual(next, LAYOUT);
});

test("parseObject returns the object a valid file holds", () => {
  assert.deepEqual(Cfg.parseObject('{"position": "top", "right": []}'), { position: "top", right: [] });
  assert.deepEqual(Cfg.parseObject("{}"), {});
});

test("parseObject rejects text that is not JSON", () => {
  assert.equal(Cfg.parseObject('{"position": "top",}'), null);
  assert.equal(Cfg.parseObject(""), null);
  assert.equal(Cfg.parseObject("{"), null);
});

test("parseObject rejects valid JSON that is not an object", () => {
  for (const text of ["null", "42", '"top"', "true", "[]", '[{"type": "clock"}]'])
    assert.equal(Cfg.parseObject(text), null, text);
});
