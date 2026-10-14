import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const U = loadQmlJs("Services/Updates.js");

// Lines as `arch-update --check` writes them on this machine, trimmed.
const PACKAGES = "bash 5.3.15-2 -> 5.3.20-2\nbat 0.26.1-2.1 -> 0.26.1-3.1\nblender 17:5.2.2-1 -> 17:5.2.2-3\n";
const AUR = "1password 8.12.22-17 -> 8.12.40-31\n";
const FLATPAK = "FreeCAD 1.1.4\nMesa (Extra) 26.2.2\n";

// --------------------------------------------------------------- reading

test("parseLines drops blank lines and surrounding space", () => {
    assert.deepEqual(U.parseLines("  a 1 -> 2 \n\n\nb 3 -> 4\n   \n"), ["a 1 -> 2", "b 3 -> 4"]);
});

test("parseLines answers nothing for nothing", () => {
    for (const v of [undefined, null, "", "\n", "  \n \n"])
        assert.deepEqual(U.parseLines(v), [], String(v));
});

// The interactive updater writes what checkupdates printed, and a terminal
// that asked for colour gets it.
test("parseLines takes colour codes out", () => {
    assert.deepEqual(U.parseLines("\x1B[1mbash\x1B[0m 5.3.15-2 -> \x1B[1;32m5.3.20-2\x1B[0m"), ["bash 5.3.15-2 -> 5.3.20-2"]);
});

test("parseEntry splits a repo line into name and versions", () => {
    assert.deepEqual(U.parseEntry("blender 17:5.2.2-1 -> 17:5.2.2-3", "repo"), {
        source: "repo",
        name: "blender",
        from: "17:5.2.2-1",
        to: "17:5.2.2-3",
        line: "blender 17:5.2.2-1 -> 17:5.2.2-3",
    });
});

// NoVersion in arch-update.conf leaves a bare name.
test("parseEntry takes a bare name as the name", () => {
    const e = U.parseEntry("paru-bin", "aur");
    assert.equal(e.name, "paru-bin");
    assert.equal(e.from, "");
    assert.equal(e.to, "");
});

// A Flatpak display name has spaces in it, so the whole line is the name
// rather than "Mesa" with a version of "(Extra)".
test("parseEntry keeps a Flatpak line whole", () => {
    const e = U.parseEntry("Mesa (Extra) 26.2.2", "flatpak");
    assert.equal(e.name, "Mesa (Extra) 26.2.2");
    assert.equal(e.from, "");
});

test("summarize counts each source and the total", () => {
    const s = U.summarize({ packages: PACKAGES, aur: AUR, flatpak: FLATPAK, combined: PACKAGES + AUR + FLATPAK });
    assert.equal(s.found, true);
    assert.equal(s.repo, 3);
    assert.equal(s.aur, 1);
    assert.equal(s.flatpak, 2);
    assert.equal(s.total, 6);
    assert.deepEqual(s.entries.map(e => e.source), ["repo", "repo", "repo", "aur", "flatpak", "flatpak"]);
});

// The split files win: the updater empties each one as it finishes that part
// and only then rewrites the combined one, so the two disagree for a moment
// and the split ones are the newer.
test("summarize reads the split files, not the combined one", () => {
    const s = U.summarize({ packages: "", aur: AUR, flatpak: "", combined: PACKAGES + AUR });
    assert.equal(s.total, 1);
    assert.equal(s.aur, 1);
});

test("summarize with every file empty is found and up to date", () => {
    const s = U.summarize({ packages: "", aur: "", flatpak: "", combined: "" });
    assert.equal(s.found, true);
    assert.equal(s.total, 0);
});

// A state directory that does not exist yet -- no check has ever run -- is
// not the same answer as "up to date".
test("summarize with no files at all is not found", () => {
    const s = U.summarize({ packages: null, aur: null, flatpak: null, combined: null });
    assert.equal(s.found, false);
    assert.equal(s.total, 0);
    assert.deepEqual(s.entries, []);
});

