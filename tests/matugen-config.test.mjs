import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const Matugen = loadQmlJs("Services/MatugenConfig.js");

// A small parser for the TOML subset buildConfig emits: comments, table
// headers with possibly-quoted dotted keys, basic-string values and the
// inline tables the custom colours use. Asserting on parsed structure rather
// than whole-file equality means adding one more template does not rewrite
// every test here -- only the tests about that template.
function parseToml(text) {
  const sections = {};
  let current = null;

  const unquote = s => {
    if (s.startsWith('"') && s.endsWith('"'))
      return s.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    return s;
  };

  const parseValue = raw => {
    const v = raw.trim();
    if (v === "true") return true;
    if (v === "false") return false;
    if (v.startsWith("{") && v.endsWith("}")) {
      const inner = {};
      // Inline-table values here are strings or booleans, never nested, so
      // splitting on commas outside quotes is enough.
      for (const part of v.slice(1, -1).split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/)) {
        const at = part.indexOf("=");
        inner[part.slice(0, at).trim()] = parseValue(part.slice(at + 1));
      }
      return inner;
    }
    return unquote(v);
  };

  for (const line of text.split("\n")) {
    const t = line.trim();
    if (t === "" || t.startsWith("#"))
      continue;
    const header = t.match(/^\[(.+)\]$/);
    if (header) {
      // A dotted header key may hold a quoted part with dots inside it.
      const parts = header[1].match(/"(?:[^"\\]|\\.)*"|[^.]+/g).map(unquote);
      current = parts.join(".");
      sections[current] = {};
      continue;
    }
    const at = t.indexOf("=");
    assert.notEqual(at, -1, `unparseable line: ${t}`);
    assert.notEqual(current, null, `key before any section: ${t}`);
    sections[current][t.slice(0, at).trim()] = parseValue(t.slice(at + 1));
  }
  return sections;
}

const OPTIONS = {
  shellDir: "/opt/pshell",
  configDir: "/home/u/.config",
  home: "/home/u",
  userTemplateDir: "/home/u/.config/pshell/templates",
  userTemplates: [],
  disabled: []
};

// Ten since Phase 5 added walker, on top of the nine Phase 3 left; a name
// missing here is a built-in the assertions below silently stop covering, so
// the list tracks BUILTIN_TEMPLATES by hand and on purpose.
const BUILTINS = ["gtk3", "gtk4", "kitty", "ghostty", "alacritty", "btop", "zed", "qtct", "swayosd", "walker"];

