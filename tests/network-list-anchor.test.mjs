import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// NetworkList hands `bar` and `anchorItem` straight to its PasswordPrompt,
// a KeyboardPanel of its own. Left unset, the prompt has no screen, draws in
// the top-left corner and never takes the popout slot, so the panel that
// hosts the list stays open underneath it. Every host has to pass both.

function qmlFiles(dir, out = []) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const p = join(dir, entry.name);
        if (entry.isDirectory())
            qmlFiles(p, out);
        else if (entry.name.endsWith(".qml"))
            out.push(p);
    }
    return out;
}

// The text between `NetworkList {` and its matching brace.
function blocks(source) {
    const out = [];
    const re = /\bNetworkList\s*\{/g;
    let m;
    while ((m = re.exec(source))) {
        let depth = 1;
        let i = m.index + m[0].length;
        for (; i < source.length && depth > 0; i++) {
            if (source[i] === "{")
                depth++;
            else if (source[i] === "}")
                depth--;
        }
        out.push(source.slice(m.index, i));
    }
    return out;
}

test("every NetworkList is given a bar and an anchor item", () => {
    const hosts = [];
    for (const file of qmlFiles(join(repo, "Widgets"))) {
        if (file.endsWith("NetworkList.qml"))
            continue;
        for (const block of blocks(readFileSync(file, "utf8"))) {
            const name = relative(repo, file);
            hosts.push(name);
            assert.match(block, /^\s*bar:\s*\S/m, `${name}: NetworkList has no bar`);
            assert.match(block, /^\s*anchorItem:\s*\S/m, `${name}: NetworkList has no anchorItem`);
        }
    }
    assert.ok(hosts.includes("Widgets/ControlCenter/ControlCenter.qml"));
    assert.ok(hosts.includes("Widgets/Network/Network.qml"));
});
