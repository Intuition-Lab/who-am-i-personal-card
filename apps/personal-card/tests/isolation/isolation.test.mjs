import assert from "node:assert/strict";
import { appendFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  ConnectorEventStore,
  stableConnectorEventHash,
} from "../../src/connectors/connector-event-store.mjs";
import {
  ConnectorSessionService,
  assertSafeViewerSessionId,
} from "../../src/connectors/connector-session-service.mjs";
import { ReportService } from "../../src/connectors/report-service.mjs";
import { EvidenceService } from "../../src/evidence/evidence-service.mjs";
import { FixtureProvider } from "../../src/providers/fixture-provider.mjs";
import { ProviderRegistry } from "../../src/providers/provider-registry.mjs";

const NOW = new Date("2026-08-07T08:00:00.000Z");
const EXPIRES_AT = "2026-08-08T08:00:00.000Z";

function createSessionService(ids) {
  const queue = [...ids];
  return new ConnectorSessionService({
    clock: () => new Date(NOW),
    idFactory: () => queue.shift(),
  });
}

function createConnectorSession(
  service,
  {
    sessionId,
    viewerSessionId = "vs_viewer_0001",
    modelId = "cecilia",
    connectorId = "codex",
    grantId = `grant_${modelId}`,
    scopes = ["model:search", "evidence:read", "reports:read"],
  } = {},
) {
  if (sessionId) {
    service.idFactory = () => sessionId;
  }
  return service.create({
    viewerSessionId,
    modelId,
    connectorId,
    grantId,
    scopes,
    expiresAt: EXPIRES_AT,
  });
}

async function withTempRuntime(run) {
  const runtimeRoot = await mkdtemp(
    path.join(tmpdir(), "personal-card-isolation-"),
  );
  try {
    return await run(runtimeRoot);
  } finally {
    await rm(runtimeRoot, { recursive: true, force: true });
  }
}

test("ConnectorSessionService binds immutable model, connector, Grant, scopes, and expiry", () => {
  const service = createSessionService(["cs_cecilia_session_0001"]);
  const session = createConnectorSession(service);

  assert.deepEqual(
    {
      sessionId: session.sessionId,
      viewerSessionId: session.viewerSessionId,
      modelId: session.modelId,
      connectorId: session.connectorId,
      grantId: session.grantId,
      scopes: session.scopes,
      expiresAt: session.expiresAt,
    },
    {
      sessionId: "cs_cecilia_session_0001",
      viewerSessionId: "vs_viewer_0001",
      modelId: "cecilia",
      connectorId: "codex",
      grantId: "grant_cecilia",
      scopes: ["model:search", "evidence:read", "reports:read"],
      expiresAt: EXPIRES_AT,
    },
  );
  assert.ok(Object.isFrozen(session));
  assert.ok(Object.isFrozen(session.scopes));
  assert.equal(
    service.resolve(session.sessionId, {
      viewerSessionId: "vs_viewer_0001",
      modelId: "cecilia",
      connectorId: "codex",
      requiredScope: "evidence:read",
    }),
    session,
  );
});

test("viewer session validation accepts E4 opaque cookie IDs without weakening path safety", () => {
  assert.equal(
    assertSafeViewerSessionId("A".repeat(43)),
    "A".repeat(43),
  );
  assert.throws(
    () => assertSafeViewerSessionId("../viewer-session"),
    (error) => error.code === "INVALID_VIEWER_SESSION_ID",
  );
});

test("switching active model revokes old viewer Connector Sessions", () => {
  const service = createSessionService([
    "cs_cecilia_session_0001",
    "cs_lin_demo_session_0001",
  ]);
  const cecilia = createConnectorSession(service);
  const lin = createConnectorSession(service, {
    modelId: "lin-demo",
    grantId: "grant_lin_demo",
  });

  assert.equal(
    service.revokeForModelSwitch("vs_viewer_0001", "lin-demo"),
    1,
  );
  assert.throws(
    () => service.resolve(cecilia.sessionId),
    (error) => error.code === "CONNECTOR_SESSION_REVOKED",
  );
  assert.equal(service.resolve(lin.sessionId), lin);
});

test("expired Connector Sessions are rejected and revoked", () => {
  let now = new Date(NOW);
  const service = new ConnectorSessionService({
    clock: () => new Date(now),
    idFactory: () => "cs_cecilia_session_0001",
  });
  const session = createConnectorSession(service);
  now = new Date("2026-08-09T08:00:00.000Z");

  assert.throws(
    () => service.resolve(session.sessionId),
    (error) => error.code === "CONNECTOR_SESSION_EXPIRED",
  );
  assert.throws(
    () => service.resolve(session.sessionId),
    (error) => error.code === "CONNECTOR_SESSION_REVOKED",
  );
});

