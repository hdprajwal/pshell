import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, copyFileSync, chmodSync, lstatSync, readlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// The real install.sh, run against fake package tools in a fake home.
//
// Every program the script hands work to is a stub that records what it was
// asked and does nothing: pacman answers -T and -Si from INSTALLED and REPO,
// and sudo, yay, go, elephant and systemctl only write to the log. elephant
// matters most -- this machine has the real one, and the setup would run it
// against the fake home if the stub were not first on PATH.
function sandbox() {
    const root = mkdtempSync(join(tmpdir(), "pshell-install-"));
    const stub = join(root, "stub");
    const home = join(root, "home");
    const log = join(root, "calls.log");
    mkdirSync(stub, { recursive: true });
    mkdirSync(home, { recursive: true });

    const recorder = name => `#!/bin/sh
{
    printf '${name}'
    for a in "$@"; do printf '\\t%s' "$a"; done
    printf '\\n'
} >> "${log}"
`;

    writeFileSync(join(stub, "pacman"), `#!/bin/sh
has() { for w in $2; do [ "$w" = "$1" ] && return 0; done; return 1; }
case "$1" in
    -T) has "$2" "\${INSTALLED:-}" ;;
    -Si) has "$2" "\${REPO:-}" ;;
    *) exit 1 ;;
esac
`);
    writeFileSync(join(stub, "sudo"), recorder("sudo"));
    writeFileSync(join(stub, "yay"), recorder("yay"));
    writeFileSync(join(stub, "elephant"), recorder("elephant"));
    writeFileSync(join(stub, "systemctl"), recorder("systemctl") + "exit 1\n");
    writeFileSync(join(stub, "pgrep"), "#!/bin/sh\nexit 1\n");
    // `go env GOVERSION` answers from GO_VERSION; a build records the
    // directory it ran in, since building from the checkout is the point.
    writeFileSync(join(stub, "go"), `#!/bin/sh
if [ "$1" = env ]; then printf '%s\\n' "\${GO_VERSION:-go1.27.1}"; exit 0; fi
${recorder("go").split("\n").slice(1).join("\n")}
printf 'cwd\\t%s\\n' "$(pwd)" >> "${log}"
`);
    for (const f of ["pacman", "sudo", "yay", "elephant", "systemctl", "pgrep", "go"])
        chmodSync(join(stub, f), 0o755);

    // A checkout is whatever has a shell.qml beside the script, so a copy of
    // install.sh with the files setup reads is enough.
    const checkout = join(root, "checkout");
    mkdirSync(join(checkout, "bin"), { recursive: true });
    writeFileSync(join(checkout, "shell.qml"), "// fake\n");
    writeFileSync(join(checkout, "bin", "pshell"), "#!/bin/sh\n");
    copyFileSync(join(repo, "config.example.json"), join(checkout, "config.example.json"));
    copyFileSync(join(repo, "install.sh"), join(checkout, "install.sh"));
    chmodSync(join(checkout, "install.sh"), 0o755);

    return { root, stub, home, log, checkout };
}

function run(box, args, env = {}) {
    return spawnSync(join(box.checkout, "install.sh"), args, {
        encoding: "utf8",
        env: {
            PATH: `${box.stub}:/usr/bin:/bin`,
            HOME: box.home,
            INSTALLED: "",
            REPO: "",
            ...env,
        },
    });
}

function calls(box, name) {
    if (!existsSync(box.log))
        return [];
    return readFileSync(box.log, "utf8")
        .split("\n")
        .filter(l => l.split("\t")[0] === name)
        .map(l => l.split("\t").slice(1));
}

test("--core installs only quickshell and git, from the repos", () => {
    const box = sandbox();
    const r = run(box, ["--core", "--skip-setup"], { REPO: "quickshell git" });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(calls(box, "sudo"), [["pacman", "-S", "--needed", "quickshell", "git"]]);
    assert.deepEqual(calls(box, "yay"), []);
});

test("anything already installed is skipped", () => {
    const box = sandbox();
    const r = run(box, ["--core", "--skip-setup"], { INSTALLED: "quickshell git" });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /everything is already installed/);
    assert.deepEqual(calls(box, "sudo"), []);
});

test("alternatives: one installed counts, otherwise the first the repos carry, otherwise the AUR", () => {
    const box = sandbox();
    const r = run(box, ["--skip-setup"], {
        // matugen-bin stands in for matugen; libvips is not packaged but
        // imagemagick is; walker and cachy-update/arch-update are nowhere.
        INSTALLED: "matugen-bin",
        REPO: "quickshell git imagemagick",
    });
    assert.equal(r.status, 0, r.stderr);

    const repoArgs = calls(box, "sudo")[0];
    assert.ok(repoArgs.includes("imagemagick"));
    assert.ok(!repoArgs.includes("libvips"));
    assert.ok(!repoArgs.includes("matugen") && !repoArgs.includes("matugen-bin"));

    const aurArgs = calls(box, "yay")[0];
    assert.equal(aurArgs[0], "-S");
    assert.ok(aurArgs.includes("walker"));
    assert.ok(aurArgs.includes("cachy-update"));
    assert.ok(!aurArgs.includes("imagemagick"));
});

