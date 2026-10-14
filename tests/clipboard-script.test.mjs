import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, existsSync, chmodSync, copyFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const script = join(repo, "Services", "clipboard.sh");

// The real Services/clipboard.sh against a fake wl-paste, wl-copy and wtype,
// the way pshell-cli.test.mjs runs bin/pshell against a fake qs. The real
// ones want a Wayland display, and a test that read or wrote the clipboard
// of whoever ran it would be a test with side effects on their session.
function sandbox() {
    const root = mkdtempSync(join(tmpdir(), "pshell-clip-"));
    const bin = join(root, "stub");
    mkdirSync(bin, { recursive: true });

    // --list-types answers from FAKE_TYPES; --type reads FAKE_CONTENT, which
    // is what "the clipboard" holds.
    //
    // A watcher loops in the script itself rather than exec'ing sleep, so the
    // process keeps the name and command line reap() looks for.
    writeFileSync(join(bin, "wl-paste"), `#!/bin/sh
case " $* " in
*" --watch "*) while :; do sleep 1; done ;;
esac
case "$1" in
--list-types) printf '%s' "\${FAKE_TYPES:-}" ;;
--type) [ -n "\${FAKE_CONTENT:-}" ] && cat "$FAKE_CONTENT" ;;
esac
exit 0
`);

    // Every wl-copy writes its argv and then what it was handed on stdin.
    writeFileSync(join(bin, "wl-copy"), `#!/bin/sh
n=$(ls "${root}" | grep -c '^copy\\.')
printf '%s\\n' "$*" > "${root}/copy.$n.argv"
cat > "${root}/copy.$n.data"
`);
    writeFileSync(join(bin, "wtype"), `#!/bin/sh
printf '%s\\n' "$*" >> "${root}/wtype.log"
`);
    for (const f of ["wl-paste", "wl-copy", "wtype"])
        chmodSync(join(bin, f), 0o755);

    return { root, bin, images: join(root, "images") };
}

function run(box, args, { input, env = {} } = {}) {
    return spawnSync(script, args, {
        input: typeof input === "string" ? Buffer.from(input) : input,
        env: {
            PATH: `${box.bin}:/usr/bin:/bin`,
            HOME: box.root,
            PSHELL_CLIPBOARD_IMAGES: box.images,
            ...env,
        },
    });
}

function lines(out) {
    return out.stdout.toString("utf8").split("\n").filter(l => l !== "").map(l => JSON.parse(l));
}

function copies(box) {
    return readdirSync(box.root)
        .filter(f => /^copy\.\d+\.argv$/.test(f))
        .sort()
        .map(f => {
            const n = f.split(".")[1];
            return {
                argv: readFileSync(join(box.root, f), "utf8").trim(),
                data: readFileSync(join(box.root, `copy.${n}.data`)),
            };
        });
}

// ----------------------------------------------------------------- capture

test("a text copy from the watcher prints one JSON line", () => {
    const box = sandbox();
    const out = run(box, ["capture", "text"], { input: "hello\nworld" });

    assert.equal(out.status, 0);
    assert.deepEqual(lines(out), [{ type: "text", text: "hello\nworld" }]);
});

test("non-ASCII text survives the round trip", () => {
    const box = sandbox();
    const out = run(box, ["capture", "text"], { input: "naïve — 日本語 😀" });

    assert.deepEqual(lines(out), [{ type: "text", text: "naïve — 日本語 😀" }]);
});

test("UTF-16 with a byte-order mark is decoded", () => {
    const box = sandbox();
    const input = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("wine text", "utf16le")]);
    const out = run(box, ["capture", "text"], { input });

    assert.deepEqual(lines(out), [{ type: "text", text: "wine text" }]);
});

test("UTF-16 without one is recognised by its padding", () => {
    const box = sandbox();
    const out = run(box, ["capture", "text"], { input: Buffer.from("plain ascii in utf-16", "utf16le") });

    assert.deepEqual(lines(out), [{ type: "text", text: "plain ascii in utf-16" }]);
});

