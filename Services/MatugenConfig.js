.pragma library

// Assembles the matugen config TOML that makes one matugen run render theme
// files for the rest of the desktop alongside the palette the bar reads.
//
// Kept pure -- no files, no environment, no Quickshell -- for the same reason
// ConfigPath.js is: so node can load it and test it without a running shell.
// Theme.qml gathers the paths and the user's template list and hands them in
// as one options object.
//
// The template set is a data list, not a config string, on purpose: the next
// thing that needs theming -- an OSD, a launcher -- is added by appending one
// record to BUILTIN_TEMPLATES, and the TOML emission cannot drift from entry
// to entry because there is only one place that writes it.

// The templates pshell ships. Order is render order.
//
// - gtk3 and gtk4 render the *same* template to two paths. That is
//   deliberate: the colour definitions are identical and GTK3 and GTK4 read
//   from different directories.
// - Every output is pshell-colors.* or themes/pshell*, never the app's real
//   config file. pshell generates a file the user *includes*; it does not own
//   anyone else's config. The README documents the include line for each.
// - kitty is the only one needing a post_hook -- it reloads on SIGUSR1.
//   Alacritty watches its own config file. btop, ghostty, zed and qt6ct read
//   their theme at start. The `|| true` matters: pkill exits non-zero when no
//   kitty is running, and matugen should not report that as a failure.
var BUILTIN_TEMPLATES = [
    {
        name: "gtk3",
        input: "gtk-colors.css",
        output: "gtk-3.0/pshell-colors.css"
    },
    {
        name: "gtk4",
        input: "gtk-colors.css",
        output: "gtk-4.0/pshell-colors.css"
    },
    {
        name: "kitty",
        input: "kitty.conf",
        output: "kitty/pshell-colors.conf",
        postHook: "pkill -SIGUSR1 -x kitty || true"
    },
    {
        name: "ghostty",
        input: "ghostty.conf",
        output: "ghostty/themes/pshell"
    },
    {
        name: "alacritty",
        input: "alacritty.toml",
        output: "alacritty/pshell-colors.toml"
    },
    {
        name: "btop",
        input: "btop.theme",
        output: "btop/themes/pshell.theme"
    },
    {
        name: "zed",
        input: "zed.json",
        output: "zed/themes/pshell.json"
    },
    {
        name: "qtct",
        input: "qtct-colors.conf",
        output: "qt6ct/colors/pshell.conf"
    }
];

// The sixteen ANSI colours, fed to matugen as custom colours with
// blend = true so a terminal gets a harmonised set rather than sixteen
// shades of the accent. The seeds are the standard xterm base sixteen:
// matugen blends each toward the wallpaper's palette, so the seed decides
// the hue family and the wallpaper decides the rest.
var ANSI = {
    ansi_0: "#000000",
    ansi_1: "#800000",
    ansi_2: "#008000",
    ansi_3: "#808000",
    ansi_4: "#000080",
    ansi_5: "#800080",
    ansi_6: "#008080",
    ansi_7: "#c0c0c0",
    ansi_8: "#808080",
    ansi_9: "#ff0000",
    ansi_10: "#00ff00",
    ansi_11: "#ffff00",
    ansi_12: "#0000ff",
    ansi_13: "#ff00ff",
    ansi_14: "#00ffff",
    ansi_15: "#ffffff"
};

