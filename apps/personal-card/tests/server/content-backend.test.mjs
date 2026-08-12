import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { chmod, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { LocalPersomeContentBackend } from "../../src/content/personal-model-content-backend.mjs";

const projectRoot = new URL("../../", import.meta.url);
const fakePersome = fileURLToPath(
  new URL("../fixtures/fake-persome-cli.mjs", import.meta.url),
);

async function waitForServer(baseUrl, child) {
  for (let attempt = 0; attempt < 160; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`Content backend server exited with ${child.exitCode}`);
    }
    try {
      const response = await fetch(baseUrl, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Startup is asynchronous.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("Timed out waiting for the content backend server.");
}

async function stopServer(child) {
  if (child.exitCode === null) child.kill("SIGTERM");
  if (child.exitCode === null) await once(child, "exit");
}

test("local content search skips unused Runtime chain narration", async () => {
  let searchArguments;
  let closeCalls = 0;
  const backend = new LocalPersomeContentBackend({
    connectPersome: async () => ({
      callTool: async (name, args) => {
        assert.equal(name, "search");
        searchArguments = args;
        return {
          structuredContent: {
            result: JSON.stringify({ query: args.query, results: [] }),
          },
        };
      },
      close: () => {
        closeCalls += 1;
      },
    }),
  });

  await backend.search({ modelId: "owner", query: "release evidence" });

  assert.equal(searchArguments.include_chains, false);
  assert.equal(searchArguments.include_bodies, true);
  assert.equal(closeCalls, 1);
});

test("local content backend provides semantic search, grounded ask, refusal, fallback, and fresh corrections", async (t) => {
  await chmod(fakePersome, 0o755);
  const root = await mkdtemp(join(tmpdir(), "whoami-content-backend-"));
  const cardDataDir = join(root, "card");
  const persomeRoot = join(root, "persome");
  await mkdir(persomeRoot, { recursive: true });
  const firstMemory = "The full Personal Model beta memory says the owner chose a two-day content backend after validating field evidence.";
  const secondMemory = "A separate observed memory records that every factual answer must expose model-bound evidence references.";
  await writeFile(join(persomeRoot, "fake-scenario.json"), JSON.stringify({
    root: "FALLBACK_MARKER Personal Card root",
    face: "CONTENT_BACKEND_FACE",
    rewind: "CONTENT_BACKEND_REWIND",
    search: firstMemory,
    searchErrorQuery: "FALLBACK_MARKER",
    emptySearchQuery: "NO_EVIDENCE",
    correctedSearch: "CORRECTED_MEMORY_LATEST_91B4",
    searchHits: [
      {
        id: "semantic-beta-1",
        content: firstMemory,
        path: "project-personal-model.md",
        timestamp: "2026-08-08T18:30:00+08:00",
        age_days: 1,
        confidence: 0.94,
      },
      {
        id: "semantic-beta-2",
        content: secondMemory,
        path: "event-2026-08-08.md",
        timestamp: "2026-08-08T20:00:00+08:00",
        confidence: 0.87,
      },
      {
        id: "semantic-beta-1",
        content: firstMemory,
        path: "project-personal-model.md",
      },
    ],
  }));

  let ownerAskCalls = 0;
  const ownerAsk = createServer(async (req, res) => {
    ownerAskCalls += 1;
    for await (const _chunk of req) {
      // Drain the request before responding.
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({
      ok: true,
      answer: "OWNER_ASK_GROUNDED_ANSWER",
    }));
  });
  await new Promise((resolve) => ownerAsk.listen(0, "127.0.0.1", resolve));
  t.after(() => ownerAsk.close());
  const ownerAskPort = ownerAsk.address().port;

  const port = 29000 + (process.pid % 1000);
  const baseUrl = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, ["persome-card-server.mjs"], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NODE_ENV: "production",
      WHOAMI_DEV_MODE: "0",
      WHOAMI_TEST_MODE: "1",
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_CARD_DATA_DIR: cardDataDir,
      PERSOME_ROOT: persomeRoot,
      PERSOME_CLI: fakePersome,
      WHO_AM_I_URL: `http://127.0.0.1:${ownerAskPort}`,
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
  t.after(async () => stopServer(child));
  await waitForServer(baseUrl, child);

  let cookie = "";
  async function request(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (cookie) headers.cookie = cookie;
    const response = await fetch(`${baseUrl}${path}`, { ...options, headers });
    const setCookie = response.headers.get("set-cookie");
    if (setCookie) cookie = setCookie.split(";", 1)[0];
    return { status: response.status, body: await response.json() };
  }
  const post = (path, body) => request(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  const profile = await post("/api/setup/profile", {
    displayName: "Content Owner",
    handle: "@content-owner",
    tagline: "Content backend beta",
    description: "A model-bound content backend owner.",
  });
  assert.equal(profile.status, 200);
  const modelId = profile.body.profile.modelId;
  const bootstrap = await request("/api/model/bootstrap");
  assert.equal(bootstrap.status, 200);
  assert.equal(bootstrap.body.modelId, modelId);

  const search = await post("/api/model/search", {
    query: "semantic beta evidence",
    top_k: 3,
    breadth: 0.4,
  });
  assert.equal(search.status, 200);
  assert.equal(search.body.status, "results");
  assert.equal(search.body.results.length, 2);
  assert.equal(search.body.results[0].body, firstMemory);
  assert.equal(search.body.results[0].source.path, "project-personal-model.md");
  assert.equal(search.body.results[0].contentType, "observed");
  assert.equal(search.body.results[0].confidence, 0.94);
  assert.equal(search.body.results[0].method, "persome-mcp-search");
  assert.equal(search.body.method, "persome-mcp-search");
  assert.equal(search.body.degraded, false);
  assert.equal(search.body.degradationReason, null);
  assert.ok(search.body.results.every((result) => result.modelId === modelId));
  assert.ok(search.body.results.every((result) =>
    result.evidenceRefs.every((reference) => reference.startsWith(`${modelId}:`))
  ));
  assert.equal(new Set(search.body.results.map(({ id }) => id)).size, 2);
  assert.ok(search.body.sourceRefs.every((sourceRef) =>
    sourceRef.startsWith(`${modelId}:`)
  ));

  const topOne = await post("/api/model/search", {
    query: "semantic beta evidence",
    top_k: 1,
  });
  assert.equal(topOne.status, 200);
  assert.equal(topOne.body.results.length, 1);
  const invalidTopK = await post("/api/model/search", {
    query: "semantic beta evidence",
    top_k: 51,
  });
  assert.equal(invalidTopK.status, 400);
  assert.equal(invalidTopK.body.code, "INVALID_SEARCH_TOP_K");

  const reference = search.body.results[0].evidenceRefs[0];
  const evidence = await request(
    `/api/model/evidence/${encodeURIComponent(reference)}`,
  );
  assert.equal(evidence.status, 200);
  assert.equal(evidence.body.evidence.modelId, modelId);
  assert.equal(evidence.body.evidence.reference, reference);
  assert.equal(evidence.body.evidence.source.type, "persome-memory");
  assert.equal(
    evidence.body.evidence.source.originalTime,
    "2026-08-08T10:30:00.000Z",
  );
  assert.equal(evidence.body.evidence.supports[0].relationship, "direct");
  assert.equal(evidence.body.evidence.availability.status, "available");
  assert.equal(evidence.body.evidence.content.text, firstMemory);
  assert.equal(evidence.body.evidence.content.resolved.status, "available");

  const ask = await post("/api/model/ask", {
    question: "Why was this beta boundary chosen?",
    top_k: 2,
  });
  assert.equal(ask.status, 200);
  assert.equal(ask.body.status, "answered");
  assert.equal(ask.body.refused, false);
  assert.equal(ask.body.answer, "OWNER_ASK_GROUNDED_ANSWER");
  assert.equal(ask.body.method, "owner-ask");
  assert.ok(ask.body.evidenceRefs.length > 0);
  assert.ok(ask.body.results.every((result) => result.modelId === modelId));
  assert.equal(ownerAskCalls, 1);

  const refused = await post("/api/model/ask", {
    question: "NO_EVIDENCE unsupported claim",
  });
  assert.equal(refused.status, 200);
  assert.equal(refused.body.status, "insufficient_evidence");
  assert.equal(refused.body.refused, true);
  assert.deepEqual(refused.body.evidenceRefs, []);
  assert.doesNotMatch(refused.body.answer, /OWNER_ASK_GROUNDED_ANSWER/u);

  const noResults = await post("/api/model/search", {
    query: "NO_EVIDENCE missing",
  });
  assert.equal(noResults.body.status, "no_results");
  assert.deepEqual(noResults.body.results, []);

  const degraded = await post("/api/model/search", {
    query: "FALLBACK_MARKER",
  });
  assert.equal(degraded.status, 200);
  assert.equal(degraded.body.status, "results");
  assert.ok(degraded.body.results.every(({ modelId: resultModelId }) =>
    resultModelId === modelId
  ));
  assert.ok(degraded.body.results.every(({ method }) =>
    method === "snapshot-keyword-search"
  ));
  assert.equal(degraded.body.method, "snapshot-keyword-search");
  assert.equal(degraded.body.degraded, true);
  assert.match(degraded.body.degradationReason, /关键词匹配/u);
  assert.doesNotMatch(JSON.stringify(degraded.body), /private fake MCP/u);

  const correction = await post("/api/model/correct", {
    correction: "The latest corrected beta memory.",
  });
  assert.equal(correction.status, 200);
  assert.equal(correction.body.status, "applied");
  assert.equal(correction.body.receiptSource, "product");
  assert.equal(correction.body.verification.status, "verified");
  assert.equal(
    correction.body.verification.oldConclusionDeprioritized,
    true,
  );
  const freshSearch = await post("/api/model/search", {
    query: "latest corrected beta",
  });
  assert.equal(freshSearch.status, 200);
  assert.match(freshSearch.body.results[0].text, /CORRECTED_MEMORY_LATEST_91B4/u);
  const callsBeforeFreshAsk = ownerAskCalls;
  const freshAsk = await post("/api/model/ask", {
    question: "What is the latest corrected beta memory?",
  });
  assert.equal(freshAsk.status, 200);
  assert.equal(freshAsk.body.method, "retrieval-grounded");
  assert.match(freshAsk.body.answer, /CORRECTED_MEMORY_LATEST_91B4/u);
  assert.equal(ownerAskCalls, callsBeforeFreshAsk);

  const override = await post("/api/model/search?modelId=foreign-model", {
    query: "latest",
  });
  assert.equal(override.status, 403);
  assert.equal(override.body.code, "MODEL_OVERRIDE_FORBIDDEN");
});