test("an empty copy records nothing", () => {
    const box = sandbox();
    const out = run(box, ["capture", "text"], { input: "" });

    assert.equal(out.status, 0);
    assert.deepEqual(lines(out), []);
});

// Password managers are the whole reason this check exists: a history file
// on disk is the last place a secret should end up.
// Every copy rewrites the whole history file, so one huge copy in it would be
// rewritten on every copy after. It is skipped, not cut short.
test("a text copy past the size cap is not recorded", () => {
    const box = sandbox();
    const env = { PSHELL_CLIPBOARD_MAX_TEXT: "16" };
    const fits = run(box, ["capture", "text"], { input: "x".repeat(16), env });
    const over = run(box, ["capture", "text"], { input: "x".repeat(17), env });

    assert.deepEqual(lines(fits), [{ type: "text", text: "x".repeat(16) }]);
    assert.equal(over.status, 0);
    assert.deepEqual(lines(over), []);
});

test("the default size cap is one MiB", () => {
    const box = sandbox();
    const out = run(box, ["capture", "text"], { input: "x".repeat(1024 * 1024 + 1) });

    assert.deepEqual(lines(out), []);
});

test("a copy a password manager marks is never recorded", () => {
    const box = sandbox();
    const hinted = run(box, ["capture", "text"], {
        input: "hunter2",
        env: { FAKE_TYPES: "text/plain\nx-kde-passwordManagerHint\n" },
    });
    const sensitive = run(box, ["capture", "text"], {
        input: "hunter2",
        env: { CLIPBOARD_STATE: "sensitive" },
    });

    assert.deepEqual(lines(hinted), []);
    assert.deepEqual(lines(sensitive), []);
});

test("an image is stored once under its sha256, however often it is copied", () => {
    const box = sandbox();
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]);
    const hash = createHash("sha256").update(png).digest("hex");

    const first = lines(run(box, ["capture", "image/png"], { input: png }));
    const second = lines(run(box, ["capture", "image/png"], { input: png }));

    const path = join(box.images, `${hash}.png`);
    assert.deepEqual(first, [{ type: "image", mime: "image/png", path }]);
    assert.deepEqual(second, first);
    // One file, and no temporaries left behind beside it.
    assert.deepEqual(readdirSync(box.images), [`${hash}.png`]);
    assert.deepEqual(readFileSync(path), png);
});

test("the snapshot at start prefers an image, then falls back to text", () => {
    const box = sandbox();
    const content = join(box.root, "content");

    writeFileSync(content, Buffer.from([1, 2, 3]));
    const img = lines(run(box, ["capture"], { env: { FAKE_TYPES: "image/jpeg\ntext/plain\n", FAKE_CONTENT: content } }));
    assert.equal(img.length, 1);
    assert.equal(img[0].mime, "image/jpeg");
    assert.match(img[0].path, /\.jpg$/);

    writeFileSync(content, "just text");
    const txt = lines(run(box, ["capture"], { env: { FAKE_TYPES: "text/plain;charset=utf-8\nUTF8_STRING\n", FAKE_CONTENT: content } }));
    assert.deepEqual(txt, [{ type: "text", text: "just text" }]);

    const none = lines(run(box, ["capture"], { env: { FAKE_TYPES: "application/x-thing\n", FAKE_CONTENT: content } }));
    assert.deepEqual(none, []);
});

// ------------------------------------------------------------------- paste

test("paste puts text on both selections and sends Shift+Insert", () => {
    const box = sandbox();
    const out = run(box, ["paste"], { input: "from history\n" });

    assert.equal(out.status, 0);
    const c = copies(box);
    assert.deepEqual(c.map(x => x.argv), ["", "--primary"]);
    assert.ok(c.every(x => x.data.toString() === "from history\n"));
    assert.equal(readFileSync(join(box.root, "wtype.log"), "utf8").trim(), "-M shift -k Insert -m shift");
});

test("copy only copies, and leaves the primary selection alone", () => {
    const box = sandbox();
    run(box, ["copy"], { input: "quiet" });

    assert.deepEqual(copies(box).map(x => x.argv), [""]);
    assert.equal(existsSync(join(box.root, "wtype.log")), false);
});