test("stable event hash includes modelId, connectorId, sessionId, and grantId", () => {
  const base = {
    modelId: "cecilia",
    connectorId: "codex",
    sessionId: "cs_cecilia_session_0001",
    grantId: "grant_cecilia",
    eventType: "tools/call",
    requestId: 7,
    tool: "search",
    receipt: "cecilia:event:01",
    summary: "same event",
    occurredAt: NOW.toISOString(),
    durationMs: 12,
  };
  const baseHash = stableConnectorEventHash(base);

  for (const [field, value] of [
    ["modelId", "lin-demo"],
    ["connectorId", "claude-code"],
    ["sessionId", "cs_cecilia_session_0002"],
    ["grantId", "grant_other"],
  ]) {
    assert.notEqual(
      stableConnectorEventHash({ ...base, [field]: value }),
      baseHash,
      `${field} must change the stable hash`,
    );
  }
});

test("same JSON-RPC id and connector write to model/session-specific logs", async () => {
  await withTempRuntime(async (runtimeRoot) => {
    const sessions = createSessionService([
      "cs_cecilia_session_0001",
      "cs_lin_demo_session_0001",
    ]);
    const cecilia = createConnectorSession(sessions);
    const lin = createConnectorSession(sessions, {
      modelId: "lin-demo",
      grantId: "grant_lin_demo",
    });
    const store = new ConnectorEventStore({
      runtimeRoot,
      clock: () => new Date(NOW),
      sessionService: sessions,
    });

    const [ceciliaEvent, linEvent] = await Promise.all([
      store.appendEvent(cecilia, {
        requestId: 42,
        tool: "search",
        receipt: "cecilia:event:01",
        summary: "CECILIA_SENTINEL",
        occurredAt: NOW.toISOString(),
      }),
      store.appendEvent(lin, {
        requestId: 42,
        tool: "search",
        receipt: "lin-demo:event:01",
        summary: "LIN_SENTINEL",
        occurredAt: NOW.toISOString(),
      }),
    ]);

    assert.notEqual(ceciliaEvent.eventId, linEvent.eventId);
    assert.equal(ceciliaEvent.requestId, linEvent.requestId);
    assert.notEqual(store.eventLogPath(cecilia), store.eventLogPath(lin));
    assert.ok(
      store
        .eventLogPath(cecilia)
        .endsWith(
          "models/cecilia/connectors/codex/sessions/cs_cecilia_session_0001/events.jsonl",
        ),
    );

    const [ceciliaEvents, linEvents] = await Promise.all([
      store.readEvents(cecilia),
      store.readEvents(lin),
    ]);
    assert.deepEqual(
      ceciliaEvents.map(({ summary }) => summary),
      ["CECILIA_SENTINEL"],
    );
    assert.deepEqual(
      linEvents.map(({ summary }) => summary),
      ["LIN_SENTINEL"],
    );
  });
});

test("ReportService aggregates only one model, connector, session, and Grant", async () => {
  await withTempRuntime(async (runtimeRoot) => {
    const sessions = createSessionService([
      "cs_cecilia_session_0001",
      "cs_lin_demo_session_0001",
    ]);
    const cecilia = createConnectorSession(sessions);
    const lin = createConnectorSession(sessions, {
      modelId: "lin-demo",
      grantId: "grant_lin_demo",
    });
    const store = new ConnectorEventStore({
      runtimeRoot,
      clock: () => new Date(NOW),
      sessionService: sessions,
    });
    await Promise.all([
      store.appendEvent(cecilia, {
        requestId: 1,
        tool: "search",
        receipt: "cecilia:event:01",
        summary: "CECILIA_SENTINEL",
      }),
      store.appendEvent(lin, {
        requestId: 1,
        tool: "search",
        receipt: "lin-demo:event:01",
        summary: "LIN_SENTINEL",
      }),
    ]);

    const reports = new ReportService({
      sessionService: sessions,
      eventStore: store,
    });
    const [ceciliaReports, linReports] = await Promise.all([
      reports.listReports({
        sessionId: cecilia.sessionId,
        viewerSessionId: cecilia.viewerSessionId,
        modelId: "cecilia",
        connectorId: "codex",
      }),
      reports.listReports({
        sessionId: lin.sessionId,
        viewerSessionId: lin.viewerSessionId,
        modelId: "lin-demo",
        connectorId: "codex",
      }),
    ]);

    assert.equal(ceciliaReports[0].modelId, "cecilia");
    assert.equal(linReports[0].modelId, "lin-demo");
    assert.equal(JSON.stringify(ceciliaReports).includes("LIN_SENTINEL"), false);
    assert.equal(JSON.stringify(linReports).includes("CECILIA_SENTINEL"), false);
    assert.deepEqual(ceciliaReports[0].evidenceRefs, ["cecilia:event:01"]);
    assert.deepEqual(linReports[0].evidenceRefs, ["lin-demo:event:01"]);

    await assert.rejects(
      reports.listReports({
        sessionId: cecilia.sessionId,
        viewerSessionId: cecilia.viewerSessionId,
        modelId: "lin-demo",
        connectorId: "codex",
      }),
      (error) => error.code === "CONNECTOR_MODEL_MISMATCH",
    );
  });
});

