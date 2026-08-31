.pragma library

// Turning `hyprctl binds -j` into a cheat sheet.
//
// Kept pure -- no Process, no Quickshell -- for the reason Backlight.js is:
// decoding a bitmask and deciding what a row says are real logic with real
// edge cases, and node can only test what it can load. Widgets/Keybinds runs
// the command and hands the parsed array in.
//
// What the compositor can and cannot tell us, measured on this machine
// (Hyprland 0.56.2, 119 binds):
//
//   * WHICH keys are bound is authoritative and cannot go stale. That is the
//     whole reason this reads the compositor rather than a config file.
//   * WHAT a bind does is only knowable when the bind itself carries a
//     `description`. Every bind here reports `dispatcher: "__lua"` with an
//     opaque numeric `arg` -- Hyprland is driven from hyprland.lua, and a Lua
//     bind's action is a closure the compositor has no words for. 4 of 119
//     carry a description; the other 115 have "__lua" and a number, which is
//     not an answer to "what does SUPER+D do".
//
// So nothing here ever renders "__lua" or that number. A row whose action
// cannot be described says so, and the user can name it themselves through
// the label map. Honest beats meaningless.

// The modifier bits, verbatim from Hyprland's own header rather than from
// memory or the wiki: /usr/include/hyprland/src/devices/IKeyboard.hpp,
// `enum eKeyboardModifiers`. All eight bits of the low byte are assigned.
//
// The ORDER of this array is the render order, and it is not the bit order.
// SUPER, CTRL, ALT, SHIFT first because that is the order people write and
// read them -- "SUPER+SHIFT+Return", never "SHIFT+SUPER+Return" -- and
// because it is the order Hyprland's own docs use. The four nobody binds
// deliberately follow, in bit order, so the tail is at least predictable.
// Pinned in tests/keybinds.test.mjs: a rearrangement here silently changes
// every key in a user's label map.
var MODIFIERS = [
    {
        bit: 64,
        name: "SUPER"
    } // HL_MODIFIER_META
    , {
        bit: 4,
        name: "CTRL"
    } // HL_MODIFIER_CTRL
    , {
        bit: 8,
        name: "ALT"
    } // HL_MODIFIER_ALT
    , {
        bit: 1,
        name: "SHIFT"
    } // HL_MODIFIER_SHIFT
    , {
        bit: 2,
        name: "CAPS"
    } // HL_MODIFIER_CAPS
    , {
        bit: 16,
        name: "MOD2"
    } // HL_MODIFIER_MOD2
    , {
        bit: 32,
        name: "MOD3"
    } // HL_MODIFIER_MOD3
    , {
        bit: 128,
        name: "MOD5"
    } // HL_MODIFIER_MOD5
];

// Every bit the table above accounts for.
var KNOWN_BITS = 255;

// What a row says when nobody has described it. One string, here, so the
// panel and the count agree about what "unlabelled" means.
var UNLABELLED = "not labelled";

// 64 -> ["SUPER"], 65 -> ["SUPER", "SHIFT"], 0 -> [].
//
// A bit outside the table is reported rather than dropped: a future Hyprland
// with a ninth modifier would otherwise make this print a combination that is
// missing a key you have to hold, which is worse than admitting there is one
// we cannot name.
function decodeModmask(mask) {
    var value = Number(mask);
    if (!isFinite(value) || value <= 0)
        return [];
    value = Math.floor(value);

    var out = [];
    for (var i = 0; i < MODIFIERS.length; i++) {
        if (value & MODIFIERS[i].bit)
            out.push(MODIFIERS[i].name);
    }

    var unknown = value & ~KNOWN_BITS;
    if (unknown > 0)
        out.push("UNKNOWN(" + unknown + ")");
    return out;
}

// The label-map key, and the string the panel prints on the row. One string
// for both on purpose: a label is then copied off the screen into
// config.json rather than derived from it by hand.
//
// Stable and documented, because a user's `keybinds.labels` is keyed by it:
//
//   * modifiers in the fixed order above, joined with "+", then the key
//     exactly as Hyprland reports it -- "Return", "TAB", "comma", "down",
//     "XF86AudioMute". Case is not normalised: it is the compositor's own
//     spelling, and lookups are case-insensitive anyway.
//   * a mouse bind keeps Hyprland's token: "SUPER+mouse:272",
//     "SUPER+mouse_down". That is also what the user typed in their config,
//     so it round-trips.
//   * a bind with no key at all normalises to the modifiers plus "?".
//     Hyprland reports an empty `key` AND `keycode: 0` for a `code:NN` bind
//     (both such binds on this machine do), so there is genuinely nothing
//     left to name it with. Two of those under the same modifiers collide on
//     one map key -- unavoidable, and worth knowing: label them from the Lua
//     side instead, where the bind still knows what it is.
function normaliseKey(bind) {
    var mods = decodeModmask(bind ? bind.modmask : 0);
    var key = String((bind && bind.key) || "").trim();
    if (key === "")
        key = "?";
    return mods.concat([key]).join("+");
}

// What the row says this bind does, and where that came from.
//
// Three sources, in this order, and the order is the ruling this feature was
// built under:
//
//   hyprland  the compositor's own `description`. Nothing beats it: it came
//             from the bind itself.
//   label     the user's `keybinds.labels` map. Their words for a bind
//             Hyprland cannot describe.
//   none      neither. The row shows the key combination and says it is
//             unlabelled. pshell does not guess from a dispatcher name.
//
// `description` is read rather than `has_description`, because the flag
// being true with an empty string would still leave nothing to print.
//
// The map is matched case-insensitively on the whole combination, so
// "super+d" in config.json finds the bind Hyprland spells "SUPER+D".
function describe(bind, labels) {
    var hypr = String((bind && bind.description) || "").trim();
    if (hypr !== "")
        return {
            text: hypr,
            source: "hyprland"
        };

    var combo = normaliseKey(bind);
    var wanted = combo.toLowerCase();
    if (labels) {
        for (var key in labels) {
            if (String(key).toLowerCase() !== wanted)
                continue;
            var value = String(labels[key] || "").trim();
            if (value !== "")
                return {
                    text: value,
                    source: "label"
                };
        }
    }

    return {
        text: UNLABELLED,
        source: "none"
    };
}

