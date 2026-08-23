.pragma library

// Writing into config.json's object, kept pure so it can be tested without a
// FileView, a Quickshell instance or a real config file.
//
// Every function returns a new object and never mutates its argument. That is
// not politeness: Config.data is a `var` property, and QML only re-evaluates
// the bindings that read it when the property is *reassigned*. Mutating in
// place would write the file correctly and leave the whole shell showing the
// old value, which is the sort of bug that gets blamed on the file watcher.
// Services/Prefs.qml already builds a new object for the same reason.

// config.json is two levels deep and never three, so a dotted path splits on
// its *first* dot only and everything after it is one literal key.
//
// That is not an arbitrary depth limit, it is the file's shape. The `shell`
// block is a flat map of Omarchy's dotted token names -- `"popups.border"`,
// `"spacing.bar-gap"` -- so "shell.popups.border" means the key
// `popups.border` inside `shell`, and splitting on every dot would invent a
// `popups` object that Config.qml's shellDefaults loop would then skip,
// silently losing the setting. `margin.top` is the other two-level case and
// it splits the same way.
function splitPath(dotted) {
    var s = String(dotted);
    var at = s.indexOf(".");
    if (at < 0)
        return [s];
    return [s.substr(0, at), s.substr(at + 1)];
}

function getPath(data, dotted) {
    var parts = splitPath(dotted);
    var node = data;
    for (var i = 0; i < parts.length; i++) {
        if (node === null || typeof node !== "object")
            return undefined;
        node = node[parts[i]];
    }
    return node;
}

// A dotted path addresses nested objects: "position" is a top-level key and
// "shell.popups.border" is a key inside the `shell` object. The intermediate
// object is created if it is missing.
//
// A path that would have to walk *through* a non-object -- "margin.top" when
// `margin` is the number 4 -- returns the config unchanged rather than
// silently replacing the number with an object. config.json accepts `margin`
// as either a number or an object, so turning one into the other behind the
// user's back would change what the bar looks like for a setting they did not
// touch.
function setPath(data, dotted, value) {
    var parts = splitPath(dotted);
    var root = {};
    var key;
    for (key in data)
        root[key] = data[key];

    var node = root;
    for (var i = 0; i < parts.length - 1; i++) {
        var name = parts[i];
        var child = node[name];
        if (child === undefined || child === null) {
            child = {};
        } else if (typeof child !== "object" || Array.isArray(child)) {
            return data;
        } else {
            var copy = {};
            for (key in child)
                copy[key] = child[key];
            child = copy;
        }
        node[name] = child;
        node = child;
    }

    node[parts[parts.length - 1]] = value;
    return root;
}

// ------------------------------------------------------- widget entries

var SECTIONS = ["left", "center", "right"];

// A widget's settings live inline in whichever of the three bar sections it
// was placed in, so changing one means finding it first. A built-in is
// addressed by its `type` and an on-disk widget by its `id`; both are
// accepted because the settings app should not have to know which kind it is
// looking at.
function findWidget(data, widgetId) {
    for (var s = 0; s < SECTIONS.length; s++) {
        var section = SECTIONS[s];
        var list = data ? data[section] : undefined;
        if (!Array.isArray(list))
            continue;
        for (var i = 0; i < list.length; i++) {
            var entry = list[i] || {};
            if (entry.id === widgetId || entry.type === widgetId)
                return {
                    section: section,
                    index: i
                };
        }
    }
    return null;
}

// A widget that is not in the bar has no entry to write into, and inventing
// one would silently add a widget the user never asked for. Returning the
// config unchanged lets the caller decide -- in practice the settings app
// only offers a widget's settings when it found the widget.
function setWidgetSetting(data, widgetId, key, value) {
    var found = findWidget(data, widgetId);
    if (found === null)
        return data;

    var root = {};
    var k;
    for (k in data)
        root[k] = data[k];

    var list = root[found.section].slice();
    var entry = {};
    for (k in list[found.index])
        entry[k] = list[found.index][k];
    entry[key] = value;
    list[found.index] = entry;
    root[found.section] = list;
    return root;
}