test("damaged JSONL tail is ignored without falling back to another model", async () => {
  await withTempRuntime(async (runtimeRoot) => {
    const sessions = createSessionService(["cs_cecilia_session_0001"]);
    const cecilia = createConnectorSession(sessions);
    const store = new ConnectorEventStore({
      runtimeRoot,
      clock: () => new Date(NOW),
      sessionService: sessions,
    });
    await store.appendEvent(cecilia, {
      requestId: 5,
      tool: "search",
      receipt: "cecilia:event:01",
      summary: "CECILIA_SENTINEL",
    });
    await appendFile(store.eventLogPath(cecilia), '{"partial":', "utf8");

    const recovered = await store.readEvents(cecilia);
    assert.equal(recovered.length, 1);
    assert.equal(recovered[0].summary, "CECILIA_SENTINEL");

    const missingLinLog = await store.readEvents({
      modelId: "lin-demo",
      connectorId: "codex",
      sessionId: "cs_lin_demo_missing_0001",
      grantId: "grant_lin_demo",
    });
    assert.deepEqual(missingLinLog, []);
  });
});

test("Event Store rejects cross-model receipts and unsafe path identities", async () => {
  await withTempRuntime(async (runtimeRoot) => {
    const sessions = createSessionService(["cs_cecilia_session_0001"]);
    const cecilia = createConnectorSession(sessions);
    const store = new ConnectorEventStore({
      runtimeRoot,
      sessionService: sessions,
    });

    await assert.rejects(
      store.appendEvent(cecilia, {
        receipt: "lin-demo:event:01",
      }),
      (error) => error.code === "EVIDENCE_MODEL_MISMATCH",
    );
    assert.throws(
      () =>
        store.eventLogPath({
          modelId: "../cecilia",
          connectorId: "codex",
          sessionId: cecilia.sessionId,
        }),
      (error) => error.code === "INVALID_MODEL_ID",
    );
  });
});

test("EvidenceService blocks cross-model receipt before calling Provider", async () => {
  const sessions = createSessionService(["cs_cecilia_session_0001"]);
  const cecilia = createConnectorSession(sessions);
  const fixture = new FixtureProvider();
  let providerCalls = 0;
  const observedProvider = new Proxy(fixture, {
    get(target, property, receiver) {
      if (property === "getEvidence") {
        return async (...args) => {
          providerCalls += 1;
          return target.getEvidence(...args);
        };
      }
      return Reflect.get(target, property, receiver);
    },
  });
  const registry = new ProviderRegistry({
    cecilia: observedProvider,
    "lin-demo": observedProvider,
  });
  const evidenceService = new EvidenceService({
    providerRegistry: registry,
    sessionService: sessions,
  });

  const valid = await evidenceService.getEvidence({
    viewerSessionId: cecilia.viewerSessionId,
    activeModelId: "cecilia",
    connectorSessionId: cecilia.sessionId,
    reference: "cecilia:event:2026-08-07:01",
  });
  assert.equal(valid.modelId, "cecilia");
  assert.equal(providerCalls, 1);

  await assert.rejects(
    evidenceService.getEvidence({
      viewerSessionId: cecilia.viewerSessionId,
      activeModelId: "cecilia",
      connectorSessionId: cecilia.sessionId,
      reference: "lin-demo:event:2026-08-07:01",
    }),
    (error) => error.code === "EVIDENCE_MODEL_MISMATCH",
  );
  assert.equal(providerCalls, 1);

  await assert.rejects(
    evidenceService.getEvidence({
      viewerSessionId: cecilia.viewerSessionId,
      activeModelId: "lin-demo",
      connectorSessionId: cecilia.sessionId,
      reference: "lin-demo:event:2026-08-07:01",
    }),
    (error) => error.code === "CONNECTOR_MODEL_MISMATCH",
  );
  assert.equal(providerCalls, 1);
});

