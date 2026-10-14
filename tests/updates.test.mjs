import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, existsSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

// The updater empties a split file and rewrites the combined one straight
// after, so once both are written they agree and the count goes down.
test("summarize follows the updater as it empties each source", () => {
    const s = U.summarize({ packages: "", aur: AUR, flatpak: FLATPAK, combined: AUR + FLATPAK });
    assert.equal(s.consistent, true);
    assert.equal(s.total, 3);
    assert.equal(s.repo, 0);
    assert.equal(s.aur, 1);
});

// check.sh's `checkupdates > last_updates_check_packages` empties the file
// for the seconds pacman spends syncing. The combined file still holds the
// last finished check, and that is the count.
test("summarize keeps the last finished count while a check has a split file emptied", () => {
    const s = U.summarize({ packages: "", aur: AUR, flatpak: FLATPAK, combined: PACKAGES + AUR + FLATPAK });
    assert.equal(s.consistent, false);
    assert.equal(s.found, true);
    assert.equal(s.total, 6);
    assert.equal(s.aur, 1);
    assert.equal(s.flatpak, 2);
    // Nothing says where the repo lines came from but the default.
    assert.equal(s.repo, 3);
});

// All three emptied at once, mid-check, must not read as "up to date".
test("summarize does not read three emptied split files as up to date", () => {
    const s = U.summarize({ packages: "", aur: "", flatpak: "", combined: PACKAGES + AUR + FLATPAK });
    assert.equal(s.consistent, false);
    assert.equal(s.total, 6);
});

// A split file half-written by the check: the same count of lines, but not
// the same lines, is still a disagreement.
test("summarize compares the lines, not just how many", () => {
    const s = U.summarize({ packages: "zsh 1 -> 2\n", aur: "", flatpak: "", combined: "bash 1 -> 2\n" });
    assert.equal(s.consistent, false);
    assert.deepEqual(s.entries.map(e => e.name), ["bash"]);
});

// While they disagree, the summary before is the better guide to which
// source each of the combined file's lines is from: the split files are the
// half-written ones.
test("summarize takes each line's source from the previous summary while the files disagree", () => {
    const before = U.summarize({ packages: PACKAGES, aur: AUR, flatpak: FLATPAK, combined: PACKAGES + AUR + FLATPAK });
    const s = U.summarize({ packages: "", aur: "", flatpak: "", combined: PACKAGES + AUR + FLATPAK }, before.entries);
    assert.deepEqual([s.repo, s.aur, s.flatpak, s.total], [3, 1, 2, 6]);
    assert.deepEqual(s.entries.map(e => e.source), before.entries.map(e => e.source));
});

// check.sh writes the combined file with `echo`, so an empty result is one
// blank line.
test("summarize with every file empty is found and up to date", () => {
    for (const combined of ["", "\n"]) {
        const s = U.summarize({ packages: "", aur: "", flatpak: "", combined });
        assert.equal(s.found, true);
        assert.equal(s.consistent, true);
        assert.equal(s.total, 0);
    }
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
    const s = U.summarize({ packages: PACKAGES, aur: null, flatpak: null, combined: PACKAGES });
    assert.equal(s.found, true);
    assert.equal(s.consistent, true);
    assert.equal(s.total, 3);
});

// The very first check touches the split files before anything else and
// writes the combined one last. Until then there has been no check.
test("summarize with split files but no combined one has not been checked yet", () => {
    const s = U.summarize({ packages: "", aur: "", flatpak: "", combined: null });
    assert.equal(s.found, false);
    assert.equal(s.consistent, false);
    assert.equal(s.total, 0);
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
    const summary = U.summarize({ packages: PACKAGES, aur: AUR, flatpak: "", combined: PACKAGES + AUR });
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 1000, now: 1000 + 7200, checking: false });
    assert.equal(line, "4 updates (3 repo, 1 AUR), checked 2 hours ago, by cachy-update");
});

test("statusLine says up to date, and that a check is running", () => {
    const summary = U.summarize({ packages: "", aur: "", flatpak: "", combined: "" });
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
    const summary = U.summarize({ packages: "bash 1 -> 2", combined: "bash 1 -> 2" });
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 1000, now: 1060, checking: false });
    assert.match(line, /^1 update \(1 repo\), checked 1 minute ago/);
});

test("listText puts the source and a tab before each line", () => {
    const s = U.summarize({ packages: "bash 1 -> 2", aur: "paru 3 -> 4", flatpak: "Mesa (Extra) 26.2.2", combined: "bash 1 -> 2\nparu 3 -> 4\nMesa (Extra) 26.2.2" });
    assert.equal(U.listText(s.entries), "repo\tbash 1 -> 2\naur\tparu 3 -> 4\nflatpak\tMesa (Extra) 26.2.2");
});

