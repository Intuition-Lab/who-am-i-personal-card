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
  const coastCli = join(root, "coast");
  const coastImageDir = "/tmp/coast-cli";
  const coastImage = join(coastImageDir, `whoami-test-${process.pid}.png`);
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
  await mkdir(coastImageDir, { recursive: true, mode: 0o700 });
  await writeFile(
    coastImage,
    Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
      "base64",
    ),
    { mode: 0o600 },
  );
  await writeFile(
    coastCli,
    `#!/bin/sh
set -eu
if [ "$1" = "query" ] && [ "$2" = "cover" ]; then
  printf '%s\\n' '{"frames":[{"frame_id":101,"timestamp":"2026-08-08T19:58:00+08:00","application":"WeChat","title":"EXISTING_COAST_FRAME_ONLY_7D31","ocr_text":"safe rewind frame"}]}'
elif [ "$1" = "query" ] && [ "$2" = "image" ]; then
  printf '%s\\n' '${coastImage}'
else
  exit 2
fi
`,
    { mode: 0o700 },
  );
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
      memoryUpdated: "2026-08-08 14:30:00+08:00",
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
      COAST_CLI: coastCli,
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
  assert.equal(status.personalModel.hasUsableModel, true);

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
  assert.equal(
    bootstrap.snapshot.personalModel.updatedAt,
    "2026-08-08T06:30:00.000Z",
  );
  assert.match(
    JSON.stringify(bootstrap.snapshot.time),
    /EXISTING_REWIND_ONLY_7D31/,
  );
  const future = bootstrap.snapshot.now.items.find(
    ({ kind }) => kind === "future",
  );
  assert.equal(future.metadata.provenance, "generated");
  assert.match(
    future.metadata.method,
    /continuation-suggestion from Persome recent_activity \/ current_context/,
  );
  assert.ok(future.metadata.sourceRefs.length > 0);
  assert.ok(Date.parse(future.metadata.timeRange.start));
  assert.ok(Date.parse(future.metadata.timeRange.end));
  assert.match(future.dayId, /^\d{4}-\d{2}-\d{2}$/);
  assert.ok(future.app.length > 0);
  assert.doesNotMatch(
    JSON.stringify(bootstrap),
    /Cecilia|@cecilia|lin-demo|@lin/,
  );

  const cookie = bootstrapResponse.headers.get("set-cookie")?.split(";", 1)[0];
  assert.ok(cookie);
  const rewindDay = bootstrap.snapshot.time.days.find(
    ({ id }) => id === "2026-08-08",
  ) ?? bootstrap.snapshot.time.days[0];
  const frameListResponse = await fetch(
    `${baseUrl}/api/model/rewind/frames?day=${encodeURIComponent(rewindDay.id)}`,
    { headers: { cookie } },
  );
  const frameList = await frameListResponse.json();
  assert.equal(frameListResponse.status, 200);
  assert.equal(frameList.modelId, bootstrap.modelId);
  assert.equal(frameList.dayId, rewindDay.id);
  assert.equal(frameList.frames.length, 1);
  assert.equal(frameList.frames[0].title, "EXISTING_COAST_FRAME_ONLY_7D31");
  assert.equal(
    frameList.frames[0].reference,
    `${bootstrap.modelId}:coast:101`,
  );

  const frameImageResponse = await fetch(
    `${baseUrl}/api/model/rewind/frame?reference=${encodeURIComponent(frameList.frames[0].reference)}`,
    { headers: { cookie } },
  );
  assert.equal(frameImageResponse.status, 200);
  assert.equal(frameImageResponse.headers.get("content-type"), "image/png");
  assert.deepEqual(
    Buffer.from(await frameImageResponse.arrayBuffer()),
    await readFile(coastImage),
  );

  const unrelatedSessionResponse = await fetch(
    `${baseUrl}/api/model/rewind/frame?reference=${encodeURIComponent(frameList.frames[0].reference)}`,
  );
  assert.notEqual(unrelatedSessionResponse.status, 200);

  const stored = JSON.parse(
    await readFile(join(cardDataDir, "owner-profile.json"), "utf8"),
  );
  assert.equal(stored.origin, "existing-personal-model");
  assert.equal(stored.modelId, bootstrap.modelId);
});
