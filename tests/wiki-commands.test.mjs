import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const doc = readFileSync(join(repo, "wiki", "commands.md"), "utf8");

// Every IPC method the shell answers must be on wiki/commands.md, written as
// `pshell <target> <method>`. The list is read from the QML, not kept by hand,
// so a new method that nobody documented fails here instead of going unseen.
//
// Methods that exist for the shell's own plumbing and are not meant to be
// typed go in this allowlist, one "target method" string each, with a comment
// saying why. It is empty today: every method on every target is something a
// keybind or a script can use. The last test fails on an entry that no longer
// matches a real method, so the list cannot quietly go stale.
const internal = new Set([
    // "pshell.example someMethod",  // why it is not for users
]);

function qmlFiles(dir) {
    const out = [];
    for (const name of readdirSync(dir)) {
        const path = join(dir, name);
        if (statSync(path).isDirectory())
            out.push(...qmlFiles(path));
        else if (name.endsWith(".qml"))
            out.push(path);
    }
    return out;
}

// The body of every `IpcHandler { ... }` block, found by counting braces.
// QML strings and comments in these blocks do not hold unbalanced braces, so
// counting is enough.
function handlerBlocks(src) {
    const blocks = [];
    const re = /\bIpcHandler\s*\{/g;
    let m;
    while ((m = re.exec(src)) !== null) {
        let i = m.index + m[0].length;
        const start = i;
        let depth = 1;
        while (depth > 0 && i < src.length) {
            if (src[i] === "{")
                depth++;
            else if (src[i] === "}")
                depth--;
            i++;
        }
        blocks.push(src.slice(start, i - 1));
    }
    return blocks;
}

// Only the handler's own level: a method body's nested `function` is not a
// method of the target.
function topLevel(body) {
    let depth = 0;
    let out = "";
    for (const c of body) {
        if (c === "{") {
            depth++;
            continue;
        }
        if (c === "}") {
            depth--;
            continue;
        }
        if (depth === 0)
            out += c;
    }
    return out;
}

function methodsOf(body) {
    return [...topLevel(body).matchAll(/\bfunction\s+(\w+)\s*\(/g)].map(m => m[1]);
}

function targetOf(body) {
    const m = /\btarget:\s*(?:"([^"]+)"|([^\n;]+))/.exec(topLevel(body));
    if (!m)
        return null;
    return m[1] !== undefined ? { name: m[1] } : { expression: m[2].trim() };
}

// target -> Map of method -> the file it came from, for failure messages.
//
// Most handlers name their target as a string. The one exception is
// Ui/Panel.qml, which holds a single handler for every panel widget, with the
// target set per widget through `ipcTarget`; its methods apply to each of
// those. Any other handler whose target this test cannot read is a failure,
// so a new pattern is noticed rather than skipped.
function collect() {
    const files = ["Services", "Widgets", "Ui", "Commons", "Components"]
        .flatMap(dir => qmlFiles(join(repo, dir)))
        .concat([join(repo, "shell.qml")]);
    const targets = new Map();
    const add = (target, method, file) => {
        if (!targets.has(target))
            targets.set(target, new Map());
        targets.get(target).set(method, relative(repo, file));
    };

    let panelMethods = null;
    const panelTargets = [];

    for (const file of files) {
        const src = readFileSync(file, "utf8");
        for (const body of handlerBlocks(src)) {
            const target = targetOf(body);
            if (target && target.name) {
                for (const method of methodsOf(body))
                    add(target.name, method, file);
            } else if (target && target.expression === "root.ipcTarget") {
                assert.equal(panelMethods, null, `${relative(repo, file)}: a second handler on root.ipcTarget`);
                panelMethods = methodsOf(body);
            } else {
                assert.fail(`${relative(repo, file)}: IpcHandler with a target this test cannot read`);
            }
        }
        for (const m of src.matchAll(/\bipcTarget:\s*"([^"]+)"/g))
            panelTargets.push({ target: m[1], file });
    }

    assert.ok(panelMethods, "expected Ui/Panel.qml's handler on root.ipcTarget");
    for (const { target, file } of panelTargets) {
        for (const method of panelMethods)
            add(target, method, file);
    }

    return targets;
}

function shortName(target) {
    return target.replace(/^pshell\./, "");
}

function escape(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function documented(target, method) {
    // Followed by something that is not part of a name, so `clear` is not
    // satisfied by `clearAll`.
    const re = new RegExp(`pshell ${escape(shortName(target))} ${escape(method)}(?![\\w])`);
    return re.test(doc);
}

const targets = collect();

// bin/pshell's own commands, which are not one IPC method each: the bare
// shorthands, and the commands that never reach the shell. Each maps to a
// line bin/pshell has to contain for the entry to be real, so an entry for a
// shorthand that has been removed fails the last test.
const shortForms = new Map([
    ["lock", /^lock\)$/m],
    ["unlock", /^unlock\)$/m],
    ["preview", /^preview\)$/m],
    ["run", /^run\)$/m],
    ["ipc", /^ipc\)$/m],
    ["launcher", /^launcher\)$/m],
    ["clipboard", /^clipboard\)$/m],
    ["nightlight", /^nightlight\)$/m],
    ["updates", /^updates\)$/m],
    ["help", /^-h \| --help \| help\)$/m],
    ["audio tone", /\[ "\$1" = tone \]/],
]);
const script = readFileSync(join(repo, "bin", "pshell"), "utf8");

