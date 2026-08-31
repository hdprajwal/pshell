import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const Keybinds = loadQmlJs("Services/Keybinds.js");

// `hyprctl binds -j` on the machine this was written on, pasted verbatim,
// not invented. Twenty-four of the 119 entries, picked to be every trap at
// once: every modmask value the real listing contains, the two mouse binds,
// one of the two `code:NN` binds that report an empty key AND a zero keycode,
// the four that carry a description, and the media key that carries none.
//
// Every one of them says `dispatcher: "__lua"` with a numeric `arg`, which is
// the whole reason this library exists: on a Hyprland driven from Lua, the
// compositor knows which keys are bound and has no words for what they do.
const REAL_BINDS = [
  { modmask: 65, key: "Return", keycode: 0, dispatcher: "__lua", arg: "6", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "Return", keycode: 0, dispatcher: "__lua", arg: "8", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "D", keycode: 0, dispatcher: "__lua", arg: "12", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "TAB", keycode: 0, dispatcher: "__lua", arg: "26", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 65, key: "Slash", keycode: 0, dispatcher: "__lua", arg: "30", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 72, key: "L", keycode: 0, dispatcher: "__lua", arg: "32", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 12, key: "Delete", keycode: 0, dispatcher: "__lua", arg: "36", description: "", has_description: false, submap: "", mouse: false, locked: true, repeat: false },
  { modmask: 0, key: "XF86AudioMute", keycode: 0, dispatcher: "__lua", arg: "42", description: "", has_description: false, submap: "", mouse: false, locked: true, repeat: false },
  { modmask: 69, key: "left", keycode: 0, dispatcher: "__lua", arg: "76", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "down", keycode: 0, dispatcher: "__lua", arg: "82", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "up", keycode: 0, dispatcher: "__lua", arg: "88", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "right", keycode: 0, dispatcher: "__lua", arg: "94", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "H", keycode: 0, dispatcher: "__lua", arg: "100", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "J", keycode: 0, dispatcher: "__lua", arg: "106", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "K", keycode: 0, dispatcher: "__lua", arg: "112", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 69, key: "L", keycode: 0, dispatcher: "__lua", arg: "118", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "mouse_down", keycode: 0, dispatcher: "__lua", arg: "125", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 68, key: "mouse_down", keycode: 0, dispatcher: "__lua", arg: "129", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "mouse:272", keycode: 0, dispatcher: "__lua", arg: "175", description: "Move window", has_description: true, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "mouse:273", keycode: 0, dispatcher: "__lua", arg: "177", description: "Resize window", has_description: true, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "", keycode: 0, dispatcher: "__lua", arg: "179", description: "Expand window left", has_description: true, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 64, key: "", keycode: 0, dispatcher: "__lua", arg: "181", description: "Shrink window left", has_description: true, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 0, key: "Print", keycode: 0, dispatcher: "__lua", arg: "187", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 4, key: "Print", keycode: 0, dispatcher: "__lua", arg: "189", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false },
  { modmask: 8, key: "Print", keycode: 0, dispatcher: "__lua", arg: "191", description: "", has_description: false, submap: "", mouse: false, locked: false, repeat: false }
];

test("every modmask the real listing contains decodes to the right modifiers", () => {
  // The nine values `hyprctl binds -j` actually returns here, counted off the
  // 119 entries: 0, 4, 8, 12, 64, 65, 68, 69, 72.
  assert.deepEqual(Keybinds.decodeModmask(0), []);
  assert.deepEqual(Keybinds.decodeModmask(4), ["CTRL"]);
  assert.deepEqual(Keybinds.decodeModmask(8), ["ALT"]);
  assert.deepEqual(Keybinds.decodeModmask(12), ["CTRL", "ALT"]);
  assert.deepEqual(Keybinds.decodeModmask(64), ["SUPER"]);
  assert.deepEqual(Keybinds.decodeModmask(65), ["SUPER", "SHIFT"]);
  assert.deepEqual(Keybinds.decodeModmask(68), ["SUPER", "CTRL"]);
  assert.deepEqual(Keybinds.decodeModmask(69), ["SUPER", "CTRL", "SHIFT"]);
  assert.deepEqual(Keybinds.decodeModmask(72), ["SUPER", "ALT"]);
});

test("the two bits nothing here binds still decode", () => {
  // 1 and 2 are HL_MODIFIER_SHIFT and HL_MODIFIER_CAPS. Nothing on this
  // machine binds either alone, and the bit table is Hyprland's rather than
  // this machine's, so both are pinned anyway.
  assert.deepEqual(Keybinds.decodeModmask(1), ["SHIFT"]);
  assert.deepEqual(Keybinds.decodeModmask(2), ["CAPS"]);
  assert.deepEqual(Keybinds.decodeModmask(16), ["MOD2"]);
  assert.deepEqual(Keybinds.decodeModmask(32), ["MOD3"]);
  assert.deepEqual(Keybinds.decodeModmask(128), ["MOD5"]);
});