test("an image is pasted from its file with its own mime type", () => {
    const box = sandbox();
    const file = join(box.root, "pic.png");
    writeFileSync(file, Buffer.from([9, 9, 9]));
    run(box, ["paste", "--type", "image/png", "--file", file]);

    const c = copies(box);
    assert.deepEqual(c.map(x => x.argv), ["--type image/png", "--primary --type image/png"]);
    assert.deepEqual(c[0].data, Buffer.from([9, 9, 9]));
});

test("a missing image file fails rather than pasting nothing", () => {
    const box = sandbox();
    const out = run(box, ["paste", "--type", "image/png", "--file", join(box.root, "gone.png")]);

    assert.equal(out.status, 1);
    assert.deepEqual(copies(box), []);
});

// -------------------------------------------------------------------- init

const mode = path => statSync(path).mode & 0o777;

// The history is every copy anything made, so on a 0755 home it must still
// be nobody else's to read.
test("init makes the history directory the owner's alone", () => {
    const box = sandbox();
    const dir = join(box.root, "state", "clipboard");
    const images = join(dir, "images");
    const out = run(box, ["init", dir], { env: { PSHELL_CLIPBOARD_IMAGES: images } });

    assert.equal(out.status, 0);
    assert.equal(mode(dir), 0o700);
    assert.equal(mode(images), 0o700);
});

test("init tightens a directory and files that were already there", () => {
    const box = sandbox();
    const dir = join(box.root, "clipboard");
    const images = join(dir, "images");
    mkdirSync(images, { recursive: true, mode: 0o755 });
    chmodSync(dir, 0o755);
    chmodSync(images, 0o755);
    writeFileSync(join(dir, "history.json"), "[]", { mode: 0o644 });
    writeFileSync(join(images, "a.png"), "png", { mode: 0o644 });

    run(box, ["init", dir], { env: { PSHELL_CLIPBOARD_IMAGES: images } });

    assert.equal(mode(dir), 0o700);
    assert.equal(mode(images), 0o700);
    assert.equal(mode(join(dir, "history.json")), 0o600);
    assert.equal(mode(join(images, "a.png")), 0o600);
});

// Created empty and 0600 rather than left for the shell's first write,
// which would make it 0644 until the next start tightened it.
test("init creates an empty, private history file, and leaves one there alone", () => {
    const box = sandbox();
    const dir = join(box.root, "fresh");
    const out = run(box, ["init", dir], { env: { PSHELL_CLIPBOARD_IMAGES: join(dir, "images") } });

    assert.equal(out.status, 0);
    assert.equal(mode(join(dir, "history.json")), 0o600);
    assert.equal(readFileSync(join(dir, "history.json"), "utf8"), "");

    writeFileSync(join(dir, "history.json"), "[\"kept\"]");
    run(box, ["init", dir], { env: { PSHELL_CLIPBOARD_IMAGES: join(dir, "images") } });
    assert.equal(readFileSync(join(dir, "history.json"), "utf8"), '["kept"]');
});

test("init without a directory fails", () => {
    const box = sandbox();
    assert.notEqual(run(box, ["init"]).status, 0);
});

test("an image directory capture makes is the owner's alone", () => {
    const box = sandbox();
    writeFileSync(join(box.root, "pic"), "png bytes");
    run(box, ["capture", "image/png"], { input: readFileSync(join(box.root, "pic")) });

    assert.equal(mode(box.images), 0o700);
});

// ------------------------------------------------------------------- clear

test("clear takes the copy off the clipboard", () => {
    const box = sandbox();
    const out = run(box, ["clear"]);

    assert.equal(out.status, 0);
    assert.deepEqual(copies(box).map(c => c.argv), ["--clear"]);
});

// -------------------------------------------------------------------- reap

