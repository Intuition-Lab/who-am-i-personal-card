import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  PersonalModelProviderError,
  assertPersonalModelProvider,
} from "../../src/contracts/personal-model-provider.mjs";
import { FixtureProvider } from "../../src/providers/fixture-provider.mjs";
import { LocalPersomeProvider } from "../../src/providers/local-persome-provider.mjs";
import { ProviderRegistry } from "../../src/providers/provider-registry.mjs";
import { RemotePersonalModelProvider } from "../../src/providers/remote-personal-model-provider.mjs";
import { defineProviderContract } from "./provider-contract.shared.mjs";

const fixtureUrls = {
  cecilia: new URL("../../fixtures/models/cecilia.json", import.meta.url),
  "lin-demo": new URL("../../fixtures/models/lin.json", import.meta.url),
};

async function loadFixture(modelId) {
  return JSON.parse(await readFile(fixtureUrls[modelId], "utf8"));
}

function createLocalProvider(overrides = {}) {
  return new LocalPersomeProvider({
    modelIds: ["cecilia", "lin-demo"],
    loadSnapshot: async ({ modelId }) => loadFixture(modelId),
    ...overrides,
  });
}

function jsonResponse(value, init = {}) {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "content-type": "application/json" },
    ...init,
  });
}

function createRemoteFetch({ requests = [] } = {}) {
  return async (url, options = {}) => {
    const parsed = new URL(url);
    const path = parsed.pathname.replace(/^\/v1\//u, "");
    requests.push({
      path,
      method: options.method ?? "GET",
      authorization: options.headers?.authorization,
      body: options.body,
    });

    if (path === "models") {
      const [cecilia, lin] = await Promise.all([
        loadFixture("cecilia"),
        loadFixture("lin-demo"),
      ]);
      return jsonResponse([cecilia.model, lin.model]);
    }

    const segments = path.split("/").map(decodeURIComponent);
    const modelId = segments[1];
    const fixture = await loadFixture(modelId);

    if (segments[2] === "snapshot") {
      return jsonResponse(fixture);
    }
    if (segments[2] === "context") {
      return jsonResponse({
        modelId,
        root: fixture.personalModel.root,
      });
    }
    if (segments[2] === "search") {
      return jsonResponse([
        {
          modelId,
          id: `${modelId}:search:1`,
          text: fixture.personalModel.root,
        },
      ]);
    }
    if (segments[2] === "evidence") {
      const reference = segments[3];
      return jsonResponse({
        modelId,
        reference,
        content: { title: fixture.time.days[0].events[0].title },
      });
    }
    if (segments[2] === "corrections") {
      return jsonResponse({ modelId, accepted: true });
    }
    if (segments[2] === "connectors") {
      return jsonResponse({
        modelId,
        connectorId: segments[3],
        status: "connected",
      });
    }
    if (segments[2] === "reports") {
      return jsonResponse(fixture.reports);
    }

    return jsonResponse({ error: "not found" }, { status: 404 });
  };
}

function createRemoteProvider(overrides = {}) {
  return new RemotePersonalModelProvider({
    baseUrl: "https://models.example/v1/",
    bearerToken: "test-token",
    fetchImpl: createRemoteFetch(),
    timeoutMs: 1_000,
    ...overrides,
  });
}

defineProviderContract("FixtureProvider", () => new FixtureProvider());
defineProviderContract("LocalPersomeProvider", () => createLocalProvider());
defineProviderContract("RemotePersonalModelProvider", () =>
  createRemoteProvider(),
);

test("FixtureProvider model operations remain bound to the requested model", async () => {
  const provider = new FixtureProvider();

  const [context, search, evidence, reports, connector] = await Promise.all([
    provider.getCurrentContext("lin-demo"),
    provider.search("lin-demo", "夜间"),
    provider.getEvidence(
      "lin-demo",
      "lin-demo:event:2026-08-07:01",
    ),
    provider.listAgentReports("lin-demo"),
    provider.connectAgent("lin-demo", "codex"),
  ]);

  assert.equal(context.modelId, "lin-demo");
  assert.ok(search.every(({ modelId }) => modelId === "lin-demo"));
  assert.equal(evidence.modelId, "lin-demo");
  assert.equal(evidence.source.type, "derived-summary");
  assert.equal(evidence.availability.status, "unavailable");
  assert.ok(reports.every(({ modelId }) => modelId === "lin-demo"));
  assert.equal(connector.modelId, "lin-demo");

  await assert.rejects(
    provider.getEvidence("lin-demo", "cecilia:event:2026-08-07:01"),
    (error) =>
      error instanceof PersonalModelProviderError &&
      error.code === "EVIDENCE_MODEL_MISMATCH",
  );
  await assert.rejects(
    provider.correct("lin-demo", "change private memory"),
    (error) =>
      error instanceof PersonalModelProviderError &&
      error.code === "PROVIDER_READ_ONLY",
  );
});

test("LocalPersomeProvider falls back to fixtures without leaking local MCP errors", async () => {
  const privateRuntimeError =
    "MCP failed at /Users/private/.persome/index.db: raw secret payload";
  const provider = new LocalPersomeProvider({
    modelIds: ["cecilia", "lin-demo"],
    loadSnapshot: async () => {
      throw new Error(privateRuntimeError);
    },
    fallbackProvider: new FixtureProvider(),
  });

  const snapshot = await provider.getSnapshot("lin-demo");
  assert.equal(snapshot.model.id, "lin-demo");

  const noFallback = new LocalPersomeProvider({
    modelIds: ["cecilia"],
    loadSnapshot: async () => {
      throw new Error(privateRuntimeError);
    },
  });
  await assert.rejects(
    noFallback.getSnapshot("cecilia"),
    (error) => {
      assert.equal(error.code, "LOCAL_PROVIDER_UNAVAILABLE");
      assert.equal(JSON.stringify(error).includes(privateRuntimeError), false);
      assert.equal(error.message.includes("/Users/private"), false);
      return true;
    },
  );
});

test("LocalPersomeProvider sanitizes mutable operation failures", async () => {
  const provider = createLocalProvider({
    operations: {
      correct: async () => {
        throw new Error("raw MCP correction body");
      },
    },
  });

  await assert.rejects(
    provider.correct("cecilia", "correction"),
    (error) =>
      error instanceof PersonalModelProviderError &&
      error.code === "LOCAL_OPERATION_FAILED" &&
      !error.message.includes("raw MCP"),
  );
});

test("LocalPersomeProvider returns complete deduplicated semantic results with evidence metadata", async () => {
  let received;
  const fullBody = "A complete durable memory body with the project decision, source context, and supporting detail.";
  const provider = createLocalProvider({
    operations: {
      search: async (request) => {
        received = request;
        return [
          {
            modelId: "cecilia",
            id: "semantic-1",
            content: fullBody,
            path: "project-personal-card.md",
            timestamp: "2026-08-09T08:00:00+08:00",
            confidence: 0.93,
          },
          {
            modelId: "cecilia",
            id: "semantic-1",
            content: fullBody,
            path: "project-personal-card.md",
          },
          {
            modelId: "lin-demo",
            id: "foreign-result",
            content: "must never cross models",
          },
        ];
      },
    },
  });

  const results = await provider.search("cecilia", "semantic decision", undefined, {
    top_k: 2,
    breadth: 0.4,
  });
  assert.equal(received.modelId, "cecilia");
  assert.equal(received.options.topK, 2);
  assert.equal(received.options.breadth, 0.4);
  assert.equal(results.length, 1);
  assert.equal(results[0].text, fullBody);
  assert.equal(results[0].body, fullBody);
  assert.equal(results[0].contentType, "observed");
  assert.equal(results[0].confidence, 0.93);
  assert.deepEqual(results[0].timeRange, {
    start: "2026-08-09T08:00:00+08:00",
    end: "2026-08-09T08:00:00+08:00",
  });
  assert.match(results[0].evidenceRefs[0], /^cecilia:memory:/u);
  assert.equal(JSON.stringify(results).includes("foreign-result"), false);
});

test("LocalPersomeProvider ask is evidence-bound and refuses when retrieval is empty", async () => {
  const grounded = createLocalProvider({
    operations: {
      ask: async () => {
        throw new Error("owner ask unavailable with private details");
      },
      search: async ({ modelId }) => [{
        modelId,
        id: "answer-evidence",
        text: "Cecilia chose the Personal Card beta boundary after reviewing field evidence.",
        evidenceRefs: [`${modelId}:event:2026-08-09:01`],
        confidence: 0.88,
      }],
    },
  });
  const answer = await grounded.ask("cecilia", "Why that beta boundary?", undefined, {
    displayName: "Cecilia",
  });
  assert.equal(answer.status, "answered");
  assert.equal(answer.refused, false);
  assert.match(answer.answer, /field evidence/u);
  assert.deepEqual(answer.evidenceRefs, ["cecilia:event:2026-08-09:01"]);
  assert.ok(answer.results.every(({ modelId }) => modelId === "cecilia"));

  const empty = createLocalProvider({
    operations: {
      ask: async () => {
        throw new Error("owner ask unavailable");
      },
      search: async () => [],
    },
  });
  const refusal = await empty.ask("cecilia", "Unsupported fact", undefined, {
    displayName: "Cecilia",
  });
  assert.equal(refusal.status, "insufficient_evidence");
  assert.equal(refusal.refused, true);
  assert.deepEqual(refusal.evidenceRefs, []);
  assert.match(refusal.answer, /不会根据空白猜测/u);
});

test("LocalPersomeProvider degrades a failed MCP search to model-bound Snapshot search", async () => {
  const provider = createLocalProvider({
    operations: {
      search: async () => {
        throw new Error("private MCP failure /Users/private/.persome/index.db");
      },
    },
  });
  const results = await provider.search("cecilia", "Personal Card");
  assert.ok(results.length > 0);
  assert.ok(results.every(({ modelId }) => modelId === "cecilia"));
  assert.ok(results.every(({ method }) => method === "snapshot-keyword-search"));
  assert.equal(JSON.stringify(results).includes("/Users/private"), false);
});

test("LocalPersomeProvider resolves original memory/activity records without promoting broken links", async () => {
  const provider = createLocalProvider({
    operations: {
      resolveEvidence: async ({ reference }) => {
        if (reference.endsWith(":memory:mem-01")) {
          return {
            sourceType: "memory",
            recordId: "mem-01",
            originalTime: "2026-08-06T03:20:00.000Z",
            sourceApp: "Notes",
            sourceTitle: "Field note",
            supportedClaims: ["Field observation changes the decision."],
            support: "direct",
            content: { text: "Original memory text" },
          };
        }
        if (reference.endsWith(":activity:activity-01")) {
          return {
            sourceType: "activity",
            recordId: "activity-01",
            occurredAt: "2026-08-07T01:40:00.000Z",
            application: "Figma",
            title: "Prototype review",
            claim: "The prototype was reviewed.",
            relationship: "direct",
            content: { durationMinutes: 38 },
          };
        }
        throw new Error("raw source disconnected");
      },
    },
  });

  const [memory, activity, broken] = await Promise.all([
    provider.getEvidence("cecilia", "cecilia:memory:mem-01"),
    provider.getEvidence("cecilia", "cecilia:activity:activity-01"),
    provider.getEvidence("cecilia", "cecilia:event:2026-08-07:01"),
  ]);
  assert.equal(memory.source.type, "persome-memory");
  assert.equal(memory.source.application, "Notes");
  assert.equal(memory.supports[0].relationship, "direct");
  assert.equal(memory.availability.status, "available");
  assert.equal(activity.source.type, "persome-activity");
  assert.equal(activity.source.originalTime, "2026-08-07T01:40:00.000Z");
  assert.equal(broken.source.type, "derived-summary");
  assert.equal(broken.availability.status, "unavailable");
  assert.equal(broken.availability.reason, "original-source-unavailable");
});

test("Local Evidence resolver rejects a cross-model or malformed resolved record", async () => {
  const provider = createLocalProvider({
    operations: {
      resolveEvidence: async () => ({
        modelId: "lin-demo",
        reference: "lin-demo:memory:foreign",
        sourceType: "memory",
        originalTime: "2026-08-06T03:20:00.000Z",
        content: {},
      }),
    },
  });

  await assert.rejects(
    provider.getEvidence("cecilia", "cecilia:memory:mem-01"),
    (error) => error.code === "INVALID_PROVIDER_RESPONSE",
  );
});

test("Local correction reloads the Snapshot and only succeeds after old conclusions are deprioritized", async () => {
  let snapshot = await loadFixture("cecilia");
  const previousConclusion = snapshot.personalModel.faces[0].text;
  const replacement = "先确认用户授权，再决定是否公开分发。";
  let snapshotLoads = 0;
  const provider = new LocalPersomeProvider({
    modelIds: ["cecilia"],
    loadSnapshot: async () => {
      snapshotLoads += 1;
      return snapshot;
    },
    operations: {
      correct: async () => {
        snapshot = structuredClone(snapshot);
        snapshot.personalModel.faces[0].text = replacement;
        snapshot.personalModel.updatedAt = "2026-08-07T08:05:00.000Z";
        return {
          ok: true,
          receipt: "correction-001",
          affected: [
            {
              reference: "cecilia:face:01",
              previousConclusion,
              replacement,
            },
          ],
        };
      },
    },
  });

  const correction = await provider.correct(
    "cecilia",
    "That conclusion is no longer accurate.",
  );
  assert.equal(correction.status, "applied");
  assert.equal(correction.receipt, "correction-001");
  assert.equal(correction.receiptSource, "runtime");
  assert.equal(correction.affected[0].state, "deprioritized");
  assert.equal(correction.verification.status, "verified");
  assert.equal(correction.verification.refreshed, true);
  assert.equal(correction.verification.oldConclusionDeprioritized, true);
  assert.equal(correction.verification.updatedAt, "2026-08-07T08:05:00.000Z");
  assert.equal(snapshotLoads, 2);
  assert.equal((await provider.getSnapshot("cecilia")).personalModel.faces[0].text, replacement);
});

test("Local correction adapts the pinned Persome 0.3.2 {kind, applied, reason, ok} response", async () => {
  let snapshot = await loadFixture("cecilia");
  const previousConclusion = snapshot.personalModel.faces[0].text;
  const replacement = "用户明确授权后，才把内容带到外部 Agent。";
  const provider = new LocalPersomeProvider({
    modelIds: ["cecilia"],
    loadSnapshot: async () => snapshot,
    operations: {
      correct: async () => {
        snapshot = structuredClone(snapshot);
        snapshot.personalModel.faces[0].text = replacement;
        snapshot.personalModel.updatedAt = "2026-08-07T08:06:00.000Z";
        return {
          kind: "update",
          applied: [
            "superseded user-cecilia.md#entry-01",
            "re-derived schema for user-cecilia.md",
          ],
          reason: "authoritative correction",
          ok: true,
        };
      },
    },
  });

  const correction = await provider.correct(
    "cecilia",
    "Only share my content after explicit authorization.",
  );
  assert.equal(correction.status, "applied");
  assert.equal(correction.receiptSource, "product");
  assert.match(
    correction.receipt,
    /^cecilia:correction:[a-f0-9]{64}$/,
  );
  assert.deepEqual(
    correction.affected.map(({ previousConclusion: value, state }) => ({
      value,
      state,
    })),
    [{ value: previousConclusion, state: "deprioritized" }],
  );
  assert.equal(correction.verification.oldConclusionDeprioritized, true);
  assert.equal(JSON.stringify(await provider.getSnapshot("cecilia")).includes(previousConclusion), false);
});

test("Local correction never returns success when receipt, affected state, or propagation is missing", async () => {
  const original = await loadFixture("cecilia");
  const previousConclusion = original.personalModel.faces[0].text;
  for (const operationResult of [
    { ok: true },
    {
      kind: "update",
      applied: ["superseded user-cecilia.md#entry-01"],
      reason: "authoritative correction",
      ok: true,
    },
    {
      ok: true,
      receipt: "correction-stale",
      affected: [
        {
          reference: "cecilia:face:01",
          previousConclusion,
        },
      ],
    },
  ]) {
    const provider = new LocalPersomeProvider({
      modelIds: ["cecilia"],
      loadSnapshot: async () => original,
      operations: { correct: async () => operationResult },
    });
    await assert.rejects(
      provider.correct("cecilia", "Correction"),
      (error) => error.code === "CORRECTION_VERIFICATION_FAILED",
    );
  }
});

test("RemotePersonalModelProvider sends Bearer auth and binds every operation", async () => {
  const requests = [];
  const provider = createRemoteProvider({
    fetchImpl: createRemoteFetch({ requests }),
  });

  const [context, search, evidence, correction, connector, reports] =
    await Promise.all([
      provider.getCurrentContext("lin-demo"),
      provider.search("lin-demo", "night"),
      provider.getEvidence(
        "lin-demo",
        "lin-demo:event:2026-08-07:01",
      ),
      provider.correct("lin-demo", "correction"),
      provider.connectAgent("lin-demo", "codex"),
      provider.listAgentReports("lin-demo"),
    ]);

  assert.equal(context.modelId, "lin-demo");
  assert.ok(search.every(({ modelId }) => modelId === "lin-demo"));
  assert.equal(evidence.modelId, "lin-demo");
  assert.equal(correction.modelId, "lin-demo");
  assert.equal(correction.status, "accepted");
  assert.equal(correction.verification.status, "unverified");
  assert.equal(connector.modelId, "lin-demo");
  assert.ok(reports.every(({ modelId }) => modelId === "lin-demo"));
  assert.ok(
    requests.every(
      ({ authorization }) => authorization === "Bearer test-token",
    ),
  );
  const remoteSearch = requests.find(({ path }) => path.endsWith("/search"));
  assert.deepEqual(JSON.parse(remoteSearch.body), { query: "night" });
});

test("RemotePersonalModelProvider supports caller abort and timeout", async () => {
  const hangingFetch = (_url, { signal }) =>
    new Promise((_resolve, reject) => {
      signal.addEventListener(
        "abort",
        () => reject(new DOMException("aborted", "AbortError")),
        { once: true },
      );
    });

  const timeoutProvider = createRemoteProvider({
    fetchImpl: hangingFetch,
    timeoutMs: 10,
  });
  await assert.rejects(
    timeoutProvider.getSnapshot("cecilia"),
    (error) => error.code === "PROVIDER_TIMEOUT",
  );

  const callerController = new AbortController();
  const abortedProvider = createRemoteProvider({
    fetchImpl: hangingFetch,
    timeoutMs: 1_000,
  });
  const request = abortedProvider.getSnapshot("cecilia", undefined, {
    signal: callerController.signal,
  });
  callerController.abort();
  await assert.rejects(request, (error) => error.code === "PROVIDER_ABORTED");
});

test("RemotePersonalModelProvider never forwards remote error bodies", async () => {
  const remoteSecret =
    "raw remote MCP error /Users/private/.persome/index.db token=secret";
  const provider = createRemoteProvider({
    fetchImpl: async () =>
      jsonResponse({ error: remoteSecret }, { status: 500 }),
  });

  await assert.rejects(provider.getSnapshot("cecilia"), (error) => {
    assert.equal(error.code, "REMOTE_PROVIDER_ERROR");
    assert.equal(error.message.includes(remoteSecret), false);
    assert.equal(JSON.stringify(error).includes(remoteSecret), false);
    return true;
  });
});

test("RemotePersonalModelProvider rejects cross-model responses", async () => {
  const cecilia = await loadFixture("cecilia");
  const snapshotProvider = createRemoteProvider({
    fetchImpl: async () => jsonResponse(cecilia),
  });

  await assert.rejects(
    snapshotProvider.getSnapshot("lin-demo"),
    (error) => error.code === "MODEL_ID_MISMATCH",
  );

  const evidenceProvider = createRemoteProvider({
    fetchImpl: async () =>
      jsonResponse({
        modelId: "cecilia",
        reference: "cecilia:event:2026-08-07:01",
        content: {},
      }),
  });
  await assert.rejects(
    evidenceProvider.getEvidence(
      "lin-demo",
      "lin-demo:event:2026-08-07:01",
    ),
    (error) => error.code === "MODEL_ID_MISMATCH",
  );

  const changedReferenceProvider = createRemoteProvider({
    fetchImpl: async () =>
      jsonResponse({
        modelId: "lin-demo",
        reference: "lin-demo:event:different",
        content: {},
      }),
  });
  await assert.rejects(
    changedReferenceProvider.getEvidence(
      "lin-demo",
      "lin-demo:event:2026-08-07:01",
    ),
    (error) => error.code === "EVIDENCE_RESPONSE_MISMATCH",
  );
});

test("ProviderRegistry is an exact allowlist and rejects path injection", async () => {
  const fixtureProvider = new FixtureProvider();
  const registry = new ProviderRegistry({
    cecilia: fixtureProvider,
    "lin-demo": fixtureProvider,
  });

  assert.equal(registry.resolve("cecilia"), fixtureProvider);
  assert.equal(assertPersonalModelProvider(registry.resolve("lin-demo")), fixtureProvider);
  assert.deepEqual(
    (await registry.listModels()).map(({ id }) => id),
    ["cecilia", "lin-demo"],
  );

  for (const invalidId of [
    "../cecilia",
    "lin/demo",
    "%2e%2e%2fcecilia",
    "lin..demo",
  ]) {
    assert.throws(
      () => registry.resolve(invalidId),
      (error) => error.code === "INVALID_MODEL_ID",
    );
  }
  assert.throws(
    () => registry.resolve("unknown-model"),
    (error) => error.code === "MODEL_NOT_FOUND",
  );
});
