import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const M = loadQmlJs("Services/NotificationMarkup.js");

// ---------------------------------------------------------------- sanitize

test("sanitize keeps the spec's basic markup", () => {
  assert.equal(M.sanitize("<b>bold</b> <i>it</i> <u>un</u>"), "<b>bold</b> <i>it</i> <u>un</u>");
});

test("sanitize keeps plain text and entities as they are", () => {
  assert.equal(M.sanitize("Tom &amp; Jerry"), "Tom &amp; Jerry");
  assert.equal(M.sanitize(""), "");
  assert.equal(M.sanitize(undefined), "");
  assert.equal(M.sanitize(null), "");
});

test("sanitize removes remote images entirely", () => {
  const out = M.sanitize('hi <img src="https://track.example/p.gif"> there');
  assert.equal(out, "hi  there");
  assert.doesNotMatch(out, /img|src|track/);
});

test("sanitize swaps an image for its alt text", () => {
  assert.equal(M.sanitize('<img alt="cat" src="http://x/cat.png"/>'), "cat");
});

test("sanitize is not fooled by a > inside a quoted attribute", () => {
  const out = M.sanitize('<img alt="a>b" src="http://x/p.gif">');
  assert.doesNotMatch(out, /<img|src=/i);
});

test("sanitize matches tags case-insensitively", () => {
  assert.doesNotMatch(M.sanitize('<IMG SRC="http://x/p.gif">'), /<img/i);
  assert.equal(M.sanitize("<B>x</B>"), "<b>x</b>");
});

test("sanitize escapes an unterminated tag rather than passing it on", () => {
  assert.equal(M.sanitize('<img src="http://x/p.gif"'), '&lt;img src="http://x/p.gif"');
  assert.equal(M.sanitize("1 < 2"), "1 &lt; 2");
});

test("sanitize strips attributes from kept tags", () => {
  assert.equal(M.sanitize('<b style="x" onclick="y">x</b>'), "<b>x</b>");
});

test("sanitize drops unknown tags but keeps their text", () => {
  assert.equal(M.sanitize('<font color="red">red</font>'), "red");
  assert.equal(M.sanitize("<h1>big</h1>"), "big");
});

test("sanitize keeps http, https and mailto links", () => {
  assert.equal(M.sanitize('<a href="https://a.example/x?y=1">x</a>'), '<a href="https://a.example/x?y=1">x</a>');
  assert.equal(M.sanitize("<a href='http://a.example'>x</a>"), '<a href="http://a.example">x</a>');
  assert.equal(M.sanitize('<a href=mailto:me@a.example>x</a>'), '<a href="mailto:me@a.example">x</a>');
});

test("sanitize unlinks other schemes but keeps the text", () => {
  assert.equal(M.sanitize('<a href="file:///etc/passwd">x</a>'), "x");
  assert.equal(M.sanitize('<a href="javascript:alert(1)">x</a>'), "x");
  assert.equal(M.sanitize('<a href="&#106;avascript:alert(1)">x</a>'), "x");
  assert.equal(M.sanitize("<a>x</a>"), "x");
});

test("sanitize keeps a quote in a link from breaking out of href", () => {
  const out = M.sanitize(`<a href='https://a.example/"><img src=http://x>'>x</a>`);
  assert.doesNotMatch(out, /<img/);
});

test("sanitize normalises line breaks", () => {
  assert.equal(M.sanitize("a<br/>b<BR >c"), "a<br>b<br>c");
});

// -------------------------------------------------------------- isSafeLink

test("isSafeLink allows only http, https and mailto", () => {
  assert.equal(M.isSafeLink("https://a.example"), true);
  assert.equal(M.isSafeLink("HTTP://a.example"), true);
  assert.equal(M.isSafeLink("mailto:me@a.example"), true);
  assert.equal(M.isSafeLink("file:///etc/passwd"), false);
  assert.equal(M.isSafeLink("javascript:alert(1)"), false);
  assert.equal(M.isSafeLink("steam://run/1"), false);
  assert.equal(M.isSafeLink("http:/missing-slash"), false);
  assert.equal(M.isSafeLink(""), false);
  assert.equal(M.isSafeLink(undefined), false);
});
