import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, existsSync, symlinkSync, lstatSync, readlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// Qt 6.12's QtQuick exports a `Color` singleton. In a file that imports
// QtQuick without a version it wins over qs.Commons' palette, whatever the
// import order, so `Color.popups` is undefined. pshell's own QML therefore
// names the palette `Commons.Color`, through `import qs.Commons as Commons`,
// the way Omarchy's does. These guard that rule.

function qmlFiles(dir, out = []) {
    for (const name of readdirSync(dir, { withFileTypes: true })) {
        if (name.name === ".git" || name.name === "node_modules")
            continue;
        const p = join(dir, name.name);
        if (name.isDirectory())
            qmlFiles(p, out);
        else if (name.name.endsWith(".qml"))
            out.push(p);
    }
    return out;
}

// Comments may name the singleton; only code is checked. A `//` after a
// colon is a URL inside a string, not a comment.
function codeOf(line) {
    const t = line.trimStart();
    if (t.startsWith("//") || t.startsWith("*") || t.startsWith("/*"))
        return "";
    const m = /(?<!:)\/\//.exec(line);
    return m ? line.slice(0, m.index) : line;
}

// A bare `Color` read as the palette: `Color.x`, or the object itself, as in
// `target: Color`. `typeof Color` is not a read of the palette.
const BARE = /(?<![\w.$"'])Color\b(?=\s*[.)\]},;]|\s*$)/;

function bareColorLines(src) {
    const hits = [];
    src.split("\n").forEach((line, i) => {
        if (BARE.test(codeOf(line)))
            hits.push(i + 1);
    });
    return hits;
}

test("the detector finds what Qt 6.12 breaks, and nothing else", () => {
    assert.deepEqual(bareColorLines("color: Color.popups.background"), [1]);
    assert.deepEqual(bareColorLines("x: a ? b : Color.urgent"), [1]);
    assert.deepEqual(bareColorLines("    target: Color"), [1]);
    assert.deepEqual(bareColorLines("color: Commons.Color.popups.background"), []);
    assert.deepEqual(bareColorLines("property color iconColor: root.iconColor"), []);
    assert.deepEqual(bareColorLines("// coloured from Color.menu.*"), []);
    assert.deepEqual(bareColorLines('x: 1 // see Color.menu'), []);
    assert.deepEqual(bareColorLines('readonly property bool pinQtQuick: typeof Color !== "undefined"'), []);
});

test("no pshell QML reads the palette as a bare Color", () => {
    const offenders = [];
    for (const file of qmlFiles(repo)) {
        const hits = bareColorLines(readFileSync(file, "utf8"));
        if (hits.length)
            offenders.push(`${relative(repo, file)}:${hits.join(",")}`);
    }
    assert.deepEqual(offenders, [], "write Commons.Color, with `import qs.Commons as Commons`, so Qt 6.12's QtQuick.Color cannot shadow it");
});

test("every file that says Commons.Color imports qs.Commons as Commons", () => {
    const missing = [];
    for (const file of qmlFiles(repo)) {
        const src = readFileSync(file, "utf8");
        if (/\bCommons\.Color\b/.test(src.split("\n").map(codeOf).join("\n"))
            && !/^import qs\.Commons as Commons\s*$/m.test(src))
            missing.push(relative(repo, file));
    }
    assert.deepEqual(missing, []);
});

// Services/widgets.sh, which WidgetRegistry runs to find and stage
// third-party widgets, against a fake HOME. Third-party widgets keep their
// bare `Color`, so on Qt 6.12 they load from a copy with QtQuick pinned.

const script = join(repo, "Services", "widgets.sh");

const WIDGET = `import QtQuick
import QtQuick.Controls
import qs.Commons
Item { Rectangle { color: Color.popups.background } }
`;

function sandbox(t) {
    const root = mkdtempSync(join(tmpdir(), "pshell-widgets-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const home = join(root, "home");
    const cache = join(root, "cache");
    const widgets = join(home, ".config", "pshell", "widgets");
    mkdirSync(widgets, { recursive: true });
    return { root, home, cache, widgets };
}

function addWidget(dir, id, files) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "manifest.json"), JSON.stringify({ id, kinds: ["bar-widget"], entryPoints: { barWidget: "BarWidget.qml" } }));
    for (const [name, body] of Object.entries(files)) {
        mkdirSync(dirname(join(dir, name)), { recursive: true });
        writeFileSync(join(dir, name), body);
    }
}

function run(box, ...args) {
    const r = spawnSync("sh", [script, ...args], {
        env: { PATH: process.env.PATH, HOME: box.home, XDG_CACHE_HOME: box.cache },
        encoding: "utf8"
    });
    const blocks = r.stdout.split("===PSHELL===").map(b => b.trim()).filter(b => b !== "").map(b => {
        const [dir, load, ...rest] = b.split("\n");
        return { dir, load, manifest: JSON.parse(rest.join("\n")) };
    });
    return { status: r.status, stderr: r.stderr, blocks };
}

test("with no version, widgets load from where they live and nothing is copied", t => {
    const box = sandbox(t);
    addWidget(join(box.widgets, "w"), "a.w", { "BarWidget.qml": WIDGET });

    const r = run(box);
    assert.equal(r.status, 0);
    assert.equal(r.blocks.length, 1);
    assert.equal(r.blocks[0].dir, join(box.widgets, "w"));
    assert.equal(r.blocks[0].load, join(box.widgets, "w"));
    assert.equal(r.blocks[0].manifest.id, "a.w");
    assert.equal(existsSync(join(box.cache, "pshell")), false);
});

test("with a version, a pinned copy is loaded and the widget is left as it was", t => {
    const box = sandbox(t);
    const src = join(box.widgets, "w");
    const files = {
        "BarWidget.qml": WIDGET,
        "Panel.qml": "import QtQuick;\nimport QtQuick 2.15 as Old\nItem {}\n",
        "nested/Row.qml": "  import QtQuick  \r\nItem {}\n",
        "Model.js": ".pragma library\n// import QtQuick\n",
        ".git/HEAD": "ref: refs/heads/main\n"
    };
    addWidget(src, "a.w", files);

    const r = run(box, "6.11");
    assert.equal(r.status, 0, r.stderr);
    const copy = join(box.cache, "pshell", "widgets", "w");
    assert.equal(r.blocks[0].dir, src);
    assert.equal(r.blocks[0].load, copy);

    assert.equal(readFileSync(join(copy, "BarWidget.qml"), "utf8"), WIDGET.replace("import QtQuick\n", "import QtQuick 6.11\n"));
    assert.equal(readFileSync(join(copy, "Panel.qml"), "utf8"), "import QtQuick 6.11\nimport QtQuick 2.15 as Old\nItem {}\n");
    assert.equal(readFileSync(join(copy, "nested/Row.qml"), "utf8"), "  import QtQuick 6.11\nItem {}\n");
    assert.equal(readFileSync(join(copy, "Model.js"), "utf8"), files["Model.js"]);
    assert.equal(existsSync(join(copy, ".git")), false);

    for (const [name, body] of Object.entries(files))
        assert.equal(readFileSync(join(src, name), "utf8"), body, `${name} was modified in place`);
});

test("a widget symlinked in, or holding a symlinked file, is copied rather than edited through the link", t => {
    const box = sandbox(t);
    const checkout = join(box.root, "checkout");
    addWidget(checkout, "linked.w", { "BarWidget.qml": WIDGET });
    symlinkSync(checkout, join(box.widgets, "linked"));

    const shared = join(box.root, "Shared.qml");
    writeFileSync(shared, WIDGET);
    addWidget(join(box.widgets, "w"), "a.w", { "BarWidget.qml": WIDGET });
    symlinkSync(shared, join(box.widgets, "w", "Shared.qml"));

    const r = run(box, "6.11");
    assert.equal(r.status, 0, r.stderr);
    const stage = join(box.cache, "pshell", "widgets");
    assert.match(readFileSync(join(stage, "linked", "BarWidget.qml"), "utf8"), /^import QtQuick 6\.11$/m);
    assert.equal(lstatSync(join(stage, "w", "Shared.qml")).isSymbolicLink(), false);
    assert.match(readFileSync(join(stage, "w", "Shared.qml"), "utf8"), /^import QtQuick 6\.11$/m);

    assert.equal(readFileSync(join(checkout, "BarWidget.qml"), "utf8"), WIDGET);
    assert.equal(readFileSync(shared, "utf8"), WIDGET);
});

test("a widget removed since the last start leaves no copy behind", t => {
    const box = sandbox(t);
    addWidget(join(box.widgets, "gone"), "gone.w", { "BarWidget.qml": WIDGET });
    run(box, "6.11");
    const stage = join(box.cache, "pshell", "widgets");
    assert.ok(existsSync(join(stage, "gone")));

    spawnSync("rm", ["-rf", join(box.widgets, "gone")]);
    addWidget(join(box.widgets, "kept"), "kept.w", { "BarWidget.qml": WIDGET });
    const r = run(box, "6.11");
    assert.deepEqual(r.blocks.map(b => b.manifest.id), ["kept.w"]);
    assert.deepEqual(readdirSync(stage), ["kept"]);
});

test("anything but a dotted version is refused before the cache is touched", t => {
    const box = sandbox(t);
    addWidget(join(box.widgets, "w"), "a.w", { "BarWidget.qml": WIDGET });
    for (const bad of ["6.11/e", "x", ".6", "6.", "6.11 ; rm"]) {
        const r = run(box, bad);
        assert.equal(r.status, 2, bad);
        assert.equal(r.blocks.length, 0, bad);
    }
    assert.equal(existsSync(join(box.cache, "pshell")), false);
});

test("a bare import with a trailing comment is pinned too, and the comment kept", t => {
    const box = sandbox(t);
    addWidget(join(box.widgets, "w"), "a.w", {
        "BarWidget.qml": "import QtQuick // for Item\nimport QtQuick.Layouts\nItem {}\n",
        "Block.qml": "import QtQuick; /* why */\r\nItem {}\r\n",
        "Versioned.qml": "import QtQuick 2.15 // old\nItem {}\n"
    });

    const r = run(box, "6.11");
    assert.equal(r.status, 0, r.stderr);
    const copy = join(box.cache, "pshell", "widgets", "w");
    assert.equal(readFileSync(join(copy, "BarWidget.qml"), "utf8"), "import QtQuick 6.11 // for Item\nimport QtQuick.Layouts\nItem {}\n");
    assert.equal(readFileSync(join(copy, "Block.qml"), "utf8"), "import QtQuick 6.11 /* why */\r\nItem {}\r\n");
    assert.equal(readFileSync(join(copy, "Versioned.qml"), "utf8"), "import QtQuick 2.15 // old\nItem {}\n");
});

test("links are copied as links: a cycle, a dangling one and one out of the widget cost nothing", t => {
    const box = sandbox(t);
    const src = join(box.widgets, "w");
    addWidget(src, "a.w", {
        "BarWidget.qml": WIDGET,
        "assets/icon.svg": "<svg/>",
        "inner/Real.qml": WIDGET,
        ".git/HEAD": "ref: refs/heads/main\n",
        "node_modules/x/index.js": "module.exports = 1;\n"
    });
    const outside = join(box.root, "outside");
    mkdirSync(outside);
    writeFileSync(join(outside, "big.bin"), "x".repeat(1 << 16));
    writeFileSync(join(outside, "Shared.qml"), WIDGET);

    symlinkSync("..", join(src, "up"));
    symlinkSync("missing.svg", join(src, "assets", "gone.svg"));
    symlinkSync(outside, join(src, "ext"));
    symlinkSync(relative(join(src, "assets"), join(outside, "big.bin")), join(src, "assets", "big.bin"));
    symlinkSync("inner/Real.qml", join(src, "Inner.qml"));
    symlinkSync(relative(src, join(outside, "Shared.qml")), join(src, "Shared.qml"));
    symlinkSync("inner", join(src, "alias"));

    const r = run(box, "6.11");
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stderr, "");
    const copy = join(box.cache, "pshell", "widgets", "w");
    assert.equal(r.blocks[0].load, copy);

    // Not followed: the cycle, the directory outside, and the dangling link
    // all arrive as links, the last two still pointing where they did.
    assert.ok(lstatSync(join(copy, "up")).isSymbolicLink());
    assert.equal(readlinkSync(join(copy, "up")), box.widgets);
    assert.equal(readlinkSync(join(copy, "ext")), outside);
    assert.equal(readlinkSync(join(copy, "assets", "big.bin")), join(outside, "big.bin"));
    assert.equal(readFileSync(join(copy, "assets", "big.bin"), "utf8").length, 1 << 16);
    assert.equal(readlinkSync(join(copy, "assets", "gone.svg")), "missing.svg");
    assert.equal(readlinkSync(join(copy, "alias")), "inner");

    // QML behind a link is copied in and pinned.
    for (const name of ["Inner.qml", "Shared.qml", "inner/Real.qml", "alias/Real.qml"]) {
        assert.equal(lstatSync(join(copy, name)).isSymbolicLink(), false, name);
        assert.match(readFileSync(join(copy, name), "utf8"), /^import QtQuick 6\.11$/m, name);
    }

    assert.equal(existsSync(join(copy, ".git")), false);
    assert.equal(existsSync(join(copy, "node_modules")), false);
    assert.equal(readFileSync(join(outside, "Shared.qml"), "utf8"), WIDGET);
    assert.equal(readFileSync(join(src, "inner", "Real.qml"), "utf8"), WIDGET);
});