test("the modifier order is SUPER, CTRL, ALT, SHIFT and not the bit order", () => {
  // Pinned because a user's label map is keyed by this string. Reordering
  // the table would silently invalidate every label they have written.
  assert.equal(Keybinds.decodeModmask(77).join("+"), "SUPER+CTRL+ALT+SHIFT");
  assert.equal(Keybinds.normaliseKey({ modmask: 65, key: "Return" }), "SUPER+SHIFT+Return");
  assert.notEqual(Keybinds.normaliseKey({ modmask: 65, key: "Return" }), "SHIFT+SUPER+Return");
});

test("a bit outside Hyprland's table is reported, not dropped", () => {
  // A ninth modifier in some future Hyprland must not make this print a
  // combination missing a key you have to hold down.
  assert.deepEqual(Keybinds.decodeModmask(64 + 256), ["SUPER", "UNKNOWN(256)"]);
  assert.deepEqual(Keybinds.decodeModmask(1024), ["UNKNOWN(1024)"]);
});

test("junk for a modmask is no modifiers rather than a throw", () => {
  assert.deepEqual(Keybinds.decodeModmask(undefined), []);
  assert.deepEqual(Keybinds.decodeModmask(null), []);
  assert.deepEqual(Keybinds.decodeModmask("nonsense"), []);
  assert.deepEqual(Keybinds.decodeModmask(-4), []);
});

test("a mouse bind keeps Hyprland's own token", () => {
  // "SUPER+mouse:272" is also what the user typed in their Hyprland config,
  // so the label-map key round-trips rather than needing translation.
  assert.equal(Keybinds.normaliseKey({ modmask: 64, key: "mouse:272" }), "SUPER+mouse:272");
  assert.equal(Keybinds.normaliseKey({ modmask: 68, key: "mouse_down" }), "SUPER+CTRL+mouse_down");
});

test("a bind with no key at all normalises to its modifiers and a question mark", () => {
  // Hyprland reports an empty `key` and `keycode: 0` for a `code:NN` bind, so
  // there is nothing left to name it with. Two of them under the same
  // modifiers therefore collide on one map key -- documented, not fixable
  // from this end, and the reason the panel's fix sentence points at the Lua
  // side as well.
  const first = { modmask: 64, key: "", keycode: 0 };
  const second = { modmask: 64, key: "", keycode: 0 };
  assert.equal(Keybinds.normaliseKey(first), "SUPER+?");
  assert.equal(Keybinds.normaliseKey(second), Keybinds.normaliseKey(first));
  assert.equal(Keybinds.normaliseKey({ modmask: 0, key: "" }), "?");
});

test("describe prefers Hyprland's own words", () => {
  const bind = { modmask: 64, key: "mouse:272", description: "Move window", has_description: true };
  const said = Keybinds.describe(bind, { "SUPER+mouse:272": "something else" });
  assert.equal(said.source, "hyprland");
  assert.equal(said.text, "Move window");
});

test("describe falls back to the label map, case-insensitively", () => {
  const bind = { modmask: 64, key: "D", description: "", has_description: false };
  const said = Keybinds.describe(bind, { "super+d": "Launcher" });
  assert.equal(said.source, "label");
  assert.equal(said.text, "Launcher");
});

test("describe says unlabelled rather than inventing something", () => {
  // The trap this whole ruling exists for: the dispatcher is "__lua" and the
  // arg is "12". Neither may reach the screen.
  const bind = { modmask: 64, key: "D", dispatcher: "__lua", arg: "12", description: "", has_description: false };
  const said = Keybinds.describe(bind, {});
  assert.equal(said.source, "none");
  assert.ok(!said.text.includes("__lua"));
  assert.ok(!said.text.includes("12"));

  // An empty label counts as no label, not as a blank description.
  assert.equal(Keybinds.describe(bind, { "SUPER+D": "   " }).source, "none");
  assert.equal(Keybinds.describe(bind, null).source, "none");
});

test("a description Hyprland reports as present but empty is not a description", () => {
  const bind = { modmask: 64, key: "Y", description: "", has_description: true };
  assert.equal(Keybinds.describe(bind, {}).source, "none");
});

test("grouping the real binds keeps every one of them", () => {
  const groups = Keybinds.group(REAL_BINDS, {});
  const counted = Keybinds.countUnlabelled(groups);
  assert.equal(counted.total, REAL_BINDS.length);
  // The four with a description are the four Hyprland can describe; the rest
  // are Lua closures.
  assert.equal(counted.unlabelled, REAL_BINDS.length - 4);
});

