import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const H = loadQmlJs("Services/ClipboardHistory.js");

const text = (t, over = {}) => ({ type: "text", text: t, time: 0, ...over });
const image = (path, over = {}) => ({ type: "image", path, mime: "image/png", time: 0, ...over });

// ---------------------------------------------------------- normalizeEntry

test("normalizeEntry keeps the two shapes and drops anything else", () => {
    assert.deepEqual(H.normalizeEntry(text("hi")), text("hi"));
    assert.deepEqual(H.normalizeEntry(image("/s/a.png")), image("/s/a.png"));
    assert.equal(H.normalizeEntry({ type: "video", path: "/x" }), null);
    assert.equal(H.normalizeEntry(null), null);
    assert.equal(H.normalizeEntry(42), null);
});

test("normalizeEntry drops whitespace-only text and pathless images", () => {
    assert.equal(H.normalizeEntry(text("  \n\t ")), null);
    assert.equal(H.normalizeEntry({ type: "image", path: "" }), null);
});

test("normalizeEntry keeps a text's surrounding whitespace, since paste must", () => {
    assert.equal(H.normalizeEntry(text("  indented\n")).text, "  indented\n");
});

test("normalizeEntry reads a bare string as text and a bad time as zero", () => {
    assert.deepEqual(H.normalizeEntry("plain"), text("plain"));
    assert.equal(H.normalizeEntry(text("a", { time: "soon" })).time, 0);
    assert.equal(H.normalizeEntry(text("a", { time: 1700 })).time, 1700);
});

// ---------------------------------------------------------------- addEntry

test("addEntry puts the new copy first", () => {
    const out = H.addEntry([text("old")], text("new"), 10);
    assert.deepEqual(out.map(e => e.text), ["new", "old"]);
});

test("copying something again moves it to the top instead of duplicating it", () => {
    const out = H.addEntry([text("a"), text("b"), text("c")], text("c"), 10);
    assert.deepEqual(out.map(e => e.text), ["c", "a", "b"]);
});

test("the same image is the same entry, by its content-addressed path", () => {
    const out = H.addEntry([image("/s/x.png"), text("t")], image("/s/x.png", { time: 9 }), 10);
    assert.equal(out.length, 2);
    assert.equal(out[0].time, 9);
});

test("text that only differs in whitespace is still a different copy", () => {
    const out = H.addEntry([text("a")], text("a\n"), 10);
    assert.equal(out.length, 2);
});

test("addEntry holds the cap at exactly the cap", () => {
    let h = [];
    for (let i = 0; i < 7; i++)
        h = H.addEntry(h, text(String(i)), 5);
    assert.deepEqual(h.map(e => e.text), ["6", "5", "4", "3", "2"]);
});

test("a re-copy at the cap does not push the oldest off", () => {
    const h = [text("a"), text("b"), text("c")];
    assert.deepEqual(H.addEntry(h, text("c"), 3).map(e => e.text), ["c", "a", "b"]);
});

test("a cap of zero keeps nothing, and a missing cap is 500", () => {
    assert.deepEqual(H.addEntry([text("a")], text("b"), 0), []);
    let h = [];
    for (let i = 0; i < 520; i++)
        h = H.addEntry(h, text(String(i)));
    assert.equal(h.length, 500);
});

test("an invalid entry leaves history as it was", () => {
    const h = [text("a")];
    assert.deepEqual(H.addEntry(h, text("   "), 10), h);
    assert.deepEqual(H.addEntry(h, null, 10), h);
});

test("addEntry does not mutate the array it was given", () => {
    const before = [text("a")];
    H.addEntry(before, text("b"), 10);
    assert.deepEqual(before, [text("a")]);
});

// ------------------------------------------------------- parse and remove

test("parseHistory survives garbage and caps what it reads", () => {
    assert.deepEqual(H.parseHistory("not json"), []);
    assert.deepEqual(H.parseHistory('{"a":1}'), []);
    assert.deepEqual(H.parseHistory(""), []);
    const raw = JSON.stringify([text("a"), { type: "junk" }, text("b"), text("c")]);
    assert.deepEqual(H.parseHistory(raw, 2).map(e => e.text), ["a", "b"]);
});

test("parseEntryJson reads one capture line and ignores noise", () => {
    assert.deepEqual(H.parseEntryJson('{"type":"text","text":"hi"}\n'), text("hi"));
    assert.equal(H.parseEntryJson(""), null);
    assert.equal(H.parseEntryJson("wl-paste: something"), null);
});

