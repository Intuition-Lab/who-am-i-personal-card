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
  throw new Error("Timed out waiting for the Personal Card test server.");
}

function startServer(port, cardDataDir, persomeRoot) {
  return spawn(process.execPath, ["persome-card-server.mjs"], {
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
}

async function stopServer(child) {
  if (child.exitCode === null) child.kill("SIGTERM");
  if (child.exitCode === null) await once(child, "exit");
}

test("production creates and restores the downloader's own Personal Model identity", async (t) => {
  await chmod(fakePersome, 0o755);
  const root = await mkdtemp(join(tmpdir(), "whoami-personal-owner-"));
  const cardDataDir = join(root, "card-data");
  const persomeRoot = join(root, "persome");
  await mkdir(persomeRoot, { recursive: true });
  await writeFile(join(persomeRoot, "config.toml"), "[mcp]\ntransport='stdio'\n");
  await writeFile(join(persomeRoot, "index.db"), "");
  const port = 19000 + (process.pid % 5000);
  const baseUrl = `http://127.0.0.1:${port}`;
  let child = startServer(port, cardDataDir, persomeRoot);
  t.after(async () => stopServer(child));
  await waitForServer(baseUrl, child);

  let cookie = "";
  async function request(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (cookie) headers.Cookie = cookie;
    const response = await fetch(`${baseUrl}${path}`, { ...options, headers });
    const setCookie = response.headers.get("set-cookie");
    if (setCookie) cookie = setCookie.split(";", 1)[0];
    return { status: response.status, body: await response.json() };
  }

  const before = await request("/api/setup/status");
  assert.equal(before.body.state, "profile_required");
  assert.equal(before.body.ready, false);
  const emptyModels = await request("/api/models");
  assert.deepEqual(emptyModels.body.models, []);
  assert.equal(emptyModels.body.devMode, false);

  const blocked = await request("/api/model/bootstrap");
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.code, "PROFILE_REQUIRED");
  assert.doesNotMatch(JSON.stringify(blocked.body), /Cecilia|@cecilia|Lin|@lin/);

  const saved = await request("/api/setup/profile", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      displayName: "Mira",
      handle: "@mira",
      tagline: "MIRA_ONLY_CARD_6C21",
      description: "MIRA_ONLY_IDENTITY_6C21",
    }),
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.ready, true);
  assert.match(saved.body.profile.modelId, /^local-[a-f0-9]{20}$/);
  const stableModelId = saved.body.profile.modelId;

  const bootstrap = await request("/api/model/bootstrap");
  assert.equal(bootstrap.status, 200);
  assert.equal(bootstrap.body.modelId, stableModelId);
  assert.equal(bootstrap.body.snapshot.model.displayName, "Mira");
  assert.equal(bootstrap.body.snapshot.model.handle, "@mira");
  assert.equal(bootstrap.body.snapshot.card.tagline, "MIRA_ONLY_CARD_6C21");
  assert.equal(
    bootstrap.body.snapshot.identity.description,
    "MIRA_ONLY_IDENTITY_6C21",
  );
  assert.match(
    bootstrap.body.snapshot.personalModel.root,
    /MIRA_ONLY_ROOT_6C21/,
  );
  assert.match(
    JSON.stringify(bootstrap.body.snapshot.time),
    /MIRA_ONLY_REWIND_6C21/,
  );
  assert.doesNotMatch(
    JSON.stringify(bootstrap.body),
    /Cecilia|@cecilia|lin-demo|@lin/,
  );

  const previousConclusion =
    "MIRA_ONLY_FACE_6C21 returns to the field before making a decision.";
  const replacement =
    "MIRA_ONLY_FACE_6C21 now verifies authorization before making a decision.";
  assert.equal(
    bootstrap.body.snapshot.personalModel.faces[0].text,
    previousConclusion,
  );
  const eventReference =
    bootstrap.body.snapshot.time.days[0].events[0].evidenceRef;
  const eventEvidence = await request(
    `/api/model/evidence/${encodeURIComponent(eventReference)}`,
  );
  assert.equal(eventEvidence.status, 200);
  assert.equal(eventEvidence.body.evidence.modelId, stableModelId);
  assert.equal(
    eventEvidence.body.evidence.source.type,
    "persome-activity",
  );
  assert.equal(eventEvidence.body.evidence.source.application, "Notes");
  assert.equal(
    eventEvidence.body.evidence.source.originalTime,
    new Date("2026-08-07T09:00").toISOString(),
  );
  assert.equal(
    eventEvidence.body.evidence.supports[0].relationship,
    "direct",
  );
  assert.equal(eventEvidence.body.evidence.availability.status, "available");

  const faceReference =
    bootstrap.body.snapshot.personalModel.faces[0].evidenceRefs[0];
  const faceEvidence = await request(
    `/api/model/evidence/${encodeURIComponent(faceReference)}`,
  );
  assert.equal(faceEvidence.status, 200);
  assert.equal(faceEvidence.body.evidence.source.type, "derived-summary");
  assert.equal(faceEvidence.body.evidence.availability.status, "available");
  assert.equal(faceEvidence.body.evidence.supports[0].relationship, "indirect");
  assert.equal(
    faceEvidence.body.evidence.content.lineage[0].reference.startsWith(
      `${stableModelId}:`,
    ),
    true,
  );
  const corrected = await request("/api/model/correct", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ correction: "The old conclusion is inaccurate." }),
  });
  assert.equal(corrected.status, 200);
  assert.equal(corrected.body.ok, true);
  assert.equal(corrected.body.status, "applied");
  assert.match(
    corrected.body.receipt,
    new RegExp(`^${stableModelId}:correction:[a-f0-9]{64}$`),
  );
  assert.equal(corrected.body.receiptSource, "product");
  assert.equal(corrected.body.affected[0].state, "deprioritized");
  assert.equal(corrected.body.verification.status, "verified");
  assert.equal(corrected.body.verification.refreshed, true);
  assert.equal(
    corrected.body.verification.oldConclusionDeprioritized,
    true,
  );
  assert.equal(corrected.body.revision, bootstrap.body.revision + 1);

  const propagated = await request("/api/model/bootstrap");
  assert.equal(
    propagated.body.snapshot.personalModel.faces[0].text,
    replacement,
  );
  assert.equal(JSON.stringify(propagated.body).includes(previousConclusion), false);

  const productionModels = await request("/api/models");
  assert.deepEqual(
    productionModels.body.models.map((model) => model.id),
    [stableModelId],
  );
  const fixtureAttempt = await request("/api/session/model", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ modelId: "lin-demo", access: "owner" }),
  });
  assert.equal(fixtureAttempt.status, 403);
  assert.doesNotMatch(JSON.stringify(fixtureAttempt.body), /@lin/);

  await stopServer(child);
  child = startServer(port, cardDataDir, persomeRoot);
  await waitForServer(baseUrl, child);
  cookie = "";
  const restarted = await request("/api/model/bootstrap");
  assert.equal(restarted.status, 200);
  assert.equal(restarted.body.modelId, stableModelId);
  assert.equal(restarted.body.snapshot.model.handle, "@mira");
  assert.equal(
    restarted.body.snapshot.personalModel.faces[0].text,
    replacement,
  );
});
