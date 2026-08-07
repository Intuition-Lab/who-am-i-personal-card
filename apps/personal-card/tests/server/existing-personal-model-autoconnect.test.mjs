import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import {
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  writeFile,
} from "node:fs/promises";
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
    if (child.exitCode !== null) {
      throw new Error(`Test server exited with ${child.exitCode}`);
    }
    try {
      const response = await fetch(baseUrl, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Startup is asynchronous.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("Timed out waiting for the existing-model test server.");
}

test("production auto-connects an owner-controlled existing Personal Model", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "whoami-existing-model-"));
  const cardDataDir = join(root, "card-data");
  const persomeRoot = join(root, "persome");
  const persomeBin = join(persomeRoot, "venv/bin/persome");
  await mkdir(join(persomeRoot, "venv/bin"), {
    recursive: true,
    mode: 0o700,
  });
  await mkdir(join(persomeRoot, "who-am-i"), {
    recursive: true,
    mode: 0o700,
  });
  await copyFile(fakePersome, persomeBin);
  await chmod(persomeBin, 0o700);
  await writeFile(
    join(persomeRoot, "who-am-i/profile.json"),
    JSON.stringify({
      schemaVersion: 1,
      id: "4bf9bfc0-965f-427c-ae12-7fe452b88d3d",
      displayName: "Existing Owner",
      handle: "@existing-owner",
      tagline: "EXISTING_CARD_ONLY_7D31",
      modelName: "EXISTING_IDENTITY_ONLY_7D31",
    }),
    { mode: 0o600 },
  );
  await writeFile(
    join(persomeRoot, "fake-scenario.json"),
    JSON.stringify({
      root: "EXISTING_ROOT_ONLY_7D31",
      face: "EXISTING_FACE_ONLY_7D31",
      rewind: "EXISTING_REWIND_ONLY_7D31",
    }),
    { mode: 0o600 },
  );

  const port = 26000 + (process.pid % 1000);
  const baseUrl = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, ["persome-card-server.mjs"], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NODE_ENV: "production",
      WHOAMI_DEV_MODE: "0",
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_CARD_DATA_DIR: cardDataDir,
      PERSOME_ROOT: persomeRoot,
      PERSOME_CLI: "",
      PERSOME_MCP_URL: "http://127.0.0.1:1/mcp",
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
  t.after(async () => {
    if (child.exitCode === null) child.kill("SIGTERM");
    if (child.exitCode === null) await once(child, "exit");
  });
  await waitForServer(baseUrl, child);

  const statusResponse = await fetch(`${baseUrl}/api/setup/status`);
  const status = await statusResponse.json();
  assert.equal(statusResponse.status, 200);
  assert.equal(status.ready, true);
  assert.equal(status.state, "ready");
  assert.equal(status.profile.displayName, "Existing Owner");
  assert.equal(status.profile.handle, "@existing-owner");
  assert.equal(status.profile.origin, "existing-personal-model");
  assert.equal(status.personalModel.connection, "existing");

  const bootstrapResponse = await fetch(`${baseUrl}/api/model/bootstrap`);
  const bootstrap = await bootstrapResponse.json();
  assert.equal(bootstrapResponse.status, 200);
  assert.match(bootstrap.modelId, /^local-[a-f0-9]{20}$/);
  assert.equal(bootstrap.snapshot.model.displayName, "Existing Owner");
  assert.equal(bootstrap.snapshot.card.tagline, "EXISTING_CARD_ONLY_7D31");
  assert.equal(
    bootstrap.snapshot.identity.description,
    "EXISTING_IDENTITY_ONLY_7D31",
  );
  assert.match(
    bootstrap.snapshot.personalModel.root,
    /EXISTING_ROOT_ONLY_7D31/,
  );
  assert.match(
    JSON.stringify(bootstrap.snapshot.time),
    /EXISTING_REWIND_ONLY_7D31/,
  );
  assert.doesNotMatch(
    JSON.stringify(bootstrap),
    /Cecilia|@cecilia|lin-demo|@lin/,
  );

  const stored = JSON.parse(
    await readFile(join(cardDataDir, "owner-profile.json"), "utf8"),
  );
  assert.equal(stored.origin, "existing-personal-model");
  assert.equal(stored.modelId, bootstrap.modelId);
});
