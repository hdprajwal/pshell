import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, copyFileSync, chmodSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const script = join(repo, "bin", "pshell");

// The real script, run against a fake qs.
//
// Nothing here starts a shell or touches a real checkout: pshell's whole job
// is deciding which qs command to run, so a qs that records its arguments
// and exits is enough to test all of it. Testing a copy of the logic would
// be worse than not testing it, which is the same reason load-qml-js.mjs
// loads the shipped file rather than a duplicate.
function sandbox() {
    const root = mkdtempSync(join(tmpdir(), "pshell-test-"));
    const bin = join(root, "stub");
    const log = join(root, "qs.log");

    mkdirSync(bin, { recursive: true });

    // `list --all` answers from QS_LIST so the display-recovery path can be
    // driven; everything else records what it was called with, including the
    // display it inherited, and then obeys QS_STDOUT / QS_EXIT.
    writeFileSync(join(bin, "qs"), `#!/bin/sh
if [ "\${1:-}" = "list" ]; then
    printf '%s' "\${QS_LIST:-}"
    exit 0
fi
{
    printf 'ARGV'
    for a in "\$@"; do printf '\\t%s' "\$a"; done
    printf '\\n'
    printf 'DISPLAY=%s\\n' "\${WAYLAND_DISPLAY:-}"
} >> "${log}"
printf '%s' "\${QS_STDOUT:-}"
exit "\${QS_EXIT:-0}"
`);
    chmodSync(join(bin, "qs"), 0o755);

    // The same trick for walker, which `pshell launcher` execs rather than
    // calling over IPC. A fake is the only way to
    // see what they run: the real walker wants a Wayland display and an
    // elephant socket, and is not installed here anyway.
    const walkerLog = join(root, "walker.log");
    writeFileSync(join(bin, "walker"), `#!/bin/sh
{
    printf 'ARGV'
    for a in "\$@"; do printf '\\t%s' "\$a"; done
    printf '\\n'
} >> "${walkerLog}"
exit "\${WALKER_EXIT:-0}"
`);
    chmodSync(join(bin, "walker"), 0o755);

    // A PATH with everything the script itself needs and no qs. Emptying
    // PATH instead would take readlink and dirname with it, and the script
    // would die at 127 long before it looked for quickshell -- proving
    // nothing about the message it prints when quickshell is the thing
    // missing.
    const bare = join(root, "bare");
    mkdirSync(bare, { recursive: true });
    for (const tool of ["readlink", "dirname", "cat"]) {
        for (const dir of ["/usr/bin", "/bin"]) {
            if (existsSync(join(dir, tool))) {
                symlinkSync(join(dir, tool), join(bare, tool));
                break;
            }
        }
    }

    // And one with qs but no walker, for the other guard. Assembled by hand
    // rather than by handing over the real PATH minus nothing: walker is not
    // installed on this machine today, so the real PATH would pass this test
    // by accident and stop passing it the day someone installs walker.
    const noWalker = join(root, "nowalker");
    mkdirSync(noWalker, { recursive: true });
    symlinkSync(join(bin, "qs"), join(noWalker, "qs"));

    return { root, bin, bare, noWalker, log, walkerLog };
}

// A directory that looks like a checkout, because that is all the script
// checks for: a shell.qml sitting in it.
function checkout(root, name) {
    const dir = join(root, name);
    mkdirSync(join(dir, "bin"), { recursive: true });
    writeFileSync(join(dir, "shell.qml"), "// fake\n");
    return dir;
}

function run(box, args, env = {}, entry = script) {
    const result = spawnSync(entry, args, {
        encoding: "utf8",
        env: {
            PATH: `${box.bin}:/usr/bin:/bin`,
            HOME: box.root,
            // Set unless a test overrides it, so the display-recovery path
            // is opt-in rather than firing in every unrelated case.
            WAYLAND_DISPLAY: "wayland-0",
            ...env,
        },
    });
    return result;
}

