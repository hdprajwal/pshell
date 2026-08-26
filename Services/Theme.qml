pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import "MatugenConfig.js" as MatugenConfig

// Colours derived from the wallpaper with matugen.
//
// This used to read matugen's JSON off stdout *instead of* using its template
// and config files: nothing was written to disk, so there was no second file
// to keep in sync and the bar was the only thing themed. That was the right
// trade while the bar was the only customer. It stopped being right when the
// terminal, GTK apps and btop needed the same palette -- a bar that matches
// the wallpaper next to a terminal that does not is worse than neither
// matching.
//
// So the same single matugen run now also renders templates to disk: pshell
// writes a config file naming them, and matugen prints the palette JSON to
// stdout (read here, exactly as before) *and* renders every template in one
// process. The cost is what the old comment prized the absence of: generated
// files on disk. They are contained by ownership -- every output is a
// pshell-colors.* or themes/pshell* file that pshell alone writes and may
// overwrite, included from the user's real configs, never those configs
// themselves.
//
// This is inert unless the config sets `theme: "wallpaper"` -- a user on
// manual colours gets no files generated behind their back -- and explicit
// colours in config.json always win over anything generated here.
Singleton {
    id: root

    property var palette: ({})
    property bool available: false

    readonly property bool enabled: Config.theme === "wallpaper" && Config.wallpaperPath !== ""

    readonly property string bg: palette.bg || ""
    readonly property string fg: palette.fg || ""
    readonly property string accent: palette.accent || ""
    readonly property string urgent: palette.urgent || ""
    readonly property string dim: palette.dim || ""

    // For the theme page's dropdowns. The menu offered and the allow-list
    // enforced come from the same arrays in MatugenConfig.js, so the UI can
    // never offer a value the setters below would refuse.
    readonly property var schemes: MatugenConfig.SCHEMES
    readonly property var prefers: MatugenConfig.PREFERS

    // The setters live on the root, not the IpcHandler, so the settings page
    // and the command line go through the same validation -- IdleInhibit's
    // handler delegates to root functions for the same reason. They write
    // through Config.set(), so the change lands in config.json and the
    // Connections below re-run matugen: the same path an edit in a text
    // editor takes.
    function setScheme(name) {
        if (!MatugenConfig.isValidScheme(name)) {
            console.warn("pshell: unknown matugen scheme:", name);
            return;
        }
        Config.set("matugenScheme", name);
    }

    function setPrefer(name) {
        if (!MatugenConfig.isValidPrefer(name)) {
            console.warn("pshell: unknown matugen prefer:", name);
            return;
        }
        Config.set("matugenPrefer", name);
    }

    // `auto` clears the pin: Config.mode only honours the literal strings
    // "light" and "dark" and falls back to SystemTheme.scheme for anything
    // else, so writing "" hands the choice back to the desktop.
    function setMode(mode) {
        if (mode === "auto") {
            Config.set("mode", "");
            return;
        }
        if (mode !== "light" && mode !== "dark") {
            console.warn("pshell: unknown mode:", mode, "- expected light, dark or auto");
            return;
        }
        Config.set("mode", mode);
    }

    // A flat file directly in the runtime directory, not a subdirectory:
    // $XDG_RUNTIME_DIR always exists and a subdirectory would need creating.
    readonly property string matugenConfigPath: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR");
        return (rt && rt !== "" ? rt : "/tmp") + "/pshell-matugen.toml";
    }

    // From ~/.config/pshell/templates.json, validated before it gets here.
    property var userTemplates: []

    // A malformed entry is skipped with a warning naming it; it never stops
    // the built-ins from rendering. WidgetRegistry treats a broken manifest
    // the same way, and for the same reason: one bad file the user is midway
    // through editing should not take the whole feature down.
    function _readUserTemplates(raw) {
        var parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (e) {
            console.warn("pshell: templates.json is not valid JSON —", e);
            return [];
        }
        if (!Array.isArray(parsed)) {
            console.warn("pshell: templates.json is not an array, ignored");
            return [];
        }

        const out = [];
        for (var i = 0; i < parsed.length; i++) {
            const t = parsed[i];
            const name = t && typeof t.name === "string" ? t.name : "";
            if (!t || name === "" || typeof t.input !== "string" || t.input === "" || typeof t.output !== "string" || t.output === "") {
                console.warn("pshell: templates.json entry", i + 1, name === "" ? "(unnamed)" : "(" + name + ")", "needs name, input and output, skipped");
                continue;
            }
            const entry = {
                name: name,
                input: t.input,
                output: t.output
            };
            if (typeof t.postHook === "string" && t.postHook !== "")
                entry.postHook = t.postHook;
            out.push(entry);
        }
        return out;
    }

    function _setUserTemplates(next) {
        // Compared as JSON so the initial load -- which usually parses to the
        // same list already in place -- does not queue a second matugen run
        // on top of the one Component.onCompleted started.
        if (JSON.stringify(next) === JSON.stringify(root.userTemplates))
            return;
        root.userTemplates = next;
        root.refresh();
    }

    // What refresh() asked configFile to write, promoted to _writtenConfig
    // once the save lands. Kept so a refresh that changes nothing in the
    // config -- a mode flip changes only the command line -- can skip the
    // write instead of trusting FileView to save unchanged text.
    property string _pendingConfig: ""
    property string _writtenConfig: ""

    function refresh() {
        if (!enabled) {
            palette = ({});
            return;
        }

        const home = Quickshell.env("HOME");
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const configDir = xdg && xdg !== "" ? xdg : home + "/.config";
        const toml = MatugenConfig.buildConfig({
            shellDir: Quickshell.shellDir,
            configDir: configDir,
            home: home,
            userTemplateDir: configDir + "/pshell/templates",
            userTemplates: root.userTemplates,
            disabled: Config.disabledTemplates
        });

        if (toml === root._writtenConfig) {
            _run();
            return;
        }

        // matugen starts from configFile.onSaved, not here: the config must
        // exist on disk before matugen reads it, and setText is not
        // synchronous.
        root._pendingConfig = toml;
        configFile.setText(toml);
    }

    function _run() {
        if (!enabled)
            return;
        generator.command = ["matugen", "-c", root.matugenConfigPath, "image", Config.wallpaperPath, "--json", "hex", "--prefer", Config.matugenPrefer, "--type", Config.matugenScheme, "--mode", Config.mode];
        generator.running = false;
        generator.running = true;
    }

    onEnabledChanged: refresh()
    Component.onCompleted: refresh()

    // wallpaperPath, not wallpaper: the two are separate bindings, and the
    // notification for the one being edited arrives before the one derived
    // from it has been re-evaluated. Watching `wallpaper` meant refresh() read
    // last wallpaper's path and matugen re-ran on the image just replaced.
    Connections {
        target: Config
        function onWallpaperPathChanged() {
            root.refresh();
        }
        function onModeChanged() {
            root.refresh();
        }
        function onDisabledTemplatesChanged() {
            root.refresh();
        }
    }

    FileView {
        id: configFile

        path: root.matugenConfigPath
        // Loading is pointless here -- this file is only ever written -- and a
        // missing one on first start is the normal case, not an error.
        printErrors: false

        onSaved: {
            root._writtenConfig = root._pendingConfig;
            root._run();
        }

        onSaveFailed: error => {
            console.warn("pshell: could not write the matugen config —", error, "- colours will not refresh");
        }
    }

    // The user's own template list: ~/.config/pshell/templates.json names
    // files in ~/.config/pshell/templates/ and where each should render to.
    // Watched, so saving the file re-renders without a restart -- the same
    // contract config.json already has.
    FileView {
        id: userTemplatesFile

        path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/pshell/templates.json"
        watchChanges: true
        // A missing file is the normal case -- most users never write one --
        // not an error.
        printErrors: false

        onLoaded: root._setUserTemplates(root._readUserTemplates(text()))
        onFileChanged: reload()
        onLoadFailed: root._setUserTemplates([])
    }

    Process {
        id: generator

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (raw === "")
                    return;

                var parsed;
                try {
                    parsed = JSON.parse(raw);
                } catch (e) {
                    console.warn("pshell: matugen output was not JSON:", e);
                    return;
                }

                const colors = parsed.colors;
                if (!colors)
                    return;

                const mode = Config.mode;
                function pick(name) {
                    const role = colors[name];
                    if (!role)
                        return "";
                    const variant = role[mode] || role.default;
                    return variant ? variant.color || "" : "";
                }

                // surface over background: on a wallpaper with a flat dark
                // edge the two are identical anyway, and surface stays
                // readable when they differ.
                root.palette = {
                    bg: pick("surface"),
                    fg: pick("on_surface"),
                    accent: pick("primary"),
                    urgent: pick("error"),
                    dim: pick("outline")
                };
                root.available = true;
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("pshell: matugen failed with exit", code, "- falling back to configured colours");
        }
    }

    // No keep-alive line in shell.qml for this target, unlike pshell.lock and
    // pshell.idle: Config's colour properties read Theme.bg, so bringing
    // Config to life -- which the bar does on every start -- builds this
    // singleton and registers the handler with it.
    IpcHandler {
        target: "pshell.theme"

        function reload(): void {
            root.refresh();
        }

        function setScheme(name: string): void {
            root.setScheme(name);
        }

        function setPrefer(name: string): void {
            root.setPrefer(name);
        }

        function setMode(mode: string): void {
            root.setMode(mode);
        }

        function current(): string {
            return "scheme=" + Config.matugenScheme + " prefer=" + Config.matugenPrefer + " mode=" + Config.mode + " wallpaper=" + (Config.wallpaperPath || "(none)");
        }
    }
}
