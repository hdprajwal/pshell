import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, existsSync, writeFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./load-qml-js.mjs";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// The templates, rendered by the real matugen and then handed to the real
// applications to parse.
//
// matugen-config.test.mjs already proves the config we hand matugen is the
// config we meant. It cannot prove the far more interesting thing: that what
// comes out the other side is a file kitty, ghostty, GTK, zed, alacritty,
// qt6ct and btop will actually accept. A template with a misspelled key or a
// colour in the wrong notation renders perfectly and produces a themed
// desktop that silently ignores it -- which is exactly the failure this
// whole sub-project exists to avoid, and exactly the failure no amount of
// asserting on our own output can catch.
//
// So every check here goes through the consuming application's own parser
// where one can be reached without a display: `ghostty +validate-config`,
// kitty's `load_config`, GTK's CssProvider. Where no parser is reachable the
// check is against the format's own stock files on this machine -- btop's
// themes, qt6ct's colour schemes -- rather than against our idea of the
// format.

// --------------------------------------------------------------- rendering

// A source colour, not an image. `matugen image` needs a fixture to commit
// and, on an image with several candidate source colours, refuses to guess
// without --prefer. `matugen color` takes the source colour directly, so the
// palette is deterministic and the test carries no binary.
const SOURCE = "#3b6ea5";

function have(command) {
    return spawnSync("sh", ["-c", `command -v ${command} >/dev/null 2>&1`]).status === 0;
}

// Rendered once per mode and reused: matugen is a process spawn per call and
// eight of these tests want the same eight files.
const rendered = {};

function render(mode) {
    if (rendered[mode])
        return rendered[mode];

    const root = mkdtempSync(join(tmpdir(), "pshell-theme-"));
    const configDir = join(root, "cfg");

    const MatugenConfig = loadQmlJs("Services/MatugenConfig.js");
    const toml = MatugenConfig.buildConfig({
        shellDir: repo,
        configDir,
        home: join(root, "home"),
        userTemplateDir: join(root, "templates"),
        userTemplates: [],
        disabled: []
    });

    // Every post_hook stripped before matugen ever sees this.
    //
    // matugen's -p prefixes output paths but does not suppress hooks, so a
    // config left intact would run `pkill -SIGUSR1 -x kitty` against whatever
    // kitty windows the person running the tests happens to have open. A test
    // suite must not reach out of its sandbox and poke the developer's
    // terminals, however harmlessly. That the real config still carries the
    // hook is asserted separately, on the text, below.
    const hookless = toml.split("\n").filter(line => !line.trim().startsWith("post_hook")).join("\n");

    const configPath = join(root, "matugen.toml");
    writeFileSync(configPath, hookless);

    const result = spawnSync("matugen", ["-c", configPath, "color", "hex", SOURCE, "--mode", mode], { encoding: "utf8" });

    rendered[mode] = { root, configDir, toml, hookless, result };
    return rendered[mode];
}

function output(mode, relative) {
    return join(render(mode).configDir, relative);
}

function read(mode, relative) {
    return readFileSync(output(mode, relative), "utf8");
}

// Skipping rather than failing when matugen is absent: the theming feature is
// documented as needing it and degrading without it, so a machine without
// matugen is a supported machine, not a broken one.
const noMatugen = !have("matugen");

// Hand a stylesheet to GTK4's own parser and collect what it complains about.
//
// The `parsing-error` signal, not the return value. CssProvider.load_from_path
// does not raise on bad CSS -- GTK's parser recovers from almost anything,
// drops the rule it could not read and carries on, so a stylesheet full of
// syntax errors "loads" fine and themes nothing. A mutation test proved it:
// replacing a whole @define-color line with `;;;` passed. The signal is where
// GTK actually reports the problem.
//
// Returns null when PyGObject is not installed, which the callers treat as
// "not checked here" rather than as a pass.
function gtkParseErrors(path) {
    const script = `import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib
errors = []
p = Gtk.CssProvider()
p.connect("parsing-error", lambda prov, section, error: errors.append(error.message))
p.load_from_path("${path}")
print("ERRORS", len(errors))
for e in errors:
    print("  ", e)`;
    const result = spawnSync("python3", ["-c", script], { encoding: "utf8" });
    if (result.status !== 0 && /ModuleNotFoundError|ValueError: Namespace/.test(result.stderr))
        return null;
    assert.equal(result.status, 0, `GTK could not load the stylesheet at all: ${result.stderr}`);
    return result.stdout;
}