test("Coast frame allowlist is partitioned by model and viewer session", async () => {
  const sessions = createSessionService(["cs_cecilia_session_0001"]);
  createConnectorSession(sessions);
  const registry = new ProviderRegistry({
    cecilia: new FixtureProvider(),
    "lin-demo": new FixtureProvider(),
  });
  const evidenceService = new EvidenceService({
    providerRegistry: registry,
    sessionService: sessions,
    loadCoastFrame: async ({ modelId, frameId }) => ({
      marker: `${modelId}:${frameId}`,
    }),
  });
  evidenceService.allowCoastFrame({
    viewerSessionId: "vs_viewer_0001",
    modelId: "cecilia",
    frameId: "frame_001",
  });

  const allowed = await evidenceService.getCoastFrame({
    viewerSessionId: "vs_viewer_0001",
    activeModelId: "cecilia",
    reference: "cecilia:coast:frame_001",
  });
  assert.equal(allowed.content.marker, "cecilia:frame_001");

  for (const request of [
    {
      viewerSessionId: "vs_viewer_0002",
      activeModelId: "cecilia",
      reference: "cecilia:coast:frame_001",
    },
    {
      viewerSessionId: "vs_viewer_0001",
      activeModelId: "lin-demo",
      reference: "lin-demo:coast:frame_001",
    },
  ]) {
    await assert.rejects(
      evidenceService.getCoastFrame(request),
      (error) => error.code === "COAST_FRAME_NOT_AUTHORIZED",
    );
  }

  evidenceService.allowCoastFrame({
    viewerSessionId: "vs_viewer_0001",
    modelId: "lin-demo",
    frameId: "frame_001",
  });
  assert.equal(
    evidenceService.revokeCoastFramesForModelSwitch(
      "vs_viewer_0001",
      "lin-demo",
    ),
    1,
  );
  await assert.rejects(
    evidenceService.getCoastFrame({
      viewerSessionId: "vs_viewer_0001",
      activeModelId: "cecilia",
      reference: "cecilia:coast:frame_001",
    }),
    (error) => error.code === "COAST_FRAME_NOT_AUTHORIZED",
  );
  const linFrame = await evidenceService.getCoastFrame({
    viewerSessionId: "vs_viewer_0001",
    activeModelId: "lin-demo",
    reference: "lin-demo:coast:frame_001",
  });
  assert.equal(linFrame.content.marker, "lin-demo:frame_001");
});

test("revoked Connector Session cannot produce Reports or Evidence", async () => {
  await withTempRuntime(async (runtimeRoot) => {
    const sessions = createSessionService(["cs_cecilia_session_0001"]);
    const cecilia = createConnectorSession(sessions);
    const store = new ConnectorEventStore({
      runtimeRoot,
      sessionService: sessions,
    });
    await store.appendEvent(cecilia, {
      receipt: "cecilia:event:01",
      summary: "before switch",
    });
    const reports = new ReportService({
      sessionService: sessions,
      eventStore: store,
    });
    const evidence = new EvidenceService({
      providerRegistry: new ProviderRegistry({
        cecilia: new FixtureProvider(),
      }),
      sessionService: sessions,
    });

    sessions.revokeForModelSwitch("vs_viewer_0001", "lin-demo");

    await assert.rejects(
      store.appendEvent(cecilia, {
        receipt: "cecilia:event:02",
        summary: "after switch",
      }),
      (error) => error.code === "CONNECTOR_SESSION_REVOKED",
    );
    await assert.rejects(
      reports.listReports({
        sessionId: cecilia.sessionId,
        viewerSessionId: cecilia.viewerSessionId,
        modelId: "cecilia",
        connectorId: "codex",
      }),
      (error) => error.code === "CONNECTOR_SESSION_REVOKED",
    );
    await assert.rejects(
      evidence.getEvidence({
        viewerSessionId: cecilia.viewerSessionId,
        activeModelId: "cecilia",
        connectorSessionId: cecilia.sessionId,
        reference: "cecilia:event:2026-08-07:01",
      }),
      (error) => error.code === "CONNECTOR_SESSION_REVOKED",
    );
  });
});
