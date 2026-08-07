import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import test from "node:test";

const projectRoot = new URL("../../", import.meta.url);

async function waitForServer(baseUrl, child) {
  for (let attempt = 0; attempt < 80; attempt += 1) {
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

test("one viewer session switches Cecilia/Lin without six-module data crossover", async (t) => {
  const port = 18000 + (process.pid % 10000);
  const baseUrl = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, ["persome-card-server.mjs"], {
    cwd: projectRoot,
    env: {
      ...process.env,
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_PROVIDER_MODE: "fixture",
      WHOAMI_DEV_MODE: "1",
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
  t.after(async () => {
    if (child.exitCode === null) child.kill("SIGTERM");
    if (child.exitCode === null) await once(child, "exit");
  });
  await waitForServer(baseUrl, child);

  let cookie = "";
  async function request(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (cookie) headers.Cookie = cookie;
    const response = await fetch(`${baseUrl}${path}`, {
      ...options,
      headers,
    });
    const setCookie = response.headers.get("set-cookie");
    if (setCookie) cookie = setCookie.split(";", 1)[0];
    return {
      status: response.status,
      body: await response.json(),
    };
  }
  const switchTo = (modelId, access) => request("/api/session/model", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ modelId, access }),
  });

  const cecilia = await request("/api/model/bootstrap");
  assert.equal(cecilia.status, 200);
  assert.equal(cecilia.body.modelId, "cecilia");
  assert.equal(cecilia.body.snapshot.model.handle, "@cecilia");

  const connected = await request("/api/model/connectors/codex/connect", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{}",
  });
  assert.equal(connected.status, 200);
  assert.equal(connected.body.modelId, "cecilia");
  const oldConnectorSessionId = connected.body.connector.sessionId;

  const lin = await switchTo("lin-demo", "authorized");
  assert.equal(lin.status, 200);
  assert.equal(lin.body.modelId, "lin-demo");
  assert.equal(lin.body.snapshot.model.handle, "@lin");
  assert.equal(lin.body.snapshot.authorization.viewerMode, "authorized");
  assert.equal(JSON.stringify(lin.body).includes("@cecilia"), false);

  const [connectors, reports, evidence] = await Promise.all([
    request("/api/model/connectors"),
    request("/api/model/reports"),
    request("/api/model/evidence/lin-demo%3Aevent%3A2026-08-07%3A01"),
  ]);
  assert.equal(connectors.body.modelId, "lin-demo");
  assert.equal(reports.body.modelId, "lin-demo");
  assert.ok(reports.body.reports.every((report) => report.modelId === "lin-demo"));
  assert.equal(evidence.body.evidence.modelId, "lin-demo");
  assert.equal(lin.body.snapshot.card.publicUrl, "pm.app/lin");
  assert.match(lin.body.snapshot.time.days[0].events[0].title, /夜间导航/);
  assert.match(lin.body.snapshot.identity.description, /Urban interaction/);
  assert.equal(
    JSON.stringify({ connectors, reports, evidence }).includes("cecilia:"),
    false,
  );

  const crossModelEvidence = await request(
    "/api/model/evidence?reference=cecilia:event:2026-08-07:01",
  );
  assert.equal(crossModelEvidence.status, 403);
  assert.equal(crossModelEvidence.body.code, "EVIDENCE_MODEL_MISMATCH");

  const revokedConnector = await request(
    `/api/model/evidence?reference=lin-demo:event:2026-08-07:01&connectorSessionId=${oldConnectorSessionId}`,
  );
  assert.equal(revokedConnector.status, 403);
  assert.equal(revokedConnector.body.code, "CONNECTOR_SESSION_REVOKED");

  const linPublic = await switchTo("lin-demo", "public");
  assert.deepEqual(
    Object.keys(linPublic.body.snapshot).sort(),
    ["authorization", "card", "identity", "model", "projection", "schemaVersion"],
  );
  const publicReports = await request("/api/model/reports");
  assert.equal(publicReports.status, 403);
  assert.equal(publicReports.body.code, "SCOPE_REQUIRED");

  const ceciliaAgain = await switchTo("cecilia", "owner");
  assert.equal(ceciliaAgain.body.modelId, "cecilia");
  assert.equal(ceciliaAgain.body.snapshot.model.handle, "@cecilia");
  assert.equal(
    JSON.stringify(ceciliaAgain.body).includes("lin-demo:"),
    false,
  );

  const override = await request("/api/model/search?modelId=lin-demo", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query: "Personal Card" }),
  });
  assert.equal(override.status, 403);
  assert.equal(override.body.code, "MODEL_OVERRIDE_FORBIDDEN");
});