test("the real config carries kitty's reload hook, even though the rendered one does not", () => {
    const MatugenConfig = loadQmlJs("Services/MatugenConfig.js");
    const toml = MatugenConfig.buildConfig({
        shellDir: repo,
        configDir: "/nonexistent",
        home: "/nonexistent",
        userTemplateDir: "/nonexistent",
        userTemplates: [],
        disabled: []
    });
    assert.match(toml, /post_hook\s*=\s*"pkill -SIGUSR1 -x kitty \|\| true"/);
});

test("matugen renders every template with real colours", { skip: noMatugen && "matugen not installed" }, () => {
    const { result, configDir } = render("dark");
    assert.equal(result.status, 0, `matugen failed: ${result.stderr}`);

    const expected = [
        "gtk-3.0/pshell-colors.css",
        "gtk-4.0/pshell-colors.css",
        "kitty/pshell-colors.conf",
        "ghostty/themes/pshell",
        "alacritty/pshell-colors.toml",
        "btop/themes/pshell.theme",
        "zed/themes/pshell.json",
        "qt6ct/colors/pshell.conf",
        "swayosd/style.css",
        "walker/themes/pshell/style.css",
        // Beside the stylesheet, not instead of it: walker resolves a theme's
        // files one at a time, so the theme directory has to hold both or the
        // hints go back to walker's two-line stacking.
        "walker/themes/pshell/keybind.xml"
    ];

    for (const relative of expected) {
        const path = join(configDir, relative);
        assert.ok(existsSync(path), `${relative} was not rendered`);
        const text = readFileSync(path, "utf8");
        assert.ok(!text.includes("{{"), `${relative} still holds an unrendered placeholder`);
        // keybind.xml is the one output with nothing to colour: it exists to
        // change a box's orientation, which GTK4 exposes no CSS for. Every
        // other template that rendered no hex has silently lost its palette,
        // so the check stays for the rest.
        if (!relative.endsWith(".xml"))
            assert.match(text, /#[0-9a-fA-F]{6}/, `${relative} holds no hex colour`);
    }
});

test("gtk3 and gtk4 render byte-identically from the one template", { skip: noMatugen && "matugen not installed" }, () => {
    assert.equal(read("dark", "gtk-3.0/pshell-colors.css"), read("dark", "gtk-4.0/pshell-colors.css"));
});

// ------------------------------------------------- the applications' parsers

test("ghostty accepts its theme", { skip: (noMatugen && "matugen not installed") || (!have("ghostty") && "ghostty not installed") }, () => {
    const path = output("dark", "ghostty/themes/pshell");
    const result = spawnSync("ghostty", ["+validate-config", `--config-file=${path}`], { encoding: "utf8" });
    assert.equal(result.status, 0, `ghostty rejected it: ${result.stdout}${result.stderr}`);
});

test("kitty takes every key in its theme and reads our colours back", { skip: (noMatugen && "matugen not installed") || (!have("kitty") && "kitty not installed") }, () => {
    const path = output("dark", "kitty/pshell-colors.conf");

    // Two assertions, because either alone passes on a broken template.
    //
    // kitty's loader does not fail on a key it does not recognise -- it logs
    // "Ignoring unknown config key" and carries on -- so a misspelled
    // `forergound` parses cleanly and silently leaves the colour at kitty's
    // built-in default. Checking only that the file loads therefore proves
    // nothing about whether kitty used any of it. So: no ignored keys, and
    // the colours kitty ends up holding are the ones in the file.
    const script = `from kitty.config import load_config
c = load_config("${path}")
for name in ("foreground", "background", "color0", "color1", "color15", "cursor"):
    v = getattr(c, name)
    print("%s=#%02x%02x%02x" % (name, v.red, v.green, v.blue))`;
    const result = spawnSync("kitty", ["+runpy", script], { encoding: "utf8" });
    assert.equal(result.status, 0, `kitty rejected it: ${result.stderr}`);

    const noise = `${result.stdout}${result.stderr}`;
    assert.doesNotMatch(noise, /Ignoring unknown config key/, `kitty ignored a key in our template: ${noise}`);

    const file = readFileSync(path, "utf8");
    for (const [, name, value] of result.stdout.matchAll(/^(\w+)=(#[0-9a-f]{6})$/gm)) {
        const inFile = (file.match(new RegExp(`^${name}\\s+(#[0-9a-fA-F]{6})`, "m")) || [])[1];
        assert.ok(inFile, `kitty reported ${name} but the template never sets it`);
        assert.equal(value, inFile.toLowerCase(), `kitty read ${name} as ${value} but the file says ${inFile} — the key is not the one kitty uses`);
    }
});

test("GTK parses the stylesheet it is handed", { skip: (noMatugen && "matugen not installed") || (!have("python3") && "python3 not installed") }, () => {
    const out = gtkParseErrors(output("dark", "gtk-4.0/pshell-colors.css"));
    if (out === null)
        return; // No PyGObject here; the format is checked by the apps that do have a parser.
    assert.match(out, /^ERRORS 0$/m, `GTK reported parse errors in our stylesheet:\n${out}`);
});

test("GTK parses the swayosd stylesheet", { skip: (noMatugen && "matugen not installed") || (!have("python3") && "python3 not installed") }, () => {
    // Weaker than the checks above, and honestly so: swayosd is not
    // installed on this machine, so nothing here can prove it *applies*
    // these rules -- GTK's CSS parser accepts any selector, including a
    // misspelled node name that would theme nothing. What contains that
    // risk is the template itself: every selector in it is copied verbatim
    // from swayosd 0.3.1's own data/style/style.scss rather than written
    // from memory. What this test does prove is the half that matugen can
    // break -- that the rendered values are CSS GTK4 (which swayosd links
    // against) reads without a single parse error.
    const out = gtkParseErrors(output("dark", "swayosd/style.css"));
    if (out === null)
        return; // No PyGObject here; the render test above still guards the placeholders.
    assert.match(out, /^ERRORS 0$/m, `GTK reported parse errors in the swayosd stylesheet:\n${out}`);
});

test("GTK parses the walker stylesheet", { skip: (noMatugen && "matugen not installed") || (!have("python3") && "python3 not installed") }, () => {
    // Exactly as weak as the swayosd check above, and for the same reason:
    // walker is not installed on this machine, so nothing here can prove it
    // *applies* these rules. GTK4's parser accepts any selector, so a class
    // walker never puts on a widget would sail through and theme nothing.
    // What holds that risk down is the template: every selector in it is
    // walker 2.17.0's own resources/themes/default/style.css, cross-checked
    // against the class names in its themes/default/*.xml layouts.
    //
    // What this does prove is the half matugen can break -- that what comes
    // out is CSS the GTK4 walker links against reads with no parse error,
    // and that no placeholder survived unrendered. That second half matters
    // more here than for any other template, because walker's theme replaces
    // its bundled stylesheet outright: a sheet GTK drops on the floor leaves
    // the launcher with no styling at all, not with walker's defaults.
    const out = gtkParseErrors(output("dark", "walker/themes/pshell/style.css"));
    if (out === null)
        return; // No PyGObject here; the render test above still guards the placeholders.
    assert.match(out, /^ERRORS 0$/m, `GTK reported parse errors in the walker stylesheet:\n${out}`);
});

// ------------------------------------------------ formats with no CLI parser

test("the zed theme is loadable and follows the mode", { skip: noMatugen && "matugen not installed" }, () => {
    // Zed reads themes leniently -- a shipped extension theme on this machine
    // (jetbrains-light.json) opens with a `//` comment too -- so the header
    // comment every template carries is legal here. Strict JSON parsers are
    // not, which is why this strips comments rather than calling JSON.parse
    // on the file as it stands.
    const strip = text => text.replace(/^\s*\/\/.*$/gm, "");

    for (const mode of ["dark", "light"]) {
        const theme = JSON.parse(strip(read(mode, "zed/themes/pshell.json")));
        assert.match(theme.$schema, /zed\.dev\/schema\/themes/);
        assert.equal(theme.themes.length, 1);
        assert.equal(theme.themes[0].appearance, mode, `zed theme claims the wrong appearance in ${mode} mode`);
        assert.ok(theme.themes[0].style.syntax, "zed theme has no syntax block");
    }
});

test("the alacritty theme is TOML with the sections alacritty reads", { skip: noMatugen && "matugen not installed" }, () => {
    const text = read("dark", "alacritty/pshell-colors.toml");
    for (const section of ["[colors.primary]", "[colors.normal]", "[colors.bright]", "[colors.cursor]"])
        assert.ok(text.includes(section), `alacritty theme has no ${section}`);
    for (const name of ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"])
        assert.match(text, new RegExp(`^${name}\\s*=\\s*"#[0-9a-fA-F]{6}"`, "m"), `alacritty theme has no ${name}`);
});

test("the qt6ct scheme has the row width qt6ct's own schemes have", { skip: noMatugen && "matugen not installed" }, () => {
    const stockDir = "/usr/share/qt6ct/colors";
    if (!existsSync(stockDir))
        return; // qt6ct not installed; nothing authoritative to compare against.

    const rowWidth = text => (text.match(/^active_colors=(.*)$/m) || [, ""])[1].split(",").length;

    const stock = readdirSync(stockDir).filter(f => f.endsWith(".conf"));
    assert.ok(stock.length > 0, "qt6ct ships no colour schemes to compare against");
    const expected = rowWidth(readFileSync(join(stockDir, stock[0]), "utf8"));

    const ours = read("dark", "qt6ct/colors/pshell.conf");
    assert.ok(ours.includes("[ColorScheme]"), "qt6ct scheme has no [ColorScheme] section");
    for (const row of ["active_colors", "inactive_colors", "disabled_colors"]) {
        const line = (ours.match(new RegExp(`^${row}=(.*)$`, "m")) || [])[1];
        assert.ok(line, `qt6ct scheme has no ${row}`);
        assert.equal(line.split(",").length, expected, `${row} has the wrong number of colours for qt6ct`);
    }
});

test("every btop key we emit is one btop's own themes use", { skip: noMatugen && "matugen not installed" }, () => {
    const stockDir = "/usr/share/btop/themes";
    if (!existsSync(stockDir))
        return; // btop not installed; no authority to check against.

    const keysOf = text => new Set([...text.matchAll(/theme\[([a-z0-9_]+)\]/g)].map(m => m[1]));

    // The union across every stock theme, because no single one sets every
    // key -- adwaita-dark leaves out the gradient triples, and a check against
    // one file alone would call ours wrong for setting them.
    const known = new Set();
    for (const file of readdirSync(stockDir).filter(f => f.endsWith(".theme")))
        for (const key of keysOf(readFileSync(join(stockDir, file), "utf8")))
            known.add(key);
    assert.ok(known.size > 0, "btop ships no themes to compare against");

    const ours = read("dark", "btop/themes/pshell.theme");
    const unknown = [...keysOf(ours)].filter(key => !known.has(key));
    assert.deepEqual(unknown, [], `btop theme sets keys btop's own themes never use: ${unknown}`);

    // btop takes "#rrggbb", "#bw", or three space-separated 0-255 decimals.
    // An empty value is legal too and means "terminal default".
    for (const [, value] of ours.matchAll(/theme\[[a-z0-9_]+\]="([^"]*)"/g))
        if (value !== "")
            assert.match(value, /^(#[0-9a-fA-F]{6}|#[0-9a-fA-F]{2}|\d{1,3} \d{1,3} \d{1,3})$/, `btop value ${value} is not a colour btop understands`);
});
