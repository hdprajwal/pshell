import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// A QML JavaScript library reads plain top-level function declarations and
// nothing else -- no `export`, no `module.exports` -- so it cannot be an ES
// module and node cannot import it directly.
//
// The alternative was a second copy of each library for the tests, which is
// the one thing worse than no tests: the copy drifts and the tests start
// passing against code nobody ships. So node loads the real file instead,
// strips the `.pragma library` line (valid QML, a syntax error in
// JavaScript), and hands back every top-level function it declares.
// Discovering the names by regex rather than listing them means new functions
// need no change here.
export function loadQmlJs(relativePath) {
  const source = readFileSync(join(repo, relativePath), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/gm, "");

  const names = [...source.matchAll(/^function\s+([A-Za-z0-9_]+)\s*\(/gm)].map(m => m[1]);
  if (names.length === 0)
    throw new Error(`${relativePath} declared no top-level functions`);

  return new Function(`${source}\nreturn { ${names.join(", ")} };`)();
}

export function loadNmParse() {
  return loadQmlJs("Services/NmParse.js");
}

export function loadConfigPath() {
  return loadQmlJs("Services/ConfigPath.js");
}
