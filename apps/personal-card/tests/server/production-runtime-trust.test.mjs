import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const projectRoot = new URL("../../", import.meta.url);
const fakePersome = fileURLToPath(
  new URL("../fixtures/fake-persome-cli.mjs", import.meta.url),
);

async function waitForServer(baseUrl, child) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`Server exited with ${child.exitCode}`);
    try {
      const response = await fetch(baseUrl, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Startup is asynchronous.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("Timed out waiting for production trust server.");
}

test("production ignores PATH/override and unauthenticated loopback Runtime impostors", async (t) => {
  let attackerCalls = 0;
  const attacker = createServer((req, res) => {
    attackerCalls += 1;
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      result: {
        content: [{ type: "text", text: "{\"root\":\"ATTACKER_ONLY\"}" }],
      },
    }));
  });
  await new Promise((resolve) => attacker.listen(0, "127.0.0.1", resolve));
  t.after(() => attacker.close());
  const attackerPort = attacker.address().port;

  const root = await mkdtemp(join(tmpdir(), "whoami-runtime-trust-"));
  const port = 24000 + (process.pid % 2000);
  const baseUrl = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, ["persome-card-server.mjs"], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NODE_ENV: "production",
      WHOAMI_DEV_MODE: "0",
      WHOAMI_PROVIDER_MODE: "fixture",
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_CARD_DATA_DIR: join(root, "card"),
      PERSOME_ROOT: join(root, "persome"),
      PERSOME_CLI: fakePersome,
      PERSOME_MCP_URL: `http://127.0.0.1:${attackerPort}/mcp`,
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
  t.after(async () => {
    if (child.exitCode === null) child.kill("SIGTERM");
    if (child.exitCode === null) await once(child, "exit");
  });
  await waitForServer(baseUrl, child);

  let cookie = "";
  const request = async (path, options = {}) => {
    const headers = { ...(options.headers || {}) };
    if (cookie) headers.Cookie = cookie;
    const response = await fetch(`${baseUrl}${path}`, { ...options, headers });
    const setCookie = response.headers.get("set-cookie");
    if (setCookie) cookie = setCookie.split(";", 1)[0];
    return { status: response.status, body: await response.json() };
  };
  const saved = await request("/api/setup/profile", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      displayName: "Owner",
      handle: "@owner",
      tagline: "Owner Card",
      description: "Owner Identity",
    }),
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.ready, false);
  assert.equal(saved.body.state, "not_installed");
  assert.equal(saved.body.personalModel.installed, false);

  const blocked = await request("/api/model/bootstrap");
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.code, "RUNTIME_NOT_INSTALLED");
  assert.doesNotMatch(JSON.stringify(blocked.body), /ATTACKER_ONLY|Cecilia|@lin/);
  assert.equal(attackerCalls, 0);
});
