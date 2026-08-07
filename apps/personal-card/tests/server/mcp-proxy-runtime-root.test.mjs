import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { access, chmod, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const proxyPath = join(projectRoot, "whoami-mcp-proxy.mjs");

function proxyArgs(runtimeRoot, persomeRoot) {
  return [
    proxyPath,
    "--agent",
    "codex",
    "--model",
    "local-test-owner",
    "--connector-session",
    "cs_12345678",
    "--grant",
    "grant_local_1234",
    "--runtime-root",
    runtimeRoot,
    "--persome-root",
    persomeRoot,
  ];
}

async function executable(path, source) {
  await writeFile(path, source, { mode: 0o700 });
  await chmod(path, 0o700);
}

test("MCP proxy uses only the model-bound Persome root", async () => {
  const root = await mkdtemp(join(tmpdir(), "whoami-proxy-root-"));
  const trustedRoot = join(root, "trusted");
  const runtimeRoot = join(root, "card");
  const attacker = join(root, "attacker");
  const attackerMarker = join(root, "attacker-ran");
  await mkdir(join(trustedRoot, "venv/bin"), { recursive: true });
  await executable(
    join(trustedRoot, "venv/bin/persome"),
    "#!/bin/sh\n/bin/cat\n",
  );
  await executable(
    attacker,
    `#!/bin/sh\n/usr/bin/touch '${attackerMarker}'\n/bin/cat\n`,
  );

  const child = spawn(process.execPath, proxyArgs(runtimeRoot, trustedRoot), {
    env: { ...process.env, PERSOME_CLI: attacker },
    stdio: ["pipe", "pipe", "pipe"],
  });
  const output = once(child.stdout, "data");
  const exited = once(child, "exit");
  const message = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {},
  });
  child.stdin.end(`${message}\n`);
  assert.equal(String((await output)[0]).trim(), message);
  assert.equal((await exited)[0], 0);
  await assert.rejects(access(attackerMarker));
});

test("MCP proxy fails closed when the bound Persome root is missing", async () => {
  const root = await mkdtemp(join(tmpdir(), "whoami-proxy-missing-"));
  const attacker = join(root, "attacker");
  const attackerMarker = join(root, "attacker-ran");
  await executable(
    attacker,
    `#!/bin/sh\n/usr/bin/touch '${attackerMarker}'\n/bin/cat\n`,
  );
  const child = spawn(
    process.execPath,
    proxyArgs(join(root, "card"), join(root, "missing")),
    {
      env: { ...process.env, PERSOME_CLI: attacker },
      stdio: ["pipe", "ignore", "pipe"],
    },
  );
  const exited = once(child, "exit");
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });
  assert.equal((await exited)[0], 1);
  assert.match(stderr, /Persome is not installed/);
  await assert.rejects(access(attackerMarker));
});