function argvIn(path) {
    if (!existsSync(path))
        return [];
    // `ARGV` with no tab after it is an invocation with no arguments, which
    // is exactly what `pshell launcher` is now -- so the line has to be kept
    // and turned into [], not filtered out as noise. Getting this wrong makes
    // "walker ran bare" indistinguishable from "walker never ran".
    return readFileSync(path, "utf8")
        .split("\n")
        .filter(line => /^ARGV(\t|$)/.test(line))
        .map(line => line.split("\t").slice(1));
}

// Every qs invocation the run produced, as arrays of arguments.
function calls(box) {
    return argvIn(box.log);
}

// The same for walker. Two logs rather than one, because most of what these
// tests want to know is which of the two a command reached -- and "it also
// fired an ipc call" is invisible in a merged log.
function walkerCalls(box) {
    return argvIn(box.walkerLog);
}

function displays(box) {
    if (!existsSync(box.log))
        return [];
    return readFileSync(box.log, "utf8")
        .split("\n")
        .filter(line => line.startsWith("DISPLAY="))
        .map(line => line.slice("DISPLAY=".length));
}

// ------------------------------------------------------------ what it runs

test("lock with no method locks", () => {
    const box = sandbox();
    const out = run(box, ["lock"]);

    assert.equal(out.status, 0);
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.lock", "lock"]]);
});

