import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import {
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { ConnectorEventStore } from "../../src/connectors/connector-event-store.mjs";
import { ConnectorSessionService } from "../../src/connectors/connector-session-service.mjs";
import { ReportService } from "../../src/connectors/report-service.mjs";
import { EvidenceService } from "../../src/evidence/evidence-service.mjs";
import { FixtureProvider } from "../../src/providers/fixture-provider.mjs";
import { ProviderRegistry } from "../../src/providers/provider-registry.mjs";

const NOW = new Date("2026-08-07T08:00:00.000Z");
const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const proxyPath = path.join(projectRoot, "whoami-mcp-proxy.mjs");
const fakePersome = fileURLToPath(
  new URL("../../../../tests/fixtures/fake-persome-mcp.py", import.meta.url),
);

async function waitForEventCount(logPath, count) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const lines = (await readFile(logPath, "utf8"))
        .split("\n")
        .filter(Boolean);
      if (lines.length >= count) return;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`Timed out waiting for ${count} Connector events.`);
}

test("Codex Connector closes the context, event, report, Evidence, and revocation loop", async (t) => {
  const root = await mkdtemp(path.join(tmpdir(), "codex-connector-e2e-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const runtimeRoot = path.join(root, "runtime");
  const persomeRoot = path.join(root, "persome");
  const persomeBin = path.join(persomeRoot, "venv/bin/persome");
  await mkdir(path.dirname(persomeBin), { recursive: true, mode: 0o700 });
  await copyFile(fakePersome, persomeBin);
  await chmod(persomeBin, 0o700);

  const sessionIds = ["cs_codex_e2e_0001", "cs_codex_e2e_0002"];
  const sessions = new ConnectorSessionService({
    clock: () => new Date(NOW),
    idFactory: () => sessionIds.shift(),
  });
  const connectorSession = sessions.create({
    viewerSessionId: "vs_codex_e2e_0001",
    modelId: "cecilia",
    connectorId: "codex",
    grantId: "grant_cecilia_e2e",
    scopes: ["model:search", "evidence:read", "reports:read"],
    expiresAt: "2026-08-08T08:00:00.000Z",
  });
  const eventStore = new ConnectorEventStore({
    runtimeRoot,
    clock: () => new Date(NOW),
    sessionService: sessions,
  });
  await eventStore.appendEvent(connectorSession, {
    eventType: "connector/connected",
    tool: "connectAgent",
    summary: "Codex connected to cecilia",
  });

  const child = spawn(process.execPath, [
    proxyPath,
    "--agent",
    "codex",
    "--model",
    connectorSession.modelId,
    "--connector-session",
    connectorSession.sessionId,
    "--grant",
    connectorSession.grantId,
    "--runtime-root",
    runtimeRoot,
    "--persome-root",
    persomeRoot,
  ], { stdio: ["pipe", "pipe", "pipe"] });
  t.after(async () => {
    if (child.exitCode === null) child.kill("SIGTERM");
    if (child.exitCode === null) await once(child, "exit");
  });

  const responses = createInterface({ input: child.stdout });
  const iterator = responses[Symbol.asyncIterator]();
  child.stdin.write(`${JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {},
  })}\n`);
  assert.equal(JSON.parse((await iterator.next()).value).id, 1);
  child.stdin.write(`${JSON.stringify({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: { name: "current_context", arguments: {} },
  })}\n`);
  const contextResponse = JSON.parse((await iterator.next()).value);
  assert.equal(contextResponse.id, 2);
  assert.match(
    contextResponse.result.content[0].text,
    /beta release gate is the current focus/,
  );

  const logPath = eventStore.eventLogPath(connectorSession);
  await waitForEventCount(logPath, 2);
  const events = await eventStore.readEvents(connectorSession);
  assert.equal(events.length, 2);
  assert.equal(events[1].tool, "current_context");
  assert.equal(events[1].summary, "读取当前上下文");
  assert.deepEqual(events[1].details, [
    "The beta release gate is the current focus.",
  ]);
  assert.equal(events[1].receipt, "cecilia:event:2026-08-07:01");

  const reports = new ReportService({
    sessionService: sessions,
    eventStore,
  });
  const [report] = await reports.listReports({
    sessionId: connectorSession.sessionId,
    viewerSessionId: connectorSession.viewerSessionId,
    modelId: connectorSession.modelId,
    connectorId: connectorSession.connectorId,
  });
  assert.equal(report.title, "Codex · Personal Model 使用报告");
  assert.equal(report.readCount, 1);
  assert.equal(report.evidenceCount, 1);
  assert.match(report.summary, /当前模型上下文/);
  assert.match(
    report.sections.find(({ title }) => title === "结果摘要").body,
    /beta release gate is the current focus/,
  );

  const evidence = new EvidenceService({
    providerRegistry: new ProviderRegistry({
      cecilia: new FixtureProvider(),
    }),
    sessionService: sessions,
  });
  const resolved = await evidence.getEvidence({
    viewerSessionId: connectorSession.viewerSessionId,
    activeModelId: connectorSession.modelId,
    connectorSessionId: connectorSession.sessionId,
    reference: report.evidenceRefs[0],
  });
  assert.equal(resolved.modelId, "cecilia");
  assert.ok(["event", "face"].includes(resolved.content.kind));
  assert.equal(resolved.reference, report.evidenceRefs[0]);

  assert.equal(sessions.revoke(connectorSession.sessionId, "disconnected"), true);
  await assert.rejects(
    reports.listReports({
      sessionId: connectorSession.sessionId,
      viewerSessionId: connectorSession.viewerSessionId,
      modelId: connectorSession.modelId,
      connectorId: connectorSession.connectorId,
    }),
    (error) => error.code === "CONNECTOR_SESSION_REVOKED",
  );
  await assert.rejects(
    evidence.getEvidence({
      viewerSessionId: connectorSession.viewerSessionId,
      activeModelId: connectorSession.modelId,
      connectorSessionId: connectorSession.sessionId,
      reference: report.evidenceRefs[0],
    }),
    (error) => error.code === "CONNECTOR_SESSION_REVOKED",
  );

  const reconnected = sessions.create({
    viewerSessionId: connectorSession.viewerSessionId,
    modelId: "cecilia",
    connectorId: "codex",
    grantId: "grant_cecilia_e2e_reconnected",
    scopes: ["evidence:read"],
    expiresAt: "2026-08-08T08:00:00.000Z",
  });
  assert.equal(
    sessions.revokeForModelSwitch(reconnected.viewerSessionId, "lin-demo"),
    1,
  );
  assert.throws(
    () => sessions.resolve(reconnected.sessionId),
    (error) => error.code === "CONNECTOR_SESSION_REVOKED",
  );
});

test("ReportService returns no report when no Connector event exists", async (t) => {
  const runtimeRoot = await mkdtemp(path.join(tmpdir(), "empty-report-e2e-"));
  t.after(() => rm(runtimeRoot, { recursive: true, force: true }));
  const sessions = new ConnectorSessionService({
    clock: () => new Date(NOW),
    idFactory: () => "cs_empty_report_0001",
  });
  const session = sessions.create({
    viewerSessionId: "vs_empty_report_0001",
    modelId: "cecilia",
    connectorId: "codex",
    grantId: "grant_empty_report",
    scopes: ["reports:read"],
    expiresAt: "2026-08-08T08:00:00.000Z",
  });
  const reports = new ReportService({
    sessionService: sessions,
    eventStore: new ConnectorEventStore({
      runtimeRoot,
      sessionService: sessions,
    }),
  });

  assert.deepEqual(await reports.listReports({
    sessionId: session.sessionId,
    viewerSessionId: session.viewerSessionId,
    modelId: session.modelId,
    connectorId: session.connectorId,
  }), []);
});