test("listText of nothing is empty", () => {
    assert.equal(U.listText([]), "");
});

// ------------------------------------------------------------- terminal

test("pickTerminal prefers the configured terminal", () => {
    const t = U.pickTerminal("kitty", "alacritty", ["ghostty", "kitty", "alacritty"]);
    assert.equal(t.name, "kitty");
    assert.deepEqual(t.argv, ["kitty"]);
    assert.equal(t.note, "");
});

test("pickTerminal falls back to $TERMINAL, then to the table's order", () => {
    assert.equal(U.pickTerminal("", "alacritty", ["ghostty", "alacritty"]).name, "alacritty");
    assert.equal(U.pickTerminal("", "", ["alacritty", "ghostty"]).name, "ghostty");
});

// A config or a $TERMINAL naming something uninstalled would otherwise turn
// the click into nothing at all; the note is for `open`'s reply, so the
// fallback is not silent.
test("pickTerminal passes over a choice that is not installed, and says so", () => {
    const t = U.pickTerminal("wezterm", "urxvt", ["kitty"]);
    assert.equal(t.name, "kitty");
    assert.match(t.note, /config\.json names wezterm, which is not installed/);
    assert.match(t.note, /\$TERMINAL names urxvt/);
});

test("pickTerminal answers empty when there is nothing", () => {
    assert.deepEqual(U.pickTerminal("", "", []), { argv: [], name: "", note: "" });
    assert.deepEqual(U.pickTerminal(undefined, undefined, undefined), { argv: [], name: "", note: "" });
});

test("pickTerminal takes a configured path", () => {
    assert.equal(U.pickTerminal("/opt/bin/kitty", "", ["/opt/bin/kitty", "ghostty"]).name, "/opt/bin/kitty");
});

// "kitty -1" used to fail `command -v` as a whole and quietly fall back.
// The program is what is looked for; the arguments go along with it.
test("pickTerminal keeps the arguments given with the terminal", () => {
    const t = U.pickTerminal("  kitty   -1 ", "", ["kitty"]);
    assert.equal(t.name, "kitty");
    assert.deepEqual(t.argv, ["kitty", "-1"]);
    assert.equal(t.note, "");
});

test("splitTerminal splits on whitespace and nothing else", () => {
    assert.deepEqual(U.splitTerminal("kitty -1"), ["kitty", "-1"]);
    assert.deepEqual(U.splitTerminal("foot --override='a b'"), ["foot", "--override='a", "b'"]);
    assert.deepEqual(U.splitTerminal("kitty; rm -rf ~"), ["kitty;", "rm", "-rf", "~"]);
    for (const v of ["", "   ", undefined, null])
        assert.deepEqual(U.splitTerminal(v), [], String(v));
});

test("terminalArgv puts the user's own arguments straight after the terminal", () => {
    assert.deepEqual(U.terminalArgv(["kitty", "-1"], "a.b", "T", ["x"]),
        ["kitty", "-1", "--class", "a.b", "--title", "T", "x"]);
    assert.deepEqual(U.terminalArgv(["xterm", "-fa", "Mono"], "a.b", "T", ["x"]),
        ["xterm", "-fa", "Mono", "-e", "x"]);
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

// ------------------------------------------------------------- status

// The time file is written last, so a first check part-way through has
// split files and no time: "checked never" said nothing true.
test("statusLine leaves out when it was checked when there is no time", () => {
    const summary = U.summarize({ packages: "bash 1 -> 2", combined: "bash 1 -> 2" });
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 0, now: 1000, checking: true });
    assert.equal(line, "1 update (1 repo), checking now, by cachy-update");
});

test("statusLine says when the updater is running, and when a check could not fetch", () => {
    const summary = U.summarize({ packages: "bash 1 -> 2", combined: "bash 1 -> 2" });
    const line = U.statusLine({ available: "cachy-update", summary, checkedAt: 1000, now: 1000, checking: false, updating: true, fetchFailed: true });
    assert.match(line, /could not reach the mirrors/);
    assert.match(line, /updating now/);
});

// ------------------------------------------------------------- refresh

// The refresh script itself, run by sh against fakes: a systemctl that
// logs what it was asked and has the unit or not, a journalctl with or
// without checkupdates' failure in it, and a fake tool. Nothing here
// reaches the real user manager: PATH starts with the fakes, and the lock
// is a file in the sandbox, never /tmp/arch-update.lock.
function sandbox({ unit = true, journal = "", toolStderr = "", toolCode = 0, systemctl = true } = {}) {
    const dir = mkdtempSync(join(tmpdir(), "pshell-updates-refresh-"));
    const bin = join(dir, "bin");
    spawnSync("mkdir", ["-p", bin]);
    const script = (name, body) => {
        writeFileSync(join(bin, name), "#!/bin/sh\n" + body);
        chmodSync(join(bin, name), 0o755);
    };
    if (systemctl)
        script("systemctl", `echo "$*" >> "${dir}/systemctl.log"
case "$2" in
cat) ${unit ? "exit 0" : "echo 'No files found' >&2; exit 1"} ;;
start) exit 0 ;;
show) echo 0123abcd ;;
esac
`);
    script("journalctl", `echo "$*" >> "${dir}/journalctl.log"
printf '%s\n' ${JSON.stringify(journal)}
`);
    script("fake-update", `echo "$*" >> "${dir}/tool.log"
printf '%s\n' ${JSON.stringify(toolStderr)} >&2
exit ${toolCode}
`);
    return { dir, bin, lock: join(dir, "arch-update.lock") };
}