test("removeEntryAt removes one and ignores a bad index", () => {
    const h = [text("a"), text("b"), text("c")];
    assert.deepEqual(H.removeEntryAt(h, 1).map(e => e.text), ["a", "c"]);
    assert.equal(H.removeEntryAt(h, 3).length, 3);
    assert.equal(H.removeEntryAt(h, -1).length, 3);
    assert.equal(H.removeEntryAt(h, 0.5).length, 3);
    assert.equal(h.length, 3);
});

// ---------------------------------------------------------- orphanedImages

test("orphanedImages names the files an edit stopped referencing", () => {
    const dir = "/state/pshell/clipboard/images";
    const before = [image(dir + "/a.png"), image(dir + "/b.png"), text("t")];
    const after = [image(dir + "/b.png"), text("t")];
    assert.deepEqual(H.orphanedImages(before, after, dir), [dir + "/a.png"]);
    assert.deepEqual(H.orphanedImages(before, [], dir + "/"), [dir + "/a.png", dir + "/b.png"]);
});

// The guard that matters. A path outside the shell's own directory -- from a
// hand-edited history.json, say -- is somebody's file, not a cache entry.
test("orphanedImages never names a file outside the image directory", () => {
    const dir = "/state/pshell/clipboard/images";
    const before = [
        image("/home/u/photo.png"),
        image(dir + "/../notes.png"),
        image("/state/pshell/clipboard/images-other/x.png"),
    ];
    assert.deepEqual(H.orphanedImages(before, [], dir), []);
    assert.deepEqual(H.orphanedImages([image("/a.png")], [], ""), []);
});

// ------------------------------------------------------------------- files

test("a text/uri-list copy shows as file names", () => {
    assert.equal(H.previewText(text("file:///home/u/My%20File.txt")), "My File.txt");
    assert.equal(H.previewText(text("file:///a/one.txt\nfile:///a/two.txt\n")), "2 files");
    assert.deepEqual(H.filePaths(text("file://localhost/etc/hosts")), ["/etc/hosts"]);
});

test("one URI inside prose is prose, not a file", () => {
    assert.deepEqual(H.filePaths(text("see file:///etc/hosts\nfor details")), []);
    assert.deepEqual(H.filePaths(text("file:///etc/hosts\nnot a uri")), []);
});

// ------------------------------------------------------------- displayRows

test("displayRows shows newest first, one line each, with history indexes", () => {
    const rows = H.displayRows([text("a\n  b"), image("/s/i.png")], "", 50);
    assert.deepEqual(rows.map(r => r.previewText), ["a b", "Image"]);
    assert.deepEqual(rows.map(r => r.index), [0, 1]);
    assert.equal(rows[1].entryType, "image");
    assert.equal(rows[1].previewImage, "/s/i.png");
});

test("displayRows filters by case-insensitive substring and keeps true indexes", () => {
    const rows = H.displayRows([text("Apple"), text("banana"), text("PINEAPPLE")], "apple", 50);
    assert.deepEqual(rows.map(r => r.index), [0, 2]);
});

test("displayRows finds images by the word image and files by name", () => {
    const h = [text("file:///tmp/Report.pdf"), image("/s/i.png"), text("other")];
    assert.deepEqual(H.displayRows(h, "image", 50).map(r => r.index), [1]);
    assert.deepEqual(H.displayRows(h, "report", 50).map(r => r.index), [0]);
});

test("displayRows stops at the limit", () => {
    const h = Array.from({ length: 80 }, (_, i) => text("row " + i));
    assert.equal(H.displayRows(h, "", 50).length, 50);
    assert.equal(H.displayRows(h, "row 7", 50).length, 11);
});

test("a single image file copied from a file manager previews as an image", () => {
    const [row] = H.displayRows([text("file:///p/shot.PNG")], "", 50);
    assert.equal(row.entryType, "file");
    assert.equal(row.previewImage, "/p/shot.PNG");
    assert.equal(row.fullText, "/p/shot.PNG");
});

test("a huge entry is drawn capped on a line break, but history keeps it whole", () => {
    const line = "x".repeat(100) + "\n";
    const big = line.repeat(200);
    const h = [text(big)];
    const [row] = H.displayRows(h, "", 50);
    assert.ok(row.fullText.length <= 8192);
    assert.ok(row.fullText.endsWith("x"));
    assert.equal(h[0].text.length, big.length);
});

test("a huge entry with no line break is cut at the limit", () => {
    const [row] = H.displayRows([text("y".repeat(20000))], "", 50);
    assert.equal(row.fullText.length, 8192);
});

test("an image's label takes a time only when given a formatter", () => {
    assert.equal(H.previewText(image("/s/a.png", { time: 5 })), "Image");
    assert.equal(H.previewText(image("/s/a.png", { time: 5 }), () => "Mon 14:02"), "Image from Mon 14:02");
    assert.equal(H.previewText(image("/s/a.jpg", { mime: "image/jpeg" })), "JPEG image");
});