test("summarize with some split files missing counts the rest", () => {
    const s = U.summarize({ packages: PACKAGES, aur: null, flatpak: null, combined: null });
    assert.equal(s.found, true);
    assert.equal(s.total, 3);
});

// An arch-update older than the split files writes only the combined one.
test("summarize falls back to the combined file when it is all there is", () => {
    const s = U.summarize({ packages: null, aur: null, flatpak: null, combined: PACKAGES + AUR });
    assert.equal(s.found, true);
    assert.equal(s.repo, 4);
    assert.equal(s.total, 4);
});

test("parseCheckTime reads the epoch off the first line", () => {
    assert.equal(U.parseCheckTime("1791898084\n2026-10-13 09:28:04\n"), 1791898084);
});

test("parseCheckTime answers 0 for anything else", () => {
    for (const v of [undefined, null, "", "2026-10-13 09:28:04", "17918x", "-5"])
        assert.equal(U.parseCheckTime(v), 0, String(v));
});

// --------------------------------------------------------------- writing

test("breakdown names only the sources that have something", () => {
    assert.equal(U.breakdown({ repo: 10, aur: 1, flatpak: 2 }), "10 repo, 1 AUR, 2 Flatpak");
    assert.equal(U.breakdown({ repo: 0, aur: 3, flatpak: 0 }), "3 AUR");
    assert.equal(U.breakdown({ repo: 0, aur: 0, flatpak: 0 }), "");
});

test("formatAge picks the largest unit that fits", () => {
    const now = 1_000_000;
    assert.equal(U.formatAge(now, now - 5), "just now");
    assert.equal(U.formatAge(now, now - 60), "1 minute ago");
    assert.equal(U.formatAge(now, now - 59 * 60), "59 minutes ago");
    assert.equal(U.formatAge(now, now - 3600), "1 hour ago");
    assert.equal(U.formatAge(now, now - 47 * 3600), "47 hours ago");
    assert.equal(U.formatAge(now, now - 48 * 3600), "2 days ago");
});

test("formatAge says never for no check, and just now for the future", () => {
    assert.equal(U.formatAge(1000, 0), "never");
    assert.equal(U.formatAge(1000, 5000), "just now");
});

test("statusLine with updates gives the count, the split, the age and the tool", () => {
    const summary = U.summarize({ packages: PACKAGES, aur: AUR, flatpak: "", combined: null });
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 1000, now: 1000 + 7200, checking: false });
    assert.equal(line, "4 updates (3 repo, 1 AUR), checked 2 hours ago, by cachy-update");
});

test("statusLine says up to date, and that a check is running", () => {
    const summary = U.summarize({ packages: "", aur: "", flatpak: "" });
    const line = U.statusLine({ available: "arch-update", summary, checkedAt: 990, now: 1000, checking: true });
    assert.equal(line, "up to date, checked just now, checking now, by arch-update");
});

test("statusLine before any check has run", () => {
    const summary = U.summarize({});
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 0, now: 1000, checking: false });
    assert.equal(line, "never checked, by cachy-update");
});

test("statusLine without either tool says so", () => {
    const line = U.statusLine({ available: "", summary: U.summarize({}), checkedAt: 0, now: 0, checking: false });
    assert.match(line, /^unavailable: /);
    assert.match(line, /cachy-update/);
    assert.match(line, /arch-update/);
});

test("singular counts read as singular", () => {
    const summary = U.summarize({ packages: "bash 1 -> 2" });
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 1000, now: 1060, checking: false });
    assert.match(line, /^1 update \(1 repo\), checked 1 minute ago/);
});

test("listText puts the source and a tab before each line", () => {
    const s = U.summarize({ packages: "bash 1 -> 2", aur: "paru 3 -> 4", flatpak: "Mesa (Extra) 26.2.2" });
    assert.equal(U.listText(s.entries), "repo\tbash 1 -> 2\naur\tparu 3 -> 4\nflatpak\tMesa (Extra) 26.2.2");
});

test("listText of nothing is empty", () => {
    assert.equal(U.listText([]), "");
});

// ------------------------------------------------------------- terminal

