import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./load-qml-js.mjs";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const Model = loadQmlJs("Services/AgentUsage.js");

// ------------------------------------------------------------ arguments

test("the timer's run is a full one, with no flags", () => {
  assert.deepEqual(Model.updaterArgs("full"), []);
  assert.deepEqual(Model.updaterArgs(undefined), []);
});

test("opening the panel only refreshes the limits", () => {
  assert.deepEqual(Model.updaterArgs("open"), ["--limits-only"]);
});

test("a retry names only the providers that asked for one", () => {
  assert.deepEqual(Model.updaterArgs("retry", ["claude"]), ["--limits-only", "claude"]);
  assert.deepEqual(Model.updaterArgs("retry", ["claude", "", "codex"]), ["--limits-only", "claude", "codex"]);
});

test("a retry with nobody to retry is still limits-only, never a full run", () => {
  assert.deepEqual(Model.updaterArgs("retry", []), ["--limits-only"]);
  assert.deepEqual(Model.updaterArgs("retry"), ["--limits-only"]);
});

// ------------------------------------------------------------ throttle

test("the first panel open always refreshes", () => {
  assert.equal(Model.openRefreshDue(0, 1_000_000), true);
});

test("a panel reopened within a minute of the last run does not refresh", () => {
  const last = 1_000_000;
  assert.equal(Model.openRefreshDue(last, last + 5_000), false);
  assert.equal(Model.openRefreshDue(last, last + 59_999), false);
  assert.equal(Model.openRefreshDue(last, last + 60_000), true);
});

test("a clock that stepped backwards does not block refreshes", () => {
  assert.equal(Model.openRefreshDue(1_000_000, 900_000), true);
});

// --------------------------------------------------------------- retry

test("only records with retryAdvised set are retried, in a stable order", () => {
  const records = [
    { id: "fireworks" },
    { id: "codex", retryAdvised: true },
    { id: "claude", retryAdvised: true },
    { id: "other", retryAdvised: false },
    null,
  ];
  assert.deepEqual(Model.retryTargets(records), ["claude", "codex"]);
  assert.deepEqual(Model.retryTargets([]), []);
  assert.deepEqual(Model.retryTargets(undefined), []);
});

test("retries back off from half a minute to five", () => {
  assert.equal(Model.retryDelaySec(0, 900), 30);
  assert.equal(Model.retryDelaySec(1, 900), 60);
  assert.equal(Model.retryDelaySec(2, 900), 120);
  assert.equal(Model.retryDelaySec(3, 900), 240);
  assert.equal(Model.retryDelaySec(4, 900), 300);
  assert.equal(Model.retryDelaySec(1000, 900), 300);
});

test("a retry is never later than the regular run", () => {
  assert.equal(Model.retryDelaySec(5, 60), 60);
  assert.equal(Model.retryDelaySec(0, 20), 20);
});

// ------------------------------------------------------------- the shell

// The arguments only matter if the `sh -c` wrapper actually hands them on: a
// script that forgot "$@" would turn every panel open back into a full run
// and nothing would say so. This runs the wrapper exactly as AgentUsage.qml
// spells it, against a stand-in pshell-agents that prints what it was given.
function wrapperScript() {
  const source = readFileSync(join(repo, "Services/AgentUsage.qml"), "utf8");
  const match = source.match(/command: \["sh", "-c", ("command -v pshell-agents[^\n]*?"), "sh"\]\.concat\(Model\.updaterArgs\(/);
  assert.ok(match, "AgentUsage.qml no longer builds the updater command the way this test expects");
  return JSON.parse(match[1]);
}

test("the updater wrapper passes its arguments through to pshell-agents", () => {
  const dir = mkdtempSync(join(tmpdir(), "pshell-agents-"));
  try {
    const fake = join(dir, "pshell-agents");
    writeFileSync(fake, '#!/bin/sh\nprintf "%s\\n" "$@"\n');
    chmodSync(fake, 0o755);
    const env = { ...process.env, PATH: dir + ":" + process.env.PATH };
    const args = Model.updaterArgs("retry", ["claude"]);
    const r = spawnSync("sh", ["-c", wrapperScript(), "sh", ...args], { encoding: "utf8", env });
    assert.equal(r.status, 0);
    assert.equal(r.stdout, "--limits-only\nclaude\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the panel asks for a panel refresh, not the timer's full run", () => {
  const source = readFileSync(join(repo, "Widgets/AiUsage/AiUsage.qml"), "utf8");
  assert.match(source, /AgentUsage\.refreshForPanel\(\)/);
  assert.doesNotMatch(source, /AgentUsage\.refresh\(\)/);
});
