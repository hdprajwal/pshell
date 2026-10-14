import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync, statSync, symlinkSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const script = join(repo, "Services", "wallpaper-thumbs.sh");
// By absolute path, so the tests that narrow PATH can still start it.
const bash = spawnSync("sh", ["-c", "command -v bash"]).stdout.toString().trim();

// The real Services/wallpaper-thumbs.sh with the real vipsthumbnail and
// magick, against images made here. XDG_CACHE_HOME points into a fresh
// temporary directory, so no test reads or writes the cache of whoever ran
// it.
function sandbox() {
    const root = mkdtempSync(join(tmpdir(), "pshell-thumbs-"));
    const images = join(root, "images");
    mkdirSync(images);
    return { root, images, cache: join(root, "cache", "pshell", "wallpaper-thumbs") };
}

function image(box, name, colour = "red", size = "160x90") {
    const path = join(box.images, name);
    const made = spawnSync("magick", ["-size", size, `xc:${colour}`, path]);
    assert.equal(made.status, 0, made.stderr.toString());
    return path;
}

function run(box, args, env = {}) {
    return spawnSync(bash, [script, ...args], {
        env: { PATH: process.env.PATH, HOME: box.root, XDG_CACHE_HOME: join(box.root, "cache"), ...env },
    });
}

// stdout as { source: thumbnail }, checking every line has the shape the
// shell splits on.
function pairs(out) {
    const map = {};
    for (const line of out.stdout.toString("utf8").split("\n").filter(l => l !== "")) {
        const parts = line.split("\t");
        assert.equal(parts.length, 2, JSON.stringify(line));
        map[parts[0]] = parts[1];
    }
    return map;
}

function cacheFiles(box) {
    return readdirSync(box.cache).sort();
}

// A PATH holding only what the script needs, minus whichever tools a test
// wants missing.
function stubPath(box, without) {
    const bin = join(box.root, "stub-" + without.join("-"));
    mkdirSync(bin);
    for (const tool of ["stat", "md5sum", "touch", "mv", "rm", "nice", "xargs", "nproc", "find", "mkdir", "vipsthumbnail", "magick"]) {
        if (without.includes(tool))
            continue;
        const which = spawnSync("bash", ["-c", 'command -v "$1"', "bash", tool]);
        const real = which.stdout.toString().trim();
        assert.ok(real !== "", `${tool} is not installed`);
        symlinkSync(real, join(bin, tool));
    }
    return bin;
}

function identify(path) {
    return spawnSync("magick", ["identify", "-format", "%m %wx%h", path]).stdout.toString();
}

// ----------------------------------------------------------------- making

test("makes a thumbnail per image and prints source<TAB>thumbnail", () => {
    const box = sandbox();
    const a = image(box, "a.png", "red");
    const b = image(box, "b.jpg", "blue", "300x200");
    const out = run(box, ["64", "36", a, b]);
    assert.equal(out.status, 0, out.stderr.toString());
    const map = pairs(out);
    assert.deepEqual(Object.keys(map).sort(), [a, b]);
    for (const thumb of Object.values(map)) {
        assert.equal(dirname(thumb), box.cache);
        assert.match(thumb, /\/[0-9a-f]{32}\.jpg$/);
        // Cropped to the box, not fitted inside it: the grid's cells are
        // all one shape.
        assert.equal(identify(thumb), "JPEG 64x36");
    }
    assert.notEqual(map[a], map[b]);
});

test("a second run reuses the thumbnail rather than making it again", () => {
    const box = sandbox();
    const a = image(box, "a.png");
    const first = pairs(run(box, ["64", "36", a]))[a];
    const before = statSync(first);
    const again = run(box, ["64", "36", a]);
    assert.equal(pairs(again)[a], first);
    // Same file, not a new one under the same name: a regenerated thumbnail
    // would arrive by rename, with a new inode.
    assert.equal(statSync(first).ino, before.ino);
    assert.deepEqual(cacheFiles(box), [first.split("/").pop()]);
});

test("each size is its own thumbnail", () => {
    const box = sandbox();
    const a = image(box, "a.png");
    const small = pairs(run(box, ["64", "36", a]))[a];
    const big = pairs(run(box, ["128", "72", a]))[a];
    assert.notEqual(small, big);
    assert.equal(identify(big), "JPEG 128x72");
});