test("a file that cannot be read is skipped with a warning, and the rest is still pinned", t => {
    if (process.getuid && process.getuid() === 0)
        return t.skip("root reads everything");
    const box = sandbox(t);
    const src = join(box.widgets, "w");
    addWidget(src, "a.w", { "BarWidget.qml": WIDGET, "secret.txt": "x" });
    spawnSync("chmod", ["000", join(src, "secret.txt")]);
    t.after(() => spawnSync("chmod", ["644", join(src, "secret.txt")]));

    const r = run(box, "6.11");
    assert.equal(r.status, 0);
    assert.match(r.stderr, /secret\.txt/);
    const copy = join(box.cache, "pshell", "widgets", "w");
    assert.equal(r.blocks[0].load, copy);
    assert.match(readFileSync(join(copy, "BarWidget.qml"), "utf8"), /^import QtQuick 6\.11$/m);
});

test("the stage is swapped in whole, and a dead scan's leftovers are cleared", t => {
    const box = sandbox(t);
    addWidget(join(box.widgets, "w"), "a.w", { "BarWidget.qml": WIDGET });
    const parent = join(box.cache, "pshell");
    // A pid that cannot be running: above the kernel's pid_max ceiling.
    mkdirSync(join(parent, "widgets.new.99999999"), { recursive: true });
    mkdirSync(join(parent, "widgets.new." + process.pid));

    assert.equal(run(box, "6.11").status, 0);
    assert.equal(run(box, "6.11").status, 0);
    assert.deepEqual(readdirSync(parent).sort(), ["widgets", "widgets.new." + process.pid]);
    assert.deepEqual(readdirSync(join(parent, "widgets")), ["w"]);
});