// TOML basic (double-quoted) strings, not literal single-quoted ones. A path
// containing an apostrophe is legal on Linux and would silently truncate a
// single-quoted string; basic strings only need \ and " escaped.
function tomlString(value) {
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

// A TOML table key is bare only for [A-Za-z0-9_-]; anything else -- a user
// template named "my kitty" -- has to be quoted or matugen refuses the file.
function tomlKey(name) {
    var s = String(name);
    if (/^[A-Za-z0-9_-]+$/.test(s))
        return s;
    return tomlString(s);
}

// The same contract as Config.expandHome(): only a *leading* ~/ is the
// user's shorthand for home; a ~ anywhere else is a legal path character
// and rewriting it would corrupt the path.
function expandHome(path, home) {
    var p = String(path || "");
    if (p.indexOf("~/") === 0)
        return String(home || "") + p.substring(1);
    return p;
}

function emitTemplate(lines, sectionName, input, output, postHook) {
    lines.push("");
    lines.push("[templates." + tomlKey(sectionName) + "]");
    lines.push("input_path = " + tomlString(input));
    lines.push("output_path = " + tomlString(output));
    if (postHook)
        lines.push("post_hook = " + tomlString(postHook));
}

// The complete matugen config as a TOML string.
//
// options:
//   shellDir        - the pshell checkout, absolute; template inputs live
//                     under <shellDir>/assets/matugen/templates/
//   configDir       - the user's config dir, absolute (~/.config); built-in
//                     outputs are relative to it
//   home            - the home directory, for ~/ in user template outputs
//   userTemplateDir - where user template inputs live, absolute
//   userTemplates   - [{ name, input, output, postHook }], appended after
//                     the built-ins; postHook may be absent
//   disabled        - built-in names to leave out, so a user who hates what
//                     pshell does to their kitty config can switch that one
//                     off without switching the feature off
function buildConfig(options) {
    var opts = options || {};
    var disabled = opts.disabled || [];
    var userTemplates = opts.userTemplates || [];
    var lines = [];

    lines.push("# Written by pshell on every matugen run; edits do not survive.");
    lines.push("# Assembled from Services/MatugenConfig.js.");
    lines.push("");
    lines.push("[config.custom_colors]");
    for (var name in ANSI)
        lines.push(name + " = { color = " + tomlString(ANSI[name]) + ", blend = true }");

    // Every section name emitted so far. A duplicate table is a TOML error
    // that takes the whole run down -- no palette, no built-ins -- so no
    // section may ever be written twice, whatever the caller sent.
    var used = {};

    // Built-ins first, in list order; user templates after, in the order
    // given. Nothing is sorted -- render order is declaration order.
    for (var i = 0; i < BUILTIN_TEMPLATES.length; i++) {
        var t = BUILTIN_TEMPLATES[i];
        if (disabled.indexOf(t.name) >= 0)
            continue;
        used["pshell_" + t.name] = true;
        emitTemplate(lines, "pshell_" + t.name, opts.shellDir + "/assets/matugen/templates/" + t.input, opts.configDir + "/" + t.output, t.postHook);
    }

    // pshell_user_, not pshell_: a user template named "kitty" would
    // otherwise duplicate the [templates.pshell_kitty] table. Two user
    // templates sharing a name are the same trap one namespace over, and
    // Theme.qml's per-entry validation cannot see it -- each entry is fine
    // alone. So the first of a name wins and the rest are skipped with a
    // warning, the same contract a malformed entry gets: one bad line in
    // templates.json must never cost the user their palette.
    for (var j = 0; j < userTemplates.length; j++) {
        var u = userTemplates[j];
        var section = "pshell_user_" + u.name;
        if (used[section]) {
            console.warn("pshell: user template \"" + u.name + "\" repeats an earlier name, skipped");
            continue;
        }
        used[section] = true;
        emitTemplate(lines, section, opts.userTemplateDir + "/" + u.input, expandHome(u.output, opts.home), u.postHook);
    }

    return lines.join("\n") + "\n";
}

// What matugen 4.2.0 accepts, kept here so Theme.qml's IPC can reject a typo
// before it reaches a process invocation, and so the lists are testable.
//
// Named lists rather than literals inside the validators, because the theme
// settings page builds its dropdowns from them: the menu the user picks from
// and the allow-list the setter checks against must be one list, or the two
// drift and the UI offers a value the service refuses.
var SCHEMES = ["scheme-content", "scheme-expressive", "scheme-fidelity", "scheme-fruit-salad", "scheme-monochrome", "scheme-neutral", "scheme-rainbow", "scheme-tonal-spot", "scheme-vibrant", "scheme-smart"];
var PREFERS = ["darkness", "lightness", "saturation", "less-saturation", "value", "closest-to-fallback"];

function isValidScheme(name) {
    return SCHEMES.indexOf(String(name)) >= 0;
}

function isValidPrefer(name) {
    return PREFERS.indexOf(String(name)) >= 0;
}