test("pickTerminal prefers the configured terminal", () => {
    assert.equal(U.pickTerminal("kitty", "alacritty", ["ghostty", "kitty", "alacritty"]), "kitty");
});

test("pickTerminal falls back to $TERMINAL, then to the table's order", () => {
    assert.equal(U.pickTerminal("", "alacritty", ["ghostty", "alacritty"]), "alacritty");
    assert.equal(U.pickTerminal("", "", ["alacritty", "ghostty"]), "ghostty");
});

// A config or a $TERMINAL naming something uninstalled would otherwise turn
// the click into nothing at all.
test("pickTerminal passes over a choice that is not installed", () => {
    assert.equal(U.pickTerminal("wezterm", "urxvt", ["kitty"]), "kitty");
});

test("pickTerminal answers empty when there is nothing", () => {
    assert.equal(U.pickTerminal("", "", []), "");
    assert.equal(U.pickTerminal(undefined, undefined, undefined), "");
});

test("pickTerminal takes a configured path", () => {
    assert.equal(U.pickTerminal("/opt/bin/kitty", "", ["/opt/bin/kitty", "ghostty"]), "/opt/bin/kitty");
});

test("terminalArgv sets the class the way each terminal spells it", () => {
    const cmd = ["cachy-update"];
    assert.deepEqual(U.terminalArgv("ghostty", "pshell.updates", "Updates", cmd),
        ["ghostty", "--class=pshell.updates", "--title=Updates", "--gtk-single-instance=false", "-e", "cachy-update"]);
    assert.deepEqual(U.terminalArgv("kitty", "pshell.updates", "Updates", cmd),
        ["kitty", "--class", "pshell.updates", "--title", "Updates", "cachy-update"]);
    assert.deepEqual(U.terminalArgv("alacritty", "pshell.updates", "Updates", cmd),
        ["alacritty", "--class", "pshell.updates", "--title", "Updates", "-e", "cachy-update"]);
    assert.deepEqual(U.terminalArgv("foot", "pshell.updates", "Updates", cmd),
        ["foot", "--app-id=pshell.updates", "--title=Updates", "cachy-update"]);
    assert.deepEqual(U.terminalArgv("wezterm", "pshell.updates", "Updates", cmd),
        ["wezterm", "start", "--class", "pshell.updates", "--", "cachy-update"]);
});

test("terminalArgv knows a terminal by its name even given a path", () => {
    assert.deepEqual(U.terminalArgv("/usr/local/bin/kitty", "a.b", "T", ["x"]),
        ["/usr/local/bin/kitty", "--class", "a.b", "--title", "T", "x"]);
});

test("terminalArgv gives an unknown terminal -e", () => {
    assert.deepEqual(U.terminalArgv("xterm", "a.b", "T", ["cachy-update"]), ["xterm", "-e", "cachy-update"]);
});

// The class goes into a Lua string inside a regex, so its dot has to reach
// Hyprland as `\.` -- written `\\.` in the Lua source.
test("floatRule matches exactly the updater's class", () => {
    const rule = U.floatRule("pshell.updates");
    assert.match(rule, /^hl\.window_rule\(\{/);
    assert.ok(rule.includes('class = "^(pshell\\\\.updates)$"'), rule);
    assert.match(rule, /name = "pshell-updates"/);
    assert.match(rule, /float = true/);
});

// A rule stays in the compositor after the click that added it, so turning
// floating off has to replace it with one that is switched off -- same
// name, same match -- rather than just not sending it.
test("floatRule with float off replaces the rule with a disabled one", () => {
    const rule = U.floatRule("pshell.updates", false);
    assert.match(rule, /name = "pshell-updates"/);
    assert.ok(rule.includes('class = "^(pshell\\\\.updates)$"'), rule);
    assert.match(rule, /enabled = false/);
    assert.doesNotMatch(rule, /float = true/);
});

test("floatRule floats unless told not to", () => {
    assert.match(U.floatRule("a.b", true), /float = true/);
    assert.match(U.floatRule("a.b", undefined), /float = true/);
});
