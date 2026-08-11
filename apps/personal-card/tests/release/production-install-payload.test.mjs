import assert from "node:assert/strict";
import { lstat, readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));
const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));
const installerPath = path.join(productRoot, "install.sh");

const forbidden = [
  ["Ceci", "lia"].join(""),
  ["ceci", "lia"].join(""),
  ["@ceci", "lia"].join(""),
  ["lin", "-demo"].join(""),
  ["Lin", " · @lin"].join(""),
  ["z", "sy"].join(""),
  ["Personal Card 的", "上一版"].join(""),
  ["继续 ", "Personal Card"].join(""),
  ["Designing quieter ", "tools for cities"].join(""),
  ["Product person building ", "Who Am I"].join(""),
  ["Urban interaction ", "designer"].join(""),
  ["pm.app/", "cecilia"].join(""),
  ["pm.app/", "lin"].join(""),
];

const textExtensions = new Set([
  ".command",
  ".css",
  ".html",
  ".js",
  ".json",
  ".md",
  ".mjs",
  ".sh",
  ".toml",
  ".txt",
]);

async function walk(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".DS_Store") continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await walk(absolute));
    else if (entry.isFile()) files.push(absolute);
  }
  return files;
}

test("the currently installed Personal Card payload contains no demo identity or Card copy", async () => {
  const installer = await readFile(installerPath, "utf8");
  const payloadRoots = [
    ...new Set(
      [...installer.matchAll(/"\$\{source_root\}\/([^"\n]+)"/g)]
        .map((match) => match[1]),
    ),
  ];
  assert.ok(
    payloadRoots.length > 0,
    "Could not resolve the Personal Card payload from install.sh.",
  );

  const findings = [];
  const payloadFiles = [];
  for (const relativeRoot of payloadRoots) {
    const absoluteRoot = path.join(appRoot, relativeRoot);
    const stats = await lstat(absoluteRoot);
    if (stats.isDirectory()) payloadFiles.push(...await walk(absoluteRoot));
    else if (stats.isFile()) payloadFiles.push(absoluteRoot);
  }
  for (const absolute of [...new Set(payloadFiles)]) {
    const relative = path.relative(appRoot, absolute);
    for (const forbiddenArtifact of [
      ["fixtures/models/", "cecilia.json"].join(""),
      ["fixtures/models/", "lin.json"].join(""),
      ["tests/visual/current/runtime-", "cecilia-1440x1000.png"].join(""),
      ["tests/visual/current/runtime-", "lin-1440x1000.png"].join(""),
    ]) {
      if (relative === forbiddenArtifact) {
        findings.push(`${relative}: development fixture/artifact is installed`);
      }
    }
    if (!textExtensions.has(path.extname(absolute))) continue;
    const content = await readFile(absolute, "utf8");
    for (const token of forbidden) {
      if (content.includes(token)) findings.push(`${relative}: ${JSON.stringify(token)}`);
    }
  }

  assert.deepEqual(
    findings,
    [],
    [
      `Found ${findings.length} demo identity/content occurrence(s) in the current install payload.`,
      ...findings.slice(0, 40),
      findings.length > 40 ? `... ${findings.length - 40} more` : "",
    ].filter(Boolean).join("\n"),
  );
});

test("every statically imported server module is part of the shipped payload", async () => {
  const [server, installer, packager] = await Promise.all([
    readFile(path.join(appRoot, "persome-card-server.mjs"), "utf8"),
    readFile(installerPath, "utf8"),
    readFile(path.join(productRoot, "scripts/build-self-contained-package.sh"), "utf8"),
  ]);

  // A static top-level import has to resolve the moment the installed server
  // boots, so both the installer payload and the self-contained packager must
  // ship it -- either by copying its whole directory or by naming the file.
  // `await import(...)` behind the DEV_MODE guard is intentionally absent from
  // production and is therefore not collected here.
  const imported = new Set();
  for (const match of server.matchAll(/from\s+"\.\/(src\/[^"]+\.mjs)"/g)) {
    imported.add(match[1]);
  }
  for (const match of server.matchAll(/^\s*import\s+"\.\/(src\/[^"]+\.mjs)"/gm)) {
    imported.add(match[1]);
  }

  assert.ok(imported.size > 0, "found no static ./src imports to verify");

  const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // Match only inside a copy list, never any mention of the path. Both scripts
  // also `mkdir` staging paths that repeat a directory name, and accepting
  // those would hide exactly the kind of omission this test exists to catch.
  // The trailing boundary keeps `src/content` from matching `src/contracts`.
  const boundary = "(?![\\w./-])";
  const copies = {
    // /bin/cp -R "${source_root}/src/auth" ...
    installer: (script, target) =>
      new RegExp(`\\$\\{source_root\\}/${escape(target)}${boundary}`).test(script),
    // A bare, line-leading entry of a `for ... in \` copy list.
    packager: (script, target) =>
      new RegExp(`^\\s*apps/personal-card/${escape(target)}${boundary}`, "m").test(script),
  };
  const shipped = (script, kind, relative) => {
    const directory = relative.slice(0, relative.lastIndexOf("/"));
    return copies[kind](script, relative) || copies[kind](script, directory);
  };

  const missing = [];
  for (const relative of [...imported].sort()) {
    if (!shipped(installer, "installer", relative)) {
      missing.push(`install.sh does not ship ${relative}`);
    }
    if (!shipped(packager, "packager", relative)) {
      missing.push(`build-self-contained-package.sh does not ship ${relative}`);
    }
  }

  assert.deepEqual(
    missing,
    [],
    ["The installed server would fail to boot with ERR_MODULE_NOT_FOUND:", ...missing].join("\n"),
  );
});