test("lock with a method calls that method instead", () => {
    const box = sandbox();
    run(box, ["lock", "isLocked"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.lock", "isLocked"]]);
});

test("unlock is its own command, not a method to remember", () => {
    const box = sandbox();
    run(box, ["unlock"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.lock", "unlock"]]);
});

test("preview reaches the lock target", () => {
    const box = sandbox();
    run(box, ["preview"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.lock", "preview"]]);
});

test("any other word is a target name", () => {
    const box = sandbox();
    run(box, ["calendar", "toggle"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.calendar", "toggle"]]);
});

test("a target method keeps its own arguments", () => {
    const box = sandbox();
    run(box, ["settings", "open", "about"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.settings", "open", "about"]]);
});

test("ipc passes straight through", () => {
    const box = sandbox();
    run(box, ["ipc", "show"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "show"]]);
});

test("run starts the shell and forwards qs options", () => {
    const box = sandbox();
    run(box, ["run", "-d"]);

    assert.deepEqual(calls(box), [["-p", repo, "-d"]]);
});

// --------------------------------------- the launcher, and the clipboard

test("launcher runs walker bare, naming no provider of its own", () => {
    const box = sandbox();
    const out = run(box, ["launcher"]);

    assert.equal(out.status, 0);
    // No arguments at all, and that is the assertion. Naming a provider here
    // would override `providers.default` in the user's own walker config --
    // not pshell's file to argue with -- and walker skips its whole prefix
    // table whenever a provider is set exclusively, so a `desktopapplications`
    // creeping back in would silently kill `=`, `.`, `@` and seven more
    // inside the one bind this command exists to serve.
    assert.deepEqual(walkerCalls(box), [[]]);
    // The point of the assertion. A `launcher` case that fell through to the
    // `*)` dispatch, or one written as a call() with an exec bolted after it,
    // would still open walker and would also ask the shell for a
    // `pshell.launcher` target that does not exist -- printing an error, or
    // worse, silently succeeding against some future target of that name.
    assert.deepEqual(calls(box), []);
});

// The clipboard history is pshell's own now, so the command that used to
// open walker's clipboard provider talks to the shell like every other one.
// Bare, it toggles -- the keybind that opens the panel also closes it.
test("clipboard toggles pshell's own panel rather than opening walker", () => {
    const box = sandbox();
    const out = run(box, ["clipboard"]);

    assert.equal(out.status, 0);
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.clipboard", "toggle"]]);
    assert.deepEqual(walkerCalls(box), []);
});

test("clipboard with a method calls that method instead", () => {
    const box = sandbox();
    run(box, ["clipboard", "history", "10"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.clipboard", "history", "10"]]);
    assert.deepEqual(walkerCalls(box), []);
});

// Pins take the number history prints, the same index the panel's rows
// carry, so the CLI passes it through untouched.
test("clipboard pin, unpin and pinned reach the shell with their index", () => {
    const box = sandbox();
    run(box, ["clipboard", "pin", "3"]);
    run(box, ["clipboard", "unpin", "0"]);
    run(box, ["clipboard", "pinned"]);

    assert.deepEqual(calls(box), [
        ["-p", repo, "ipc", "call", "pshell.clipboard", "pin", "3"],
        ["-p", repo, "ipc", "call", "pshell.clipboard", "unpin", "0"],
        ["-p", repo, "ipc", "call", "pshell.clipboard", "pinned"],
    ]);
});

// history marks pins inside the preview column, so the script has nothing
// to do but pass the lines through -- two tab-separated fields each, which
// is what `cut -f1` after fzf relies on.
test("clipboard history passes pinned lines through, marker and all", () => {
    const box = sandbox();
    const lines = "0\t[pin] ssh key\n1\tlatest copy";
    const out = run(box, ["clipboard", "history", "20"], { QS_STDOUT: lines });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, lines + "\n");
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.clipboard", "history", "20"]]);
});

test("both are documented, unlike the targets", () => {
    const box = sandbox();
    const out = run(box, ["help"]);

    assert.match(out.stdout, /^\s+launcher\s+/m);
    assert.match(out.stdout, /^\s+clipboard\s+/m);
});

test("a missing walker says what to install rather than failing at exec", () => {
    const box = sandbox();
    const out = run(box, ["launcher"], { PATH: `${box.noWalker}:${box.bare}` });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /walker is not on your PATH/);
    assert.match(out.stderr, /pacman -S walker/);
    assert.match(out.stderr, /elephant/);
    assert.doesNotMatch(out.stderr, /not found/);
    // qs is on this PATH and untouched: a launcher that cannot run must not
    // quietly become an ipc call to a target named launcher.
    assert.deepEqual(calls(box), []);
});

// The guard that used to cover both now covers only the launcher: a machine
// without walker still has a clipboard history.
test("clipboard needs no walker any more", () => {
    const box = sandbox();
    const out = run(box, ["clipboard"], { PATH: `${box.noWalker}:${box.bare}` });

    assert.equal(out.status, 0);
    assert.doesNotMatch(out.stderr, /walker/);
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.clipboard", "toggle"]]);
});

test("launcher takes no arguments, so a typo cannot reach walker's own flags", () => {
    const box = sandbox();
    const out = run(box, ["launcher", "--dmenu"]);

    assert.equal(out.status, 1);
    assert.match(out.stderr, /takes no arguments/);
    assert.deepEqual(walkerCalls(box), []);
    assert.deepEqual(calls(box), []);
});

// Adding two named commands to the case block is exactly how the catch-all
// underneath them stops being reached, and the failure is quiet: a target
// would just stop working.
test("adding them left the target dispatch alone", () => {
    const box = sandbox();
    run(box, ["calendar", "toggle"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.calendar", "toggle"]]);
    assert.deepEqual(walkerCalls(box), []);
});

// ------------------------------------------------------------ nightlight

// Bare, it toggles, for the clipboard's reason: the keybind that turns it on
// also turns it off.
test("nightlight toggles", () => {
    const box = sandbox();
    const out = run(box, ["nightlight"], { QS_STDOUT: "on 4000K" });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, "on 4000K\n");
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.nightlight", "toggle"]]);
});

test("nightlight with a method calls that method instead", () => {
    const box = sandbox();
    run(box, ["nightlight", "setTemperature", "3500"]);

    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.nightlight", "setTemperature", "3500"]]);
});

test("nightlight is documented, and says what it needs", () => {
    const box = sandbox();
    const out = run(box, ["help"]);

    assert.match(out.stdout, /^\s+nightlight\s+.*hyprsunset/m);
});

// The shell has no way to fail an IPC call -- qs exits 0 whatever the method
// returns -- so a target that cannot do what it was asked says `error: ...`
// and the script turns that into an exit code. Without it, a machine with no
// hyprsunset would answer `pshell nightlight on` with success.
test("an error: answer fails the command and goes to stderr", () => {
    const box = sandbox();
    const out = run(box, ["nightlight", "on"], {
        QS_STDOUT: "error: hyprsunset is not installed, so there is no nightlight. Install it with: sudo pacman -S hyprsunset",
    });

    assert.equal(out.status, 1);
    assert.equal(out.stdout, "");
    assert.match(out.stderr, /^pshell: hyprsunset is not installed/);
    assert.match(out.stderr, /sudo pacman -S hyprsunset/);
});

// Opt-in, not universal: only targets that promise to answer `error: ...`
// get the rule. Notification history prints `app: summary` lines, so after
// `notify-send -a error hi` its output starts `error: ` and is still output.
test("notification history from an app named error is output, not a failure", () => {
    const box = sandbox();
    const history = "error: hi\nfirefox: Download finished — report.pdf";
    const out = run(box, ["notifications", "history"], { QS_STDOUT: history });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, history + "\n");
    assert.equal(out.stderr, "");
});

test("the error: rule is the opted-in targets', not every target's", () => {
    const box = sandbox();
    const out = run(box, ["clipboard", "history"], { QS_STDOUT: "error: nope" });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, "error: nope\n");
});

// Only a leading `error: ` counts. A clipboard entry that happens to contain
// the word, numbered and tabbed as history prints it, is output.
test("an answer that only mentions an error is still output", () => {
    const box = sandbox();
    const out = run(box, ["clipboard", "history"], { QS_STDOUT: "0\terror: something I copied" });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, "0\terror: something I copied\n");
});

// With no reading yet, `weather hourly` has nothing to print, and printing
// nothing with a 0 would read as a day with no hours in it.
test("weather hourly with nothing to show fails the command", () => {
    const box = sandbox();
    const out = run(box, ["weather", "hourly"], { QS_STDOUT: "error: no hourly forecast yet" });

    assert.equal(out.status, 1);
    assert.equal(out.stdout, "");
    assert.equal(out.stderr, "pshell: no hourly forecast yet\n");
});

test("weather hourly lines are output", () => {
    const box = sandbox();
    const lines = "21:00  24°C  40%  Light rain\n22:00  23°C  10%  Overcast";
    const out = run(box, ["weather", "hourly"], { QS_STDOUT: lines });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, lines + "\n");
});

// --------------------------------------------------------------- updates

// Bare, it reports rather than acts: the action is a sudo pacman in a
// terminal, and that is asked for by name.
test("updates on its own asks for the status", () => {
    const box = sandbox();
    const out = run(box, ["updates"], { QS_STDOUT: "4 updates (3 repo, 1 AUR), checked just now, by cachy-update" });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, "4 updates (3 repo, 1 AUR), checked just now, by cachy-update\n");
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.updates", "status"]]);
});

test("updates with a method calls that method instead", () => {
    const box = sandbox();
    for (const method of ["refresh", "open", "count", "list"])
        run(box, ["updates", method]);

    assert.deepEqual(calls(box), ["refresh", "open", "count", "list"].map(m => ["-p", repo, "ipc", "call", "pshell.updates", m]));
});

test("updates is documented, and says what it needs", () => {
    const box = sandbox();
    const out = run(box, ["help"]);

    assert.match(out.stdout, /^\s+updates\s+.*cachy-update/m);
});

// The second target to promise `error: ` answers, so the second one the
// rule is opted in for.
test("an error: answer from updates fails the command", () => {
    const box = sandbox();
    const out = run(box, ["updates", "open"], {
        QS_STDOUT: "error: neither cachy-update nor arch-update is installed. On CachyOS: sudo pacman -S cachy-update; on Arch: sudo pacman -S arch-update",
    });

    assert.equal(out.status, 1);
    assert.equal(out.stdout, "");
    assert.match(out.stderr, /^pshell: neither cachy-update nor arch-update is installed/);
});

test("the update list is output, tabs and all", () => {
    const box = sandbox();
    const list = "repo\tbash 5.3.15-2 -> 5.3.20-2\naur\t1password 8.12.22-17 -> 8.12.40-31";
    const out = run(box, ["updates", "list"], { QS_STDOUT: list });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, list + "\n");
});

// ----------------------------------------------------------- volume tone

test("audio tone with an action passes the action through", () => {
    const box = sandbox();
    for (const action of ["on", "off", "toggle", "test", "status"])
        run(box, ["audio", "tone", action]);

    assert.deepEqual(calls(box), ["on", "off", "toggle", "test", "status"].map(a => ["-p", repo, "ipc", "call", "pshell.audio", "tone", a]));
});

// The method takes its action as an argument, so bare would be a call qs
// refuses; it asks for the status instead.
test("audio tone on its own asks for the status", () => {
    const box = sandbox();
    const out = run(box, ["audio", "tone"], { QS_STDOUT: "on, after 180ms, with pw-play, /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" });

    assert.equal(out.status, 0);
    assert.match(out.stdout, /^on, after 180ms/);
    assert.deepEqual(calls(box), [["-p", repo, "ipc", "call", "pshell.audio", "tone", "status"]]);
});

test("the rest of the audio target is untouched", () => {
    const box = sandbox();
    run(box, ["audio", "setVolume", "40"]);
    run(box, ["audio", "status"]);

    assert.deepEqual(calls(box), [
        ["-p", repo, "ipc", "call", "pshell.audio", "setVolume", "40"],
        ["-p", repo, "ipc", "call", "pshell.audio", "status"],
    ]);
});

test("audio with no method is refused before qs is bothered", () => {
    const box = sandbox();
    const out = run(box, ["audio"]);

    assert.equal(out.status, 1);
    assert.match(out.stderr, /audio needs a method/);
    assert.deepEqual(calls(box), []);
});

test("audio tone is documented", () => {
    const box = sandbox();
    const out = run(box, ["help"]);

    assert.match(out.stdout, /^\s+audio tone \[on\|off\|toggle\|test\]/m);
});

// `pshell audio tone test` with nothing to play with has to fail, so a
// script checking for a player can.
test("an error: answer from audio fails the command", () => {
    const box = sandbox();
    const out = run(box, ["audio", "tone", "test"], {
        QS_STDOUT: "error: no pw-play, paplay or canberra-gtk-play on PATH. pw-play comes with pipewire.",
    });

    assert.equal(out.status, 1);
    assert.equal(out.stdout, "");
    assert.match(out.stderr, /^pshell: no pw-play, paplay or canberra-gtk-play on PATH/);
});

test("the audio status line is output", () => {
    const box = sandbox();
    const line = 'volume 35% sink "Built-in Audio" mic 50% source "Built-in Audio"';
    const out = run(box, ["audio", "status"], { QS_STDOUT: line });

    assert.equal(out.status, 0);
    assert.equal(out.stdout, line + "\n");
});

// ------------------------------------------------------- what it refuses

test("a target with no method is refused before qs is bothered", () => {
    const box = sandbox();
    const out = run(box, ["calendar"]);

    assert.equal(out.status, 1);
    assert.match(out.stderr, /needs a method/);
    assert.deepEqual(calls(box), []);
});

test("unlock rejects arguments rather than ignoring them", () => {
    const box = sandbox();
    const out = run(box, ["unlock", "now"]);

    assert.equal(out.status, 1);
    assert.match(out.stderr, /takes no arguments/);
    assert.deepEqual(calls(box), []);
});

test("preview rejects arguments too", () => {
    const box = sandbox();
    const out = run(box, ["preview", "--fullscreen"]);

    assert.equal(out.status, 1);
    assert.deepEqual(calls(box), []);
});

test("help needs neither qs nor a running shell", () => {
    const box = sandbox();
    const out = run(box, ["help"], { PATH: "/usr/bin:/bin" });

    assert.equal(out.status, 0);
    assert.match(out.stdout, /usage: pshell/);
});

test("no arguments prints usage and succeeds", () => {
    const box = sandbox();
    const out = run(box, []);

    assert.equal(out.status, 0);
    assert.match(out.stdout, /usage: pshell/);
    assert.deepEqual(calls(box), []);
});

// Usage used to carry a hardcoded target list while the code comment beside
// it explained that such a copy would go stale. It pointed at the shell
// instead; this keeps it that way.
test("usage does not carry its own copy of the target list", () => {
    const box = sandbox();
    const out = run(box, ["help"]);

    assert.match(out.stdout, /pshell ipc show/);
    assert.doesNotMatch(out.stdout, /aiusage/);
});

test("a missing qs is reported as a missing qs", () => {
    const box = sandbox();
    const out = run(box, ["lock"], { PATH: box.bare });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /qs is not on your PATH/);
});

// ----------------------------------------------------- which shell it finds

test("the checkout the script sits in wins over PSHELL_DIR", () => {
    const box = sandbox();
    const mine = checkout(box.root, "mine");
    const other = checkout(box.root, "other");
    const entry = join(mine, "bin", "pshell");
    copyFileSync(script, entry);
    chmodSync(entry, 0o755);

    run(box, ["lock"], { PSHELL_DIR: other }, entry);

    // A worktree's own command must not be redirected by a variable someone
    // set once in a shell rc.
    assert.deepEqual(calls(box), [["-p", mine, "ipc", "call", "pshell.lock", "lock"]]);
});

test("a copy outside any checkout follows PSHELL_DIR", () => {
    const box = sandbox();
    const target = checkout(box.root, "target");
    const entry = join(box.root, "installed", "pshell");
    mkdirSync(dirname(entry), { recursive: true });
    copyFileSync(script, entry);
    chmodSync(entry, 0o755);

    run(box, ["lock"], { PSHELL_DIR: target }, entry);

    assert.deepEqual(calls(box), [["-p", target, "ipc", "call", "pshell.lock", "lock"]]);
});

test("with neither, it falls back to the documented install path", () => {
    const box = sandbox();
    const config = join(box.root, "cfg");
    const target = join(config, "quickshell", "pshell");
    mkdirSync(target, { recursive: true });
    writeFileSync(join(target, "shell.qml"), "// fake\n");

    const entry = join(box.root, "installed2", "pshell");
    mkdirSync(dirname(entry), { recursive: true });
    copyFileSync(script, entry);
    chmodSync(entry, 0o755);

    run(box, ["lock"], { XDG_CONFIG_HOME: config }, entry);

    assert.deepEqual(calls(box), [["-p", target, "ipc", "call", "pshell.lock", "lock"]]);
});

test("finding no checkout at all says what to set", () => {
    const box = sandbox();
    const entry = join(box.root, "lost", "pshell");
    mkdirSync(dirname(entry), { recursive: true });
    copyFileSync(script, entry);
    chmodSync(entry, 0o755);

    const out = run(box, ["lock"], { XDG_CONFIG_HOME: join(box.root, "empty") }, entry);

    assert.equal(out.status, 1);
    assert.match(out.stderr, /cannot find a pshell checkout/);
    assert.match(out.stderr, /PSHELL_DIR/);
});

// --------------------------------------------------------- what it explains

test("a shell that is not running is not a typo", () => {
    const box = sandbox();
    const out = run(box, ["lock"], { QS_EXIT: "1", QS_STDOUT: "No running instances on the current display" });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /the shell is not running/);
    assert.match(out.stderr, /pshell run/);
});

// qs exits 0 for an unknown target and prints "Target not found." to
// stdout, so trusting the exit code reported a mistyped command -- or one
// aimed at a shell whose branch lacks the target -- as a success.
test("an unknown target is an error even though qs exits zero", () => {
    const box = sandbox();
    const out = run(box, ["lock"], { QS_EXIT: "0", QS_STDOUT: "Target not found." });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /no 'pshell\.lock' target/);
    assert.match(out.stderr, /ipc show/);
    assert.doesNotMatch(out.stdout, /Target not found/);
});

test("an unknown target is an error when qs does exit non-zero too", () => {
    const box = sandbox();
    const out = run(box, ["calendar", "toggle"], { QS_EXIT: "1", QS_STDOUT: "Target not found." });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /no 'pshell\.calendar' target/);
});

