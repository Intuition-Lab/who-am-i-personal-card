import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { chmod, mkdir, mkdtemp, writeFile } from "node:fs/promises";
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
  throw new Error("Timed out waiting for owner-isolation server.");
}

async function stopServer(child) {
  if (child.exitCode === null) child.kill("SIGTERM");
  if (child.exitCode === null) await once(child, "exit");
}

async function startOwner(root, port, persona, profile) {
  const persomeRoot = join(root, "persome");
  const cardDataDir = join(root, "card");
  await mkdir(persomeRoot, { recursive: true });
  await writeFile(
    join(persomeRoot, "fake-scenario.json"),
    JSON.stringify(persona),
  );
  const child = spawn(process.execPath, ["persome-card-server.mjs"], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NODE_ENV: "production",
      WHOAMI_DEV_MODE: "0",
      WHOAMI_TEST_MODE: "1",
      WHOAMI_PROVIDER_MODE: "fixture",
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_CARD_DATA_DIR: cardDataDir,
      PERSOME_ROOT: persomeRoot,
      PERSOME_CLI: fakePersome,
      PERSOME_MCP_URL: "http://127.0.0.1:1/mcp",
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
  const baseUrl = `http://127.0.0.1:${port}`;
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
    body: JSON.stringify(profile),
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.ready, true);
  return { child, request };
}

test("two isolated macOS owners receive only their own Personal Model", async (t) => {
  await chmod(fakePersome, 0o755);
  const suiteRoot = await mkdtemp(join(tmpdir(), "whoami-two-owners-"));
  const portBase = 21000 + (process.pid % 3000);
  const mira = await startOwner(
    join(suiteRoot, "mira-home"),
    portBase,
    {
      root: "MIRA_ROOT_6C21",
      face: "MIRA_FACE_6C21",
      rewind: "MIRA_REWIND_6C21",
      search: "MIRA_SEARCH_6C21",
      build: "MIRA_BUILD_6C21",
    },
    {
      displayName: "Mira",
      handle: "@mira",
      tagline: "MIRA_CARD_6C21",
      description: "MIRA_IDENTITY_6C21",
    },
  );
  const noah = await startOwner(
    join(suiteRoot, "noah-home"),
    portBase + 1,
    {
      root: "NOAH_ROOT_92EF",
      face: "NOAH_FACE_92EF",
      rewind: "NOAH_REWIND_92EF",
      search: "NOAH_SEARCH_92EF",
      build: "NOAH_BUILD_92EF",
    },
    {
      displayName: "Noah",
      handle: "@noah",
      tagline: "NOAH_CARD_92EF",
      description: "NOAH_IDENTITY_92EF",
    },
  );
  t.after(async () => {
    await Promise.all([stopServer(mira.child), stopServer(noah.child)]);
  });

  const miraBootstrap = await mira.request("/api/model/bootstrap");
  const noahBootstrap = await noah.request("/api/model/bootstrap");
  assert.equal(miraBootstrap.status, 200);
  assert.equal(noahBootstrap.status, 200);
  assert.notEqual(miraBootstrap.body.modelId, noahBootstrap.body.modelId);

  const miraJson = JSON.stringify(miraBootstrap.body);
  const noahJson = JSON.stringify(noahBootstrap.body);
  for (const marker of [
    "MIRA_CARD_6C21",
    "MIRA_IDENTITY_6C21",
    "MIRA_ROOT_6C21",
    "MIRA_REWIND_6C21",
  ]) {
    assert.match(miraJson, new RegExp(marker));
  }
  for (const marker of [
    "NOAH_CARD_92EF",
    "NOAH_IDENTITY_92EF",
    "NOAH_ROOT_92EF",
    "NOAH_REWIND_92EF",
  ]) {
    assert.match(noahJson, new RegExp(marker));
  }
  assert.doesNotMatch(miraJson, /NOAH_|Cecilia|@cecilia|lin-demo|@lin/);
  assert.doesNotMatch(noahJson, /MIRA_|Cecilia|@cecilia|lin-demo|@lin/);

  const miraModels = await mira.request("/api/models");
  const noahModels = await noah.request("/api/models");
  assert.deepEqual(miraModels.body.models.map((model) => model.handle), ["@mira"]);
  assert.deepEqual(noahModels.body.models.map((model) => model.handle), ["@noah"]);
});