test("groups come out in modifier-count order, then SUPER, CTRL, ALT, SHIFT", () => {
  // Within a tier the modifier order decides, so SUPER's fifty binds open the
  // sheet and ALT's one is further down. Across tiers the count decides, so
  // the three-modifier groups are last.
  const titles = Keybinds.group(REAL_BINDS, {}).map(g => g.title);
  assert.deepEqual(titles, [
    "No modifier",
    "SUPER",
    "CTRL",
    "ALT",
    "SUPER+CTRL",
    "SUPER+ALT",
    "SUPER+SHIFT",
    "CTRL+ALT",
    "SUPER+CTRL+SHIFT"
  ]);
});

test("a submap's binds get their own group, after the root ones", () => {
  // Every bind on this machine is in the root submap today. A submap is a
  // mode, though: its binds only fire once you are in it, so mixing them into
  // the root list would have the sheet lying about what the key does now.
  const withSubmap = REAL_BINDS.concat([
    { modmask: 0, key: "escape", keycode: 0, dispatcher: "__lua", arg: "900", description: "", has_description: false, submap: "resize", mouse: false },
    { modmask: 0, key: "H", keycode: 0, dispatcher: "__lua", arg: "902", description: "Narrower", has_description: true, submap: "resize", mouse: false }
  ]);
  const groups = Keybinds.group(withSubmap, {});
  const titles = groups.map(g => g.title);

  assert.equal(titles[titles.length - 1], "submap resize · No modifier");
  assert.ok(titles.indexOf("submap resize · No modifier") > titles.indexOf("No modifier"));
  assert.equal(Keybinds.countUnlabelled(groups).total, withSubmap.length);
  assert.equal(groups[groups.length - 1].rows.length, 2);
  assert.equal(groups[groups.length - 1].unlabelled, 1);
});

test("rows inside a group are sorted by key and carry their source", () => {
  const groups = Keybinds.group(REAL_BINDS, { "SUPER+D": "Launcher" });
  const superGroup = groups.find(g => g.title === "SUPER");
  const keys = superGroup.rows.map(r => r.key);
  assert.deepEqual(keys, [...keys].sort((a, b) => a.toLowerCase() < b.toLowerCase() ? -1 : (a.toLowerCase() > b.toLowerCase() ? 1 : 0)));

  const launcher = superGroup.rows.find(r => r.combo === "SUPER+D");
  assert.equal(launcher.description, "Launcher");
  assert.equal(launcher.source, "label");
  // One label was given, so one fewer row is unlabelled than the group has
  // rows without a Hyprland description.
  const move = superGroup.rows.find(r => r.combo === "SUPER+mouse:272");
  assert.equal(move.source, "hyprland");
});

test("group survives being handed nothing", () => {
  assert.deepEqual(Keybinds.group(null, {}), []);
  assert.deepEqual(Keybinds.group([], null), []);
  assert.deepEqual(Keybinds.countUnlabelled(null), { total: 0, unlabelled: 0 });
  // A bind object with nothing in it still lands somewhere rather than
  // disappearing: "?" under no modifier, unlabelled.
  const groups = Keybinds.group([{}], {});
  assert.equal(groups.length, 1);
  assert.equal(groups[0].rows[0].combo, "?");
  assert.equal(groups[0].rows[0].source, "none");
});

test("the filter matches the combination and the description both", () => {
  const groups = Keybinds.group(REAL_BINDS, { "SUPER+D": "Launcher" });

  const byCombo = Keybinds.filter(groups, "mouse");
  assert.equal(Keybinds.countUnlabelled(byCombo).total, 4);

  const byWords = Keybinds.filter(groups, "launch");
  assert.equal(Keybinds.countUnlabelled(byWords).total, 1);
  assert.equal(byWords[0].rows[0].combo, "SUPER+D");

  // Case-insensitive, and an empty query is not a filter.
  assert.equal(Keybinds.countUnlabelled(Keybinds.filter(groups, "MOVE WINDOW")).total, 1);
  assert.equal(Keybinds.filter(groups, "   ").length, groups.length);
  assert.equal(Keybinds.filter(groups, "no such bind").length, 0);
});

test("the filter does not match pshell's own words for an undescribed row", () => {
  // The placeholder is text this library wrote, not the user's, so searching
  // it answered a question nobody asked: on the real 119 binds, typing "lab"
  // or "not" returned all 115 undescribed rows at once.
  const groups = Keybinds.group(REAL_BINDS, { "SUPER+D": "Labelled by hand" });

  assert.equal(Keybinds.countUnlabelled(Keybinds.filter(groups, "not label")).total, 0);
  assert.equal(Keybinds.countUnlabelled(Keybinds.filter(groups, "lab")).total, 1);
  assert.equal(Keybinds.filter(groups, "lab")[0].rows[0].combo, "SUPER+D");

  // An undescribed row is still reachable by its combination, which is the
  // only thing about it that is true.
  const byCombo = Keybinds.filter(groups, "SUPER+TAB");
  assert.equal(Keybinds.countUnlabelled(byCombo).total, 1);
  assert.equal(byCombo[0].rows[0].source, "none");
});