test("a shell that is not running is caught whatever the exit code", () => {
    const box = sandbox();
    const out = run(box, ["lock"], { QS_EXIT: "0", QS_STDOUT: "No running instances" });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /the shell is not running/);
});

test("any other qs failure is passed through rather than reworded", () => {
    const box = sandbox();
    const out = run(box, ["lock"], { QS_EXIT: "1", QS_STDOUT: "something else went wrong" });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /something else went wrong/);
});

test("output from a successful call is printed", () => {
    const box = sandbox();
    const out = run(box, ["lock", "isLocked"], { QS_STDOUT: "true\n" });

    assert.equal(out.status, 0);
    assert.equal(out.stdout.trim(), "true");
});

// ------------------------------------------------------ reaching a TTY user

// The escape hatch. `qs ipc` will not look at an instance on a display it is
// not itself on, and a TTY -- the only place you can run this from when the
// lockscreen will not take your password -- has no WAYLAND_DISPLAY at all.
test("without a display, it recovers one from the instance list", () => {
    const box = sandbox();
    const list = [
        "Instance abc:",
        "  Process ID: 1",
        `  Config path: ${repo}/shell.qml`,
        "  Display connection: wayland/wayland-3",
        "",
    ].join("\n");

    const out = run(box, ["unlock"], { WAYLAND_DISPLAY: "", QS_LIST: list });

    assert.equal(out.status, 0);
    assert.deepEqual(displays(box), ["wayland-3"]);
});