// A stand-in for a running Quickshell: a copy of bash whose executable is
// called qs, since the executable's name is all reap() looks at.
function underFakeShell(box, name = "qs") {
    const qs = join(box.root, name);
    if (!existsSync(qs))
        copyFileSync("/bin/bash", qs);
    chmodSync(qs, 0o755);
    return qs;
}

function alive(pid) {
    try {
        process.kill(pid, 0);
        return true;
    } catch {
        return false;
    }
}

function watcher(box, spawnFrom) {
    return spawn(spawnFrom, ["-c", `exec "${box.bin}/wl-paste" --type text --watch "${script}" capture text`], {
        stdio: "ignore",
        env: { PATH: `${box.bin}:/usr/bin:/bin` },
    });
}

const settle = () => new Promise(r => setTimeout(r, 300));

test("reap kills an orphaned watcher but never another shell's", async () => {
    const box = sandbox();
    const qs = underFakeShell(box);

    // An orphan stand-in: a watcher whose parent is node, not a Quickshell.
    const orphan = watcher(box, "/bin/sh");
    // Another running pshell's watcher: its parent is a process named qs.
    const other = spawn(qs, ["-c", `"${box.bin}/wl-paste" --type text --watch "${script}" capture text & wait`], {
        stdio: "ignore",
        env: { PATH: `${box.bin}:/usr/bin:/bin` },
    });
    await settle();

    const otherWatcher = Number(spawnSync("pgrep", ["-P", String(other.pid), "-x", "wl-paste"], { encoding: "utf8" }).stdout.trim());
    assert.ok(otherWatcher > 0, "the second shell's watcher did not start");

    try {
        run(box, ["reap"]);
        await settle();
        assert.equal(alive(orphan.pid), false, "the orphaned watcher survived");
        assert.equal(alive(otherWatcher), true, "another shell's watcher was killed");
    } finally {
        orphan.kill();
        process.kill(otherWatcher);
        other.kill();
    }
});

// NixOS runs Quickshell as a wrapped binary, .quickshell-wrapped, and that is
// still another shell, not an orphan.
test("reap spares a watcher under a wrapped quickshell binary", async () => {
    const box = sandbox();
    const wrapped = underFakeShell(box, ".quickshell-wrapped");
    const other = spawn(wrapped, ["-c", `"${box.bin}/wl-paste" --type text --watch "${script}" capture text & wait`], {
        stdio: "ignore",
        env: { PATH: `${box.bin}:/usr/bin:/bin` },
    });
    await settle();

    const otherWatcher = Number(spawnSync("pgrep", ["-P", String(other.pid), "-x", "wl-paste"], { encoding: "utf8" }).stdout.trim());
    assert.ok(otherWatcher > 0, "the wrapped shell's watcher did not start");

    try {
        run(box, ["reap"]);
        await settle();
        assert.equal(alive(otherWatcher), true, "a wrapped shell's watcher was killed");
    } finally {
        process.kill(otherWatcher);
        other.kill();
    }
});

test("reap kills watchers left under the very shell that runs it", async () => {
    const box = sandbox();
    const qs = underFakeShell(box);

    // One fake shell: it starts a watcher, then runs reap as a sibling child,
    // which is what a config reload looks like from the process table.
    const shell = spawn(qs, ["-c", `
        "${box.bin}/wl-paste" --type text --watch "${script}" capture text &
        w=$!
        sleep 0.2
        "${script}" reap
        sleep 0.2
        kill -0 $w 2>/dev/null && echo alive || echo reaped
    `], { env: { PATH: `${box.bin}:/usr/bin:/bin` } });

    let out = "";
    shell.stdout.on("data", d => (out += d));
    await new Promise(r => shell.on("exit", r));
    assert.equal(out.trim(), "reaped");
});

test("reap leaves unrelated wl-paste watchers alone", async () => {
    const box = sandbox();
    const unrelated = spawn("/bin/sh", ["-c", `exec "${box.bin}/wl-paste" --watch echo changed`], { stdio: "ignore" });
    await settle();

    try {
        run(box, ["reap"]);
        await settle();
        assert.equal(alive(unrelated.pid), true);
    } finally {
        unrelated.kill();
    }
});