// The command in the first cell of every table row on commands.md, as the
// words after `pshell`. Arguments that are placeholders -- `[qs options]`,
// `<arguments>` -- stop the list, since they are not words you type.
function tableCommands() {
    const out = [];
    for (const line of doc.split("\n")) {
        const m = /^\|\s*`pshell ([^`]+)`\s*\|/.exec(line);
        if (!m)
            continue;
        const words = [];
        for (const w of m[1].trim().split(/\s+/)) {
            if (w.startsWith("[") || w.startsWith("<"))
                break;
            words.push(w);
        }
        out.push({ words, text: m[1] });
    }
    return out;
}

function isMethod(words) {
    if (words.length < 2)
        return false;
    const methods = targets.get("pshell." + words[0]);
    return !!methods && methods.has(words[1]);
}

test("the scan finds the shell's IPC targets", () => {
    // A broken regex would find nothing and pass everything below. These are
    // targets that have been there a long time.
    for (const t of ["pshell.bar", "pshell.lock", "pshell.wallpaper", "pshell.clipboard", "pshell.calendar"])
        assert.ok(targets.has(t), `expected to find ${t}`);
    assert.ok(targets.size >= 20, `only ${targets.size} targets found`);
});

test("every IPC method is on wiki/commands.md", () => {
    const missing = [];
    for (const [target, methods] of targets) {
        for (const [method, file] of methods) {
            if (internal.has(`${target} ${method}`))
                continue;
            if (!documented(target, method))
                missing.push(`pshell ${shortName(target)} ${method}   (${file})`);
        }
    }
    assert.deepEqual(missing, [], "not on wiki/commands.md:\n  " + missing.join("\n  "));
});

test("every IPC target has its own heading on wiki/commands.md", () => {
    const missing = [];
    for (const target of targets.keys()) {
        const re = new RegExp(`^## ${escape(shortName(target))}\\s*$`, "m");
        if (!re.test(doc))
            missing.push(`## ${shortName(target)}`);
    }
    assert.deepEqual(missing, [], "headings missing:\n  " + missing.join("\n  "));
});

test("every command in a commands.md table is a real method or a bin/pshell command", () => {
    const rows = tableCommands();
    assert.ok(rows.length > 100, `only ${rows.length} table rows found`);
    const unknown = rows
        .filter(r => !isMethod(r.words) && !shortForms.has(r.words.join(" ")))
        .map(r => "pshell " + r.text);
    assert.deepEqual(unknown, [], "on wiki/commands.md but not in the shell:\n  " + unknown.join("\n  "));
});

test("the short-form allowlist matches bin/pshell", () => {
    const stale = [...shortForms].filter(([, pattern]) => !pattern.test(script)).map(([name]) => name);
    assert.deepEqual(stale, [], "short forms bin/pshell no longer has:\n  " + stale.join("\n  "));
});

test("the internal allowlist names only real methods", () => {
    const stale = [];
    for (const entry of internal) {
        const [target, method] = entry.split(" ");
        if (!targets.has(target) || !targets.get(target).has(method))
            stale.push(entry);
    }
    assert.deepEqual(stale, [], "allowlist entries that no longer exist:\n  " + stale.join("\n  "));
});
