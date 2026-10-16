import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./load-qml-js.mjs";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const Proc = loadQmlJs("Services/Proc.js");

// Quickshell never emits `exited` for a Process whose binary cannot be
// started; it only reports that it is not running. Anything that waits on
// `exited` -- a queue's busy flag, a restart counter, a "lost" warning --
// waits for ever. Proc.supervised exists partly so setpriv being absent is
// not that: sh always starts, and a missing program becomes an exit code.

function which(name) {
  const r = spawnSync("sh", ["-c", 'command -v "$1"', "sh", name], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

function run(argv, env) {
  return spawnSync(argv[0], argv.slice(1), { encoding: "utf8", env: env || process.env });
}

test("supervised runs the program when setpriv is installed", t => {
  if (which("setpriv") === "")
    t.skip("no setpriv on this machine");
  const r = run(Proc.supervised(["printf", "%s", "a b'c"]));
  assert.equal(r.status, 0);
  assert.equal(r.stdout, "a b'c");
});

test("supervised still runs the program without setpriv", () => {
  // A PATH with sh and basename and nothing else, so `command -v setpriv`
  // fails the way it does on a system without util-linux. basename because
  // it is a real binary in every sh, where printf is often a builtin.
  const dir = mkdtempSync(join(tmpdir(), "pshell-proc-"));
  try {
    for (const name of ["sh", "basename"]) {
      const real = which(name);
      assert.notEqual(real, "", name + " must be installed to run this test");
      symlinkSync(real, join(dir, name));
    }
    const argv = Proc.supervised(["basename", "/x/ok"]);
    const r = run([join(dir, "sh"), ...argv.slice(1)], { PATH: dir });
    assert.equal(r.status, 0);
    assert.equal(r.stdout, "ok\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("supervised turns a missing program into an exit, not a failure to start", () => {
  const r = run(Proc.supervised(["pshell-no-such-binary"]));
  assert.equal(r.error, undefined);
  assert.equal(r.status, 127);
});

function qmlFiles(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory())
      qmlFiles(p, out);
    else if (entry.name.endsWith(".qml"))
      out.push(p);
  }
  return out;
}

test("no Process starts setpriv directly", () => {
  // setpriv as argv[0] is a Process that never starts, and never exits,
  // wherever util-linux is missing. Proc.supervised is the way to use it.
  const offenders = [];
  for (const dir of ["Services", "Widgets", "Ui", "Commons"]) {
    for (const file of qmlFiles(join(repo, dir))) {
      const source = readFileSync(file, "utf8");
      if (/\[\s*"setpriv"/.test(source))
        offenders.push(relative(repo, file));
    }
  }
  assert.deepEqual(offenders, []);
});

test("Nm's queue recovers from an nmcli that never starts", () => {
  // Without a guard on `running`, `_busy` stays set and every lookup after
  // the first waits for an exit that never comes.
  const source = readFileSync(join(repo, "Services/Nm.qml"), "utf8");
  assert.match(source, /onRunningChanged:\s*\{\s*if \(!worker\.running && root\._busy\)\s*root\._finish\(/);
});