// The order groups are shown in: modifier count first, then the modifier
// order above.
//
// Count first because that is how a sheet is read -- everything on SUPER
// alone is one block, everything on SUPER+SHIFT is the next -- and it keeps
// the two- and three-modifier groups, which are the rare ones, out of the
// middle. Alphabetical would open the sheet on ALT.
function _rank(mods) {
    var order = [];
    for (var i = 0; i < mods.length; i++) {
        var at = -1;
        for (var m = 0; m < MODIFIERS.length; m++) {
            if (MODIFIERS[m].name === mods[i])
                at = m;
        }
        // An unknown modifier sorts after every known one rather than
        // ahead of SUPER by accident.
        order.push(at < 0 ? MODIFIERS.length : at);
    }
    return order;
}

function _compareGroups(a, b) {
    // Root binds before submap binds. A submap is a mode: its binds only
    // work after you have entered it, and mixing them into the root list
    // would be the sheet lying about what SUPER+H does right now.
    if ((a.submap === "") !== (b.submap === ""))
        return a.submap === "" ? -1 : 1;
    if (a.submap !== b.submap)
        return a.submap < b.submap ? -1 : 1;

    if (a.mods.length !== b.mods.length)
        return a.mods.length - b.mods.length;

    var ra = _rank(a.mods);
    var rb = _rank(b.mods);
    for (var i = 0; i < ra.length; i++) {
        if (ra[i] !== rb[i])
            return ra[i] - rb[i];
    }
    return 0;
}

// What a group is called. The modifiers as they will appear on every row in
// it, or "No modifier" for the bare keys -- the media and brightness keys,
// mostly -- and the submap named outright when there is one.
function groupTitle(mods, submap) {
    var base = mods.length > 0 ? mods.join("+") : "No modifier";
    var name = String(submap || "");
    return name === "" ? base : "submap " + name + " · " + base;
}

// The binds, grouped for display.
//
// Returns [{ title, mods, submap, unlabelled, rows: [row] }] where a row is
// { combo, key, mods, description, source, submap }.
//
// Never drops a bind. A bind with no key and no description is still
// somewhere in here -- under its modifiers, with "?" for a key and the
// unlabelled state -- because a cheat sheet that quietly holds fewer rows
// than the compositor has binds is worse than one with an ugly row in it.
// tests/keybinds.test.mjs pins the total.
function group(binds, labels) {
    var list = Array.isArray(binds) ? binds : [];
    var groups = [];
    var index = {};

    for (var i = 0; i < list.length; i++) {
        var bind = list[i] || {};
        var mods = decodeModmask(bind.modmask);
        var submap = String(bind.submap || "");
        var said = describe(bind, labels);
        var title = groupTitle(mods, submap);

        if (index[title] === undefined) {
            index[title] = groups.length;
            groups.push({
                title: title,
                mods: mods,
                submap: submap,
                unlabelled: 0,
                rows: []
            });
        }

        var into = groups[index[title]];
        into.rows.push({
            combo: normaliseKey(bind),
            key: String(bind.key || ""),
            mods: mods,
            description: said.text,
            source: said.source,
            submap: submap,
            // The original position, so the sort below can fall back on it
            // rather than depending on the engine's sort being stable.
            order: i
        });
        if (said.source === "none")
            into.unlabelled++;
    }

    for (var g = 0; g < groups.length; g++) {
        groups[g].rows.sort(function (x, y) {
            var kx = x.key.toLowerCase();
            var ky = y.key.toLowerCase();
            if (kx !== ky)
                return kx < ky ? -1 : 1;
            return x.order - y.order;
        });
    }

    groups.sort(_compareGroups);
    return groups;
}

// How many rows there are and how many nobody has described, straight off
// what group() already worked out. The panel says both out loud: a feature
// that silently under-delivers is worse than one that admits what it is
// missing.
function countUnlabelled(groups) {
    var total = 0;
    var unlabelled = 0;
    var list = Array.isArray(groups) ? groups : [];
    for (var i = 0; i < list.length; i++) {
        total += list[i].rows.length;
        unlabelled += list[i].unlabelled;
    }
    return {
        total: total,
        unlabelled: unlabelled
    };
}

// The panel's filter. Matches the combination and the description both,
// because you may be hunting either: "what is on SUPER+Y" or "which key
// takes a screenshot".
function filter(groups, query) {
    var text = String(query || "").trim().toLowerCase();
    var list = Array.isArray(groups) ? groups : [];
    if (text === "")
        return list;

    var out = [];
    for (var i = 0; i < list.length; i++) {
        var kept = list[i].rows.filter(function (row) {
            return row.combo.toLowerCase().indexOf(text) >= 0 || row.description.toLowerCase().indexOf(text) >= 0;
        });
        if (kept.length === 0)
            continue;
        var unlabelled = 0;
        for (var k = 0; k < kept.length; k++) {
            if (kept[k].source === "none")
                unlabelled++;
        }
        out.push({
            title: list[i].title,
            mods: list[i].mods,
            submap: list[i].submap,
            unlabelled: unlabelled,
            rows: kept
        });
    }
    return out;
}