test("every built-in template appears, reading from the shell and writing under the config dir", () => {
  const toml = parseToml(Matugen.buildConfig(OPTIONS));
  for (const name of BUILTINS) {
    const section = toml[`templates.pshell_${name}`];
    assert.ok(section, `missing [templates.pshell_${name}]`);
    assert.match(section.input_path, /^\/opt\/pshell\/assets\/matugen\/templates\//);
    assert.match(section.output_path, /^\/home\/u\/\.config\//);
  }
});

test("gtk3 and gtk4 render the same template to different outputs", () => {
  const toml = parseToml(Matugen.buildConfig(OPTIONS));
  assert.equal(toml["templates.pshell_gtk3"].input_path, toml["templates.pshell_gtk4"].input_path);
  assert.notEqual(toml["templates.pshell_gtk3"].output_path, toml["templates.pshell_gtk4"].output_path);
});

// walker is the one built-in whose output is a file *inside* a directory
// named for the theme rather than a file named for it. Write
// themes/pshell.css instead and matugen still renders happily, walker still
// starts, and the launcher silently wears its stock colours -- so the shape
// of the path is worth an assertion of its own.
test("walker renders into a theme directory, which is what walker looks for", () => {
  const toml = parseToml(Matugen.buildConfig(OPTIONS));
  assert.equal(toml["templates.pshell_walker"].output_path, "/home/u/.config/walker/themes/pshell/style.css");
});

test("all sixteen ansi custom colours appear, each blended", () => {
  const toml = parseToml(Matugen.buildConfig(OPTIONS));
  const custom = toml["config.custom_colors"];
  assert.ok(custom, "missing [config.custom_colors]");
  for (let i = 0; i < 16; i++) {
    const entry = custom[`ansi_${i}`];
    assert.ok(entry, `missing ansi_${i}`);
    assert.match(entry.color, /^#[0-9a-f]{6}$/);
    assert.equal(entry.blend, true);
  }
});

test("a path containing a double quote survives escaping and parses back", () => {
  const toml = parseToml(Matugen.buildConfig({ ...OPTIONS, shellDir: '/odd/"quoted"/pshell' }));
  assert.equal(toml["templates.pshell_kitty"].input_path, '/odd/"quoted"/pshell/assets/matugen/templates/kitty.conf');
});

test("a path containing a single quote is emitted intact", () => {
  // The reason for basic strings over literal ones: an apostrophe in a path
  // would end a single-quoted TOML string early.
  const toml = parseToml(Matugen.buildConfig({ ...OPTIONS, configDir: "/home/o'brien/.config" }));
  assert.equal(toml["templates.pshell_btop"].output_path, "/home/o'brien/.config/btop/themes/pshell.theme");
});

test("disabling kitty removes its section and leaves the other nine", () => {
  const toml = parseToml(Matugen.buildConfig({ ...OPTIONS, disabled: ["kitty"] }));
  assert.equal(toml["templates.pshell_kitty"], undefined);
  for (const name of BUILTINS.filter(n => n !== "kitty"))
    assert.ok(toml[`templates.pshell_${name}`], `disabled kitty took pshell_${name} with it`);
});

test("a user template appends after the built-ins, reading from the user template dir", () => {
  const raw = Matugen.buildConfig({
    ...OPTIONS,
    userTemplates: [{ name: "waybar", input: "waybar.css", output: "/home/u/.config/waybar/colors.css" }]
  });
  const toml = parseToml(raw);
  const section = toml["templates.pshell_user_waybar"];
  assert.ok(section, "missing user template section");
  assert.equal(section.input_path, "/home/u/.config/pshell/templates/waybar.css");
  assert.ok(raw.indexOf("pshell_user_waybar") > raw.lastIndexOf("pshell_qtct"), "user template did not come after the built-ins");
});

test("a leading ~/ in a user output expands to home; a ~ elsewhere is left alone", () => {
  const toml = parseToml(Matugen.buildConfig({
    ...OPTIONS,
    userTemplates: [
      { name: "a", input: "a.css", output: "~/colors/a.css" },
      { name: "b", input: "b.css", output: "/data/~backup/b.css" }
    ]
  }));
  assert.equal(toml["templates.pshell_user_a"].output_path, "/home/u/colors/a.css");
  assert.equal(toml["templates.pshell_user_b"].output_path, "/data/~backup/b.css");
});

test("a user postHook emits post_hook; its absence emits none", () => {
  const toml = parseToml(Matugen.buildConfig({
    ...OPTIONS,
    userTemplates: [
      { name: "hooked", input: "h.css", output: "/tmp/h.css", postHook: "touch /tmp/done" },
      { name: "plain", input: "p.css", output: "/tmp/p.css" }
    ]
  }));
  assert.equal(toml["templates.pshell_user_hooked"].post_hook, "touch /tmp/done");
  assert.equal(toml["templates.pshell_user_plain"].post_hook, undefined);
});

test("kitty reloads through a post_hook that tolerates no kitty running", () => {
  const toml = parseToml(Matugen.buildConfig(OPTIONS));
  const hook = toml["templates.pshell_kitty"].post_hook;
  assert.ok(hook, "kitty has no post_hook");
  assert.ok(hook.includes("|| true"), "kitty's post_hook would report pkill's exit as a matugen failure");
});

test("only kitty has a post_hook among the built-ins", () => {
  const toml = parseToml(Matugen.buildConfig(OPTIONS));
  for (const name of BUILTINS.filter(n => n !== "kitty"))
    assert.equal(toml[`templates.pshell_${name}`].post_hook, undefined, `pshell_${name} grew a post_hook`);
});

test("a user template name that is not a bare TOML key is quoted, not emitted broken", () => {
  const toml = parseToml(Matugen.buildConfig({
    ...OPTIONS,
    userTemplates: [{ name: "my theme", input: "t.css", output: "/tmp/t.css" }]
  }));
  assert.ok(toml["templates.pshell_user_my theme"], "quoted section key did not parse back");
});

test("two user templates sharing a name emit one section, and the first wins", () => {
  const raw = Matugen.buildConfig({
    ...OPTIONS,
    userTemplates: [
      { name: "w", input: "first.css", output: "/tmp/first.css" },
      { name: "w", input: "second.css", output: "/tmp/second.css" }
    ]
  });
  // Counted on the raw text: a duplicate table would overwrite silently in
  // parseToml, which is exactly how this bug hid from structural assertions.
  const headers = raw.split("\n").filter(l => l === "[templates.pshell_user_w]");
  assert.equal(headers.length, 1, "duplicate name emitted two sections — matugen rejects that whole config");
  const toml = parseToml(raw);
  assert.equal(toml["templates.pshell_user_w"].input_path, "/home/u/.config/pshell/templates/first.css");
});

test("a user template named after a built-in neither displaces nor duplicates it", () => {
  const raw = Matugen.buildConfig({
    ...OPTIONS,
    userTemplates: [{ name: "kitty", input: "kitty.conf", output: "/tmp/kitty.conf" }]
  });
  for (const section of ["[templates.pshell_kitty]", "[templates.pshell_user_kitty]"]) {
    const count = raw.split("\n").filter(l => l === section).length;
    assert.equal(count, 1, `${section} appeared ${count} times`);
  }
  const toml = parseToml(raw);
  // The built-in kept its own definition -- hook included -- and the user's
  // landed beside it under its own name.
  assert.ok(toml["templates.pshell_kitty"].post_hook.includes("|| true"));
  assert.equal(toml["templates.pshell_kitty"].input_path, "/opt/pshell/assets/matugen/templates/kitty.conf");
  assert.equal(toml["templates.pshell_user_kitty"].input_path, "/home/u/.config/pshell/templates/kitty.conf");
  assert.equal(toml["templates.pshell_user_kitty"].post_hook, undefined);
});

test("scheme and prefer validation accept matugen's lists and nothing else", () => {
  assert.equal(Matugen.isValidScheme("scheme-tonal-spot"), true);
  assert.equal(Matugen.isValidScheme("scheme-vibrant"), true);
  assert.equal(Matugen.isValidScheme("tonal-spot"), false);
  assert.equal(Matugen.isValidPrefer("saturation"), true);
  assert.equal(Matugen.isValidPrefer("less-saturation"), true);
  assert.equal(Matugen.isValidPrefer("hue"), false);
});