test("it picks the display of its own checkout, not of another shell", () => {
    const box = sandbox();
    const list = [
        "Instance other:",
        "  Process ID: 1",
        "  Config path: /somewhere/else/shell.qml",
        "  Display connection: wayland/wayland-9",
        "Instance mine:",
        "  Process ID: 2",
        `  Config path: ${repo}/shell.qml`,
        "  Display connection: wayland/wayland-4",
        "",
    ].join("\n");

    run(box, ["unlock"], { WAYLAND_DISPLAY: "", QS_LIST: list });

    assert.deepEqual(displays(box), ["wayland-4"]);
});

test("a checkout path with a space in it still resolves", () => {
    const box = sandbox();
    const spaced = checkout(box.root, "has space");
    const entry = join(spaced, "bin", "pshell");
    copyFileSync(script, entry);
    chmodSync(entry, 0o755);

    const list = [
        "Instance abc:",
        `  Config path: ${spaced}/shell.qml`,
        "  Display connection: wayland/wayland-7",
        "",
    ].join("\n");

    run(box, ["unlock"], { WAYLAND_DISPLAY: "", QS_LIST: list }, entry);

    assert.deepEqual(displays(box), ["wayland-7"]);
});

test("an existing display is left alone", () => {
    const box = sandbox();
    // A list that would resolve to something else entirely, to prove it is
    // not consulted when the environment already knows.
    const list = [
        "Instance abc:",
        `  Config path: ${repo}/shell.qml`,
        "  Display connection: wayland/wayland-9",
        "",
    ].join("\n");

    run(box, ["unlock"], { WAYLAND_DISPLAY: "wayland-1", QS_LIST: list });

    assert.deepEqual(displays(box), ["wayland-1"]);
});

test("no instance in the list leaves the display unset rather than guessing", () => {
    const box = sandbox();
    const list = [
        "Instance other:",
        "  Config path: /somewhere/else/shell.qml",
        "  Display connection: wayland/wayland-9",
        "",
    ].join("\n");

    run(box, ["unlock"], { WAYLAND_DISPLAY: "", QS_LIST: list });

    assert.deepEqual(displays(box), [""]);
});
