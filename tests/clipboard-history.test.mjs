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

// The shell loads uncapped and trims itself, so a cap lowered while it was
// down -- or set to zero -- still forgets the entries past it, and their
// image files with them.
test("parseHistory with no cap reads everything, so a smaller cap can be applied after", () => {
    const dir = "/state/pshell/clipboard/images";
    const raw = JSON.stringify([text("a"), image(`${dir}/1.png`), text("b"), image(`${dir}/2.png`)]);
    const full = H.parseHistory(raw, Infinity);
    assert.equal(full.length, 4);

    assert.deepEqual(H.orphanedImages(full, full.slice(0, 1), dir), [`${dir}/1.png`, `${dir}/2.png`]);
    assert.deepEqual(H.orphanedImages(full, full.slice(0, 0), dir), [`${dir}/1.png`, `${dir}/2.png`]);
    assert.deepEqual(H.orphanedImages(full, full.slice(0, 3), dir), [`${dir}/2.png`]);
});

test("parseHistory with no cap still reads more than the default 500", () => {
    const raw = JSON.stringify(Array.from({ length: 700 }, (_, i) => text(`t${i}`)));
    assert.equal(H.parseHistory(raw, Infinity).length, 700);
    assert.equal(H.parseHistory(raw).length, 500);
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

// -------------------------------------------------------------------- pins

const pin = e => ({ ...e, pinned: true });
const texts = h => h.map(e => (e.pinned ? "*" : "") + e.text);

test("a history from before pins loads with nothing pinned and no new field", () => {
    const h = H.parseHistory(JSON.stringify([text("a"), image("/s/x.png")]), Infinity);
    assert.deepEqual(h, [text("a"), image("/s/x.png")]);
    assert.equal(H.pinnedCount(h), 0);
});

test("normalizeEntry keeps pinned only when it is exactly true", () => {
    assert.equal(H.normalizeEntry(pin(text("a"))).pinned, true);
    assert.equal("pinned" in H.normalizeEntry(text("a", { pinned: "yes" })), false);
    assert.equal("pinned" in H.normalizeEntry(text("a", { pinned: false })), false);
});

test("parseHistory reads every pin whatever the cap, and puts them first", () => {
    const raw = JSON.stringify([text("a"), text("b"), pin(text("p")), text("c")]);
    assert.deepEqual(texts(H.parseHistory(raw, 1)), ["*p", "a"]);
    assert.deepEqual(texts(H.parseHistory(raw, 0)), ["*p"]);
});

test("pins never count toward the cap, and copies never push them off", () => {
    let h = [pin(text("keep")), pin(text("also"))];
    for (let i = 0; i < 10; i++)
        h = H.addEntry(h, text(String(i)), 3);
    assert.deepEqual(texts(h), ["*keep", "*also", "9", "8", "7"]);
});

test("re-copying a pinned entry neither duplicates it nor unpins it, and stamps its time", () => {
    const h = [pin(text("p", { time: 1 })), text("a", { time: 2 })];
    const out = H.addEntry(h, text("p", { time: 9 }), 10);
    assert.deepEqual(texts(out), ["*p", "a"]);
    assert.equal(out[0].time, 9);
    assert.equal(H.newestIndex(out), 0);
});

test("re-copying a pinned entry does not evict a rolling one at the cap", () => {
    const h = [pin(text("p")), text("a"), text("b")];
    assert.deepEqual(texts(H.addEntry(h, text("p"), 2)), ["*p", "a", "b"]);
});

test("a copy arriving marked pinned is still recorded unpinned", () => {
    assert.deepEqual(texts(H.addEntry([], pin(text("x")), 10)), ["x"]);
});

test("a cap of zero keeps the pins and nothing else", () => {
    assert.deepEqual(texts(H.addEntry([pin(text("p")), text("a")], text("b"), 0)), ["*p"]);
    assert.deepEqual(texts(H.capHistory([text("a"), pin(text("p"))], 0)), ["*p"]);
});

test("setPinned moves a pin to the end of the pinned entries", () => {
    const h = [pin(text("p")), text("a"), text("b"), text("c")];
    assert.deepEqual(texts(H.setPinned(h, 2, true, 10)), ["*p", "*b", "a", "c"]);
});

test("setPinned unpins back to the top of the rolling history", () => {
    const h = [pin(text("p")), pin(text("q")), text("a")];
    assert.deepEqual(texts(H.setPinned(h, 0, false, 10)), ["*q", "p", "a"]);
});

test("unpinning at a full cap pushes the oldest rolling entry off, not the unpinned one", () => {
    const h = [pin(text("p")), text("a"), text("b")];
    assert.deepEqual(texts(H.setPinned(h, 0, false, 2)), ["p", "a"]);
});

test("unpinning with a cap of zero forgets the entry", () => {
    assert.deepEqual(H.setPinned([pin(text("p"))], 0, false, 0), []);
});

test("setPinned ignores a bad index and a pin that is already one", () => {
    const h = [pin(text("p")), text("a")];
    assert.deepEqual(texts(H.setPinned(h, 5, true, 10)), ["*p", "a"]);
    assert.deepEqual(texts(H.setPinned(h, -1, true, 10)), ["*p", "a"]);
    assert.deepEqual(texts(H.setPinned(h, 0, true, 10)), ["*p", "a"]);
    assert.deepEqual(texts(H.setPinned(h, 1, false, 10)), ["*p", "a"]);
});

test("setPinned does not mutate the array it was given", () => {
    const h = [text("a")];
    H.setPinned(h, 0, true, 10);
    assert.deepEqual(h, [text("a")]);
});

test("pinnedOnly is what clearing leaves", () => {
    const h = [pin(text("p")), text("a"), pin(image("/s/x.png"))];
    assert.deepEqual(H.pinnedOnly(h).map(e => e.text || e.path), ["p", "/s/x.png"]);
});

test("an image a pin references is never named an orphan", () => {
    const h = [pin(image("/s/img/x.png")), image("/s/img/y.png")];
    assert.deepEqual(H.orphanedImages(h, H.pinnedOnly(h), "/s/img"), ["/s/img/y.png"]);
    let rolled = h;
    for (let i = 0; i < 5; i++)
        rolled = H.addEntry(rolled, text(String(i)), 2);
    assert.deepEqual(H.orphanedImages(h, rolled, "/s/img"), ["/s/img/y.png"]);
});

test("newestIndex finds the latest copy, pinned or not", () => {
    assert.equal(H.newestIndex([]), -1);
    assert.equal(H.newestIndex([pin(text("p", { time: 1 })), text("a", { time: 5 })]), 1);
    assert.equal(H.newestIndex([pin(text("p", { time: 7 })), text("a", { time: 5 })]), 0);
});

test("newestIndex prefers the rolling history's first entry on a tie", () => {
    assert.equal(H.newestIndex([pin(text("p")), text("a"), text("b")]), 1);
    assert.equal(H.newestIndex([text("a"), text("b")]), 0);
});

test("displayRows draws pins first, marked, and searches them like the rest", () => {
    const h = [pin(text("pinned token")), text("plain token"), text("other")];
    const rows = H.displayRows(h, "", 10);
    assert.deepEqual(rows.map(r => r.pinned), [true, false, false]);
    const found = H.displayRows(h, "TOKEN", 10);
    assert.deepEqual(found.map(r => [r.index, r.pinned]), [[0, true], [1, false]]);
});

test("a huge pinned entry is drawn capped and still marked pinned", () => {
    const big = pin(text("x".repeat(H.displayTextLimit + 10)));
    assert.equal(H.cappedEntry(big).pinned, true);
});

test("displayRows' limit counts only unpinned rows, so pins never hide recent copies", () => {
    const h = [];
    for (let i = 0; i < 60; i++)
        h.push(pin(text("pin " + i)));
    for (let i = 0; i < 60; i++)
        h.push(text("copy " + i));
    const rows = H.displayRows(h, "", 50);
    assert.equal(rows.filter(r => r.pinned).length, 60);
    assert.equal(rows.filter(r => !r.pinned).length, 50);
    assert.equal(rows[60].previewText, "copy 0");
    // Filtered, the same: matching pins, then up to the limit of the rest.
    const found = H.displayRows(h, "1", 3);
    assert.deepEqual(found.map(r => r.previewText), [
        "pin 1", "pin 10", "pin 11", "pin 12", "pin 13", "pin 14", "pin 15", "pin 16", "pin 17", "pin 18", "pin 19",
        "pin 21", "pin 31", "pin 41", "pin 51", "copy 1", "copy 10", "copy 11",
    ]);
});

test("historyLines lists every pin, marked, then N of the rest, numbered by index", () => {
    const h = [pin(text("p0")), pin(text("p1")), text("a"), text("b"), text("c")];
    assert.equal(H.historyLines(h, 2), "0\t[pin] p0\n1\t[pin] p1\n2\ta\n3\tb");
    assert.equal(H.historyLines(h, 0), "0\t[pin] p0\n1\t[pin] p1\n2\ta\n3\tb\n4\tc");
    assert.equal(H.historyLines(h, -1).split("\n").length, 5);
    assert.equal(H.historyLines([], 5), "");
});

test("historyLines numbers match displayRows' indexes", () => {
    const h = [pin(text("p")), text("a\nb"), image("/s/i.png")];
    const fromCli = H.historyLines(h, 50).split("\n").map(l => Number(l.split("\t")[0]));
    assert.deepEqual(fromCli, H.displayRows(h, "", 50).map(r => r.index));
});

test("historyLine marks a pin inside the preview column, keeping two fields", () => {
    assert.equal(H.historyLine(pin(text("x\ty")), 0).split("\t").length, 2);
    assert.equal(H.historyLine(text("x"), 4), "4\tx");
    assert.equal(H.historyLine(pin(image("/s/i.png")), 1), "1\t[pin] Image");
});
