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

    // The same trick for walker, which `pshell launcher` and `pshell
    // clipboard` exec rather than call over IPC. A fake is the only way to
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

// ------------------------------------------------- the two that run walker

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

test("clipboard opens walker on the clipboard provider", () => {
    const box = sandbox();
    const out = run(box, ["clipboard"]);

    assert.equal(out.status, 0);
    assert.deepEqual(walkerCalls(box), [["--provider", "clipboard"]]);
    assert.deepEqual(calls(box), []);
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

test("clipboard gets the same guard, not just launcher", () => {
    const box = sandbox();
    const out = run(box, ["clipboard"], { PATH: `${box.noWalker}:${box.bare}` });

    assert.equal(out.status, 1);
    assert.match(out.stderr, /walker is not on your PATH/);
    assert.deepEqual(calls(box), []);
});

test("neither takes arguments, so a typo cannot reach walker's own flags", () => {
    for (const cmd of ["launcher", "clipboard"]) {
        const box = sandbox();
        const out = run(box, [cmd, "--dmenu"]);

        assert.equal(out.status, 1, `${cmd} accepted an argument`);
        assert.match(out.stderr, /takes no arguments/);
        assert.deepEqual(walkerCalls(box), []);
        assert.deepEqual(calls(box), []);
    }
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