function runRefresh(box) {
    const argv = U.refreshArgv("fake-update", box.lock, "arch-update.service");
    const r = spawnSync(argv[0], argv.slice(1), { env: { PATH: box.bin + ":/usr/bin:/bin", HOME: box.dir }, encoding: "utf8" });
    return { code: r.status, out: U.parseRefresh(r.stdout), stdout: r.stdout };
}

const log = (box, name) => existsSync(join(box.dir, name)) ? readFileSync(join(box.dir, name), "utf8") : "";

test("refresh starts the timer's unit when there is one, and not the tool", () => {
    const box = sandbox();
    const r = runRefresh(box);
    assert.equal(r.code, 0);
    assert.deepEqual(r.out, { busy: false, via: "systemd", fetchFailed: false });
    assert.match(log(box, "systemctl.log"), /^--user start arch-update\.service$/m);
    assert.equal(log(box, "tool.log"), "");
    // The journal is read for this run only.
    assert.match(log(box, "journalctl.log"), /_SYSTEMD_INVOCATION_ID=0123abcd/);
});

test("refresh runs `<tool> --check` itself where the unit is missing", () => {
    for (const opts of [{ unit: false }, { systemctl: false }]) {
        const box = sandbox(opts);
        const r = runRefresh(box);
        assert.equal(r.out.via, "direct", JSON.stringify(opts));
        assert.equal(log(box, "tool.log"), "--check\n");
        assert.doesNotMatch(log(box, "systemctl.log"), /start/);
    }
});

test("refresh passes the direct check's exit code on", () => {
    const box = sandbox({ unit: false, toolCode: 3 });
    assert.equal(runRefresh(box).code, 3);
});

test("refresh notices checkupdates could not reach the mirrors, by either path", () => {
    const viaUnit = runRefresh(sandbox({ journal: "==> ERROR: Cannot fetch updates" }));
    assert.equal(viaUnit.out.fetchFailed, true);
    const direct = runRefresh(sandbox({ unit: false, toolStderr: "==> ERROR: Cannot fetch updates" }));
    assert.equal(direct.out.fetchFailed, true);
    assert.equal(runRefresh(sandbox({ journal: "Finished Run arch-update auto check." })).out.fetchFailed, false);
});

// The interactive updater holds the lock for as long as it runs. A check
// then could write the list from before `pacman -Syu` over update.sh's.
test("refresh refuses, and starts nothing, while the updater holds its lock", async () => {
    const box = sandbox();
    const holder = spawn("flock", [box.lock, "sleep", "5"], { stdio: "ignore" });
    try {
        // Wait for the holder to have it.
        for (let i = 0; i < 50 && spawnSync("flock", ["-n", "-E", "75", box.lock, "true"]).status !== 75; i++)
            await new Promise(r => setTimeout(r, 20));
        const r = runRefresh(box);
        assert.equal(r.out.busy, true);
        assert.equal(r.out.via, "");
        assert.equal(log(box, "systemctl.log"), "");
        assert.equal(log(box, "tool.log"), "");
        const probe = U.lockProbeArgv(box.lock);
        assert.equal(spawnSync(probe[0], probe.slice(1), { encoding: "utf8" }).stdout, "held\n");
    } finally {
        holder.kill();
    }
});

test("the lock probe is quiet when nobody holds the lock", () => {
    const box = sandbox();
    const probe = U.lockProbeArgv(box.lock);
    assert.equal(spawnSync(probe[0], probe.slice(1), { encoding: "utf8" }).stdout, "");
});

test("refreshArgv and lockProbeArgv default to arch-update's own lock and unit", () => {
    const argv = U.refreshArgv("cachy-update");
    assert.deepEqual(argv.slice(3), ["pshell-updates-refresh", "cachy-update", "/tmp/arch-update.lock", "arch-update.service"]);
    assert.equal(U.lockProbeArgv().at(-1), "/tmp/arch-update.lock");
});

test("parseRefresh reads nothing as nothing", () => {
    assert.deepEqual(U.parseRefresh(""), { busy: false, via: "", fetchFailed: false });
});