test("an image changed in place gets a new thumbnail", () => {
    const box = sandbox();
    const a = image(box, "a.png", "red");
    const first = pairs(run(box, ["64", "36", a]))[a];
    image(box, "a.png", "green", "200x100");
    // Ahead of the first write's second, so the test does not lean on the
    // size changing too.
    const later = new Date(Date.now() + 5000);
    utimesSync(a, later, later);
    const second = pairs(run(box, ["64", "36", a]))[a];
    assert.ok(second);
    assert.notEqual(second, first);
});

test("paths with spaces and quotes are paths, not shell syntax", () => {
    const box = sandbox();
    const odd = [
        image(box, "with space.png"),
        image(box, `it's "quoted".png`),
        image(box, "$(touch pwned) `x`;.png"),
    ];
    const out = run(box, ["64", "36", ...odd]);
    assert.equal(out.status, 0, out.stderr.toString());
    assert.deepEqual(Object.keys(pairs(out)).sort(), [...odd].sort());
    assert.ok(!readdirSync(box.root).includes("pwned"));
    assert.ok(!readdirSync(box.images).includes("pwned"));
});

test("a file that is not an image prints nothing and leaves nothing behind", () => {
    const box = sandbox();
    const good = image(box, "good.png");
    const bad = join(box.images, "bad.png");
    writeFileSync(bad, "this is not a png\n");
    const gone = join(box.images, "gone.png");
    const out = run(box, ["64", "36", bad, good, gone]);
    assert.equal(out.status, 0);
    assert.deepEqual(Object.keys(pairs(out)), [good]);
    // Only the good one's thumbnail: no temporary file from the failed one.
    assert.deepEqual(cacheFiles(box), [pairs(run(box, ["64", "36", good]))[good].split("/").pop()]);
});

// ------------------------------------------------------------------ tools

test("falls back to ImageMagick without vipsthumbnail", () => {
    const box = sandbox();
    const a = image(box, "a.png", "red", "300x100");
    const out = run(box, ["64", "36", a], { PATH: stubPath(box, ["vipsthumbnail"]) });
    assert.equal(out.status, 0, out.stderr.toString());
    assert.equal(identify(pairs(out)[a]), "JPEG 64x36");
});

test("with neither tool, says so and prints nothing", () => {
    const box = sandbox();
    const a = image(box, "a.png");
    const out = run(box, ["64", "36", a], { PATH: stubPath(box, ["vipsthumbnail", "magick"]) });
    assert.equal(out.status, 1);
    assert.equal(out.stdout.toString(), "");
    assert.match(out.stderr.toString(), /neither vipsthumbnail nor magick/);
});

test("rejects a size that is not one", () => {
    const box = sandbox();
    for (const args of [[], ["64"], ["0", "36"], ["64", "x"], ["-1", "36"]]) {
        const out = run(box, args);
        assert.equal(out.status, 2, JSON.stringify(args));
        assert.equal(out.stdout.toString(), "");
    }
});

test("no images is no output and no error", () => {
    const box = sandbox();
    const out = run(box, ["64", "36"]);
    assert.equal(out.status, 0, out.stderr.toString());
    assert.equal(out.stdout.toString(), "");
});

// ------------------------------------------------------------------ prune

test("prunes thumbnails unused for sixty days and stale temporary files", () => {
    const box = sandbox();
    const a = image(box, "a.png");
    const kept = pairs(run(box, ["64", "36", a]))[a];
    const old = join(box.cache, "0123456789abcdef0123456789abcdef.jpg");
    const tmp = join(box.cache, ".0123456789abcdef0123456789abcdef.999.jpg");
    const fresh = join(box.cache, ".fedcba9876543210fedcba9876543210.998.jpg");
    for (const f of [old, tmp, fresh])
        writeFileSync(f, "x");
    const longAgo = new Date(Date.now() - 61 * 86400 * 1000);
    const hourAgo = new Date(Date.now() - 3600 * 1000);
    utimesSync(old, longAgo, longAgo);
    utimesSync(tmp, hourAgo, hourAgo);
    // An old thumbnail that is used again is touched, and so kept.
    utimesSync(kept, longAgo, longAgo);
    run(box, ["64", "36", a]);
    assert.deepEqual(cacheFiles(box), [fresh, kept].map(f => f.split("/").pop()).sort());
});
