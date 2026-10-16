.pragma library

// What a notification body is allowed to be by the time a Text draws it.
//
// The widgets render bodies as Text.StyledText, which is the right format
// for the markup the spec allows -- <b>, <i>, <u>, <a href> -- but which also
// honours <img src="...">, and fetches http(s) sources over the network.
// Any app (or any website through a browser's notification bridge) could
// put a tracking pixel in a body and learn when, and from which IP, the
// toast was drawn -- and again every time the history panel redraws the
// saved record, long after the notification itself is gone.
// bodyImagesSupported: false only *tells* applications not to send them; it
// stops nothing. So every body goes through sanitize() first, and the
// filtering happens at render time rather than on arrival so records
// already sitting in notifications.json are covered too.
//
// Plain functions, no QML, so tests/notification-markup.test.mjs can load
// the very file the widgets import.

// Tags that survive, emitted bare -- whatever attributes they arrived with
// are dropped, since none of them means anything StyledText should act on.
// <br> is not in the spec's list but plenty of senders use it for line
// breaks, and it can neither fetch nor link anything.
var _bareTags = { b: true, i: true, u: true, br: true };

// One complete tag. Attribute values are matched as quoted runs so a ">"
// inside alt="a>b" does not end the tag early and spill the rest of it out
// as text.
var _tagPattern = /<(\/?)([A-Za-z][A-Za-z0-9]*)((?:"[^"]*"|'[^']*'|[^'">])*)>/g;

// The schemes a click may hand to Qt.openUrlExternally. Anything else --
// file:, javascript:, a custom handler some app registered -- is a click
// that runs something rather than opens a page, which no notification gets
// to decide for the user.
function isSafeLink(url) {
    return /^(https?:\/\/|mailto:)/i.test(String(url === undefined || url === null ? "" : url).trim());
}

// Text that is not part of a recognised tag. A stray "<" is escaped rather
// than left for StyledText to guess at -- an unterminated "<img src=..." is
// exactly the input a lenient parser might still act on. Entities ("&amp;")
// are left alone: the spec allows them and StyledText decodes them.
function _escapeText(text) {
    return text.replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function _escapeAttr(text) {
    return _escapeText(text).replace(/"/g, "&quot;");
}

// The value of one attribute in a tag's attribute run, or null if absent.
function _attr(attrs, name) {
    var m = new RegExp("(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))", "i").exec(attrs);
    if (!m)
        return null;
    return m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3]);
}

// The body with <b>, <i>, <u>, <br> and safe <a href> kept, <img> replaced
// by its alt text, and every other tag removed with its text kept. Links
// whose href is not http(s) or mailto lose the link but keep their text.
function sanitize(body) {
    var source = body === undefined || body === null ? "" : String(body);
    var out = "";
    var last = 0;
    // Closing </a> tags are only kept for openings that were, so an unsafe
    // link's dropped opening does not leave a stray close behind.
    var openLinks = 0;
    var m;

    _tagPattern.lastIndex = 0;
    while ((m = _tagPattern.exec(source)) !== null) {
        out += _escapeText(source.slice(last, m.index));
        last = _tagPattern.lastIndex;

        var closing = m[1] === "/";
        var name = m[2].toLowerCase();
        var attrs = m[3];

        if (_bareTags[name]) {
            out += name === "br" ? "<br>" : "<" + (closing ? "/" : "") + name + ">";
        } else if (name === "a") {
            if (closing) {
                if (openLinks > 0) {
                    openLinks--;
                    out += "</a>";
                }
            } else {
                var href = _attr(attrs, "href");
                if (href !== null && isSafeLink(href)) {
                    openLinks++;
                    out += "<a href=\"" + _escapeAttr(href.trim()) + "\">";
                }
            }
        } else if (name === "img" && !closing) {
            // The alt text is what the sender meant the reader to see in
            // place of the picture; the source is never touched.
            var alt = _attr(attrs, "alt");
            if (alt)
                out += _escapeText(alt);
        }
        // Anything else is dropped, its text content kept.
    }
    out += _escapeText(source.slice(last));
    return out;
}