test("--no-aur reports what is missing and never calls the helper", () => {
    const box = sandbox();
    const r = run(box, ["--skip-setup", "--no-aur"], { REPO: "quickshell git" });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(calls(box, "yay"), []);
    assert.match(r.stderr, /not installed:.*walker/);
});

test("--yes passes --noconfirm to pacman and the AUR helper", () => {
    const box = sandbox();
    const r = run(box, ["--skip-setup", "--yes"], { REPO: "quickshell git" });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(calls(box, "sudo")[0].includes("--noconfirm"));
    assert.ok(calls(box, "yay")[0].includes("--noconfirm"));
});

test("power-profiles-daemon is left out when TLP is installed", () => {
    const box = sandbox();
    const r = run(box, ["--skip-setup"], { INSTALLED: "tlp", REPO: "quickshell git power-profiles-daemon" });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(!calls(box, "sudo")[0].includes("power-profiles-daemon"));
});

test("--dry-run changes nothing", () => {
    const box = sandbox();
    const r = run(box, ["--dry-run"], { REPO: "quickshell git" });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(calls(box, "sudo"), []);
    assert.deepEqual(calls(box, "yay"), []);
    assert.deepEqual(calls(box, "go"), []);
    assert.ok(!existsSync(join(box.home, ".config", "pshell")));
    assert.ok(!existsSync(join(box.home, ".local", "bin")));
});

test("setup writes config.json, links the command and builds the helper from the checkout", () => {
    const box = sandbox();
    const r = run(box, ["--skip-packages"]);
    assert.equal(r.status, 0, r.stderr);

    const config = join(box.home, ".config", "pshell", "config.json");
    assert.equal(readFileSync(config, "utf8"), readFileSync(join(box.checkout, "config.example.json"), "utf8"));

    const link = join(box.home, ".local", "bin", "pshell");
    assert.ok(lstatSync(link).isSymbolicLink());
    assert.equal(readlinkSync(link), join(box.checkout, "bin", "pshell"));

    assert.deepEqual(calls(box, "go")[0], ["build", "-o", join(box.home, ".local", "bin", "pshell-agents"), "./cmd/pshell-agents"]);
    assert.deepEqual(calls(box, "cwd")[0], [box.checkout]);
});

test("setup never overwrites config.json or a real file where the link goes", () => {
    const box = sandbox();
    mkdirSync(join(box.home, ".config", "pshell"), { recursive: true });
    mkdirSync(join(box.home, ".local", "bin"), { recursive: true });
    writeFileSync(join(box.home, ".config", "pshell", "config.json"), "{\"mine\": true}\n");
    writeFileSync(join(box.home, ".local", "bin", "pshell"), "#!/bin/sh\n# mine\n");

    const r = run(box, ["--skip-packages"]);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(readFileSync(join(box.home, ".config", "pshell", "config.json"), "utf8"), "{\"mine\": true}\n");
    assert.match(readFileSync(join(box.home, ".local", "bin", "pshell"), "utf8"), /# mine/);
    assert.match(r.stderr, /not a symlink; leaving it alone/);
});

test("a Go older than 1.24 skips the helper instead of failing", () => {
    const box = sandbox();
    const r = run(box, ["--skip-packages"], { GO_VERSION: "go1.22.5" });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(calls(box, "go"), []);
    assert.match(r.stdout, /needs Go 1\.24 or newer/);
});

test("a Hyprland config that already starts pshell is not told to again", () => {
    const box = sandbox();
    mkdirSync(join(box.home, ".config", "hypr"), { recursive: true });
    writeFileSync(join(box.home, ".config", "hypr", "hyprland.lua"), "hl.exec_cmd(\"/home/me/.local/bin/pshell run\")\n");
    writeFileSync(join(box.home, ".config", "hypr", "hypridle.conf"), "lock_cmd = pshell lock\n");

    const r = run(box, ["--skip-packages"]);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /already starts pshell/);
    assert.doesNotMatch(r.stdout, /exec-once/);
});

test("without a Hyprland line, it prints one for this checkout", () => {
    const box = sandbox();
    mkdirSync(join(box.home, ".config", "hypr"), { recursive: true });
    writeFileSync(join(box.home, ".config", "hypr", "hypridle.conf"), "lock_cmd = pshell lock\n");

    const r = run(box, ["--skip-packages"]);
    assert.equal(r.status, 0, r.stderr);
    assert.ok(r.stdout.includes(`exec-once = qs -p ${box.checkout}`));
});

test("an unknown option fails with usage", () => {
    const box = sandbox();
    const r = run(box, ["--frobnicate"]);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /unknown option/);
});
