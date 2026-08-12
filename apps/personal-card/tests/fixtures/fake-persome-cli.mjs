#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { createInterface } from "node:readline";

const command = process.argv[2] || "";
const defaultPersona = {
  key: "MIRA_ONLY",
  root: "MIRA_ONLY_ROOT_6C21",
  face: "MIRA_ONLY_FACE_6C21",
  rewind: "MIRA_ONLY_REWIND_6C21",
  search: "MIRA_ONLY_SEARCH_6C21",
  build: "MIRA_ONLY_BUILD_6C21",
};
let persona = defaultPersona;
let scenarioPath = "";
try {
  scenarioPath = path.resolve(
    process.env.PERSOME_ROOT || "",
    "fake-scenario.json",
  );
  persona = { ...defaultPersona, ...JSON.parse(readFileSync(scenarioPath, "utf8")) };
} catch {
  // Tests without a scenario use the stable Mira fixture.
}
const correctionStatePath = process.env.PERSOME_ROOT
  ? path.resolve(process.env.PERSOME_ROOT, "fake-correction-applied")
  : "";
const correctionApplied =
  correctionStatePath.length > 0 && existsSync(correctionStatePath);
const previousFace =
  `${persona.face} returns to the field before making a decision.`;
const correctedFace = persona.correctedFace ||
  `${persona.face} now verifies authorization before making a decision.`;
const rewindTimestamp = persona.rewindTimestamp || "2026-08-07T09:00";

if (command === "--help") {
  process.stdout.write("fake persome\n");
  process.exit(0);
}

if (command === "status" || (command === "model" && process.argv[3] === "status")) {
  process.stdout.write("model: ready\n");
  process.exit(0);
}

if (command !== "mcp") {
  process.stderr.write("unsupported fake command\n");
  process.exit(2);
}

const toolResults = {
  get_model_snapshot: {
    projection_schema_version: 1,
    model_schema_version: 1,
    section: "overview",
    build: {
      status: "complete",
      trigger: "test",
      build_id: persona.build,
    },
    model_stats: { roots: 1, faces: 1, volumes: 0, points: 2, lines: 1 },
    root: { signature: persona.root },
    faces: [],
    volumes: [],
  },
  list_memories: {
    count: 2,
    files: [{
      path: "memory/mira.md",
      updated: correctionApplied
        ? persona.correctedMemoryUpdated || "2026-08-07T02:05:00.000Z"
        : persona.memoryUpdated || "2026-08-07T02:00:00.000Z",
    }],
  },
  behavior_patterns: {
    root: { signature: `${persona.root}. Builds calm tools from field evidence.` },
    faces: [
      {
        signature: correctionApplied ? correctedFace : previousFace,
        observations: 7,
        confidence: 0.94,
      },
    ],
  },
  recent_activity: {
    entries: [
      {
        id: persona.rewind,
        path: "event-2026-08-07.md",
        timestamp: rewindTimestamp,
        content:
          `${persona.rewind} (09:00–09:40)\n\n${persona.rewind} reviewed a quiet navigation prototype in the field.\n\n- [09:00–09:40, Notes] ${persona.rewind} notes`,
      },
    ],
  },
  current_context: {
    recent_timeline_blocks: [],
  },
  correct_memory: {
    ok: true,
  },
  remember: {
    ok: true,
    memory_id: "fake-jot-memory",
  },
};

function modelSnapshotResult(args = {}) {
  if (args.section !== "faces") return toolResults.get_model_snapshot;
  return {
    ...toolResults.get_model_snapshot,
    section: "faces",
    items: [
      {
        id: "mira-face",
        signature: correctionApplied ? correctedFace : previousFace,
        observations: 7,
        confidence: 0.94,
        status: "active",
        member_receipts: ["⟨mem-01:user-mira.md⟩"],
        source_receipts: ["⟨mem-01:user-mira.md⟩"],
      },
    ],
    include_evidence_refs: args.include_evidence_refs === true,
  };
}

function searchResult(args = {}) {
  if (
    persona.emptySearch === true
    || (persona.emptySearchQuery && String(args.query).includes(persona.emptySearchQuery))
  ) {
    return { query: args.query, results: [] };
  }
  const configured = Array.isArray(persona.searchHits)
    ? persona.searchHits
    : [
        {
          id: "mira-search",
          content: persona.search,
          path: "memory/mira.md",
        },
      ];
  const topK = Number.isInteger(args.top_k) ? args.top_k : configured.length;
  return {
    query: args.query,
    results: configured.slice(0, topK),
  };
}

function applyCorrection(args = {}) {
  const correction = String(args.correction || "").trim();
  if (correction && scenarioPath) {
    persona = {
      ...persona,
      search: persona.correctedSearch || correction,
      searchHits: [
        {
          id: persona.correctedSearchId || "corrected-memory",
          content: persona.correctedSearch || correction,
          path: persona.correctedSearchPath || "memory/corrected.md",
          timestamp: persona.correctedTimestamp || "2026-08-09T09:00:00+08:00",
          confidence: 1,
        },
      ],
    };
    writeFileSync(scenarioPath, JSON.stringify(persona));
  }
  try {
    if (!correction || !correctionStatePath) {
      throw new Error("missing correction state");
    }
    writeFileSync(correctionStatePath, "applied\n", { mode: 0o600 });
    return {
      kind: "update",
      applied: [
        "superseded user-mira.md#fake-entry-01",
        "re-derived schema for user-mira.md",
      ],
      reason: "authoritative correction",
      ok: true,
    };
  } catch {
    return { kind: "error", applied: [], reason: "not applied", ok: false };
  }
}

function resolveEvidenceResult(reference) {
  if (reference === persona.rewind) {
    return {
      reference,
      canonical_reference: reference,
      kind: "activity",
      id: reference,
      status: "historical",
      label: "Field prototype review",
      summary: `${persona.rewind} reviewed a quiet navigation prototype in the field.`,
      timestamp: rewindTimestamp,
      path: reference,
      metadata: { source_kind: "entry", app_name: "Notes" },
      sources: [],
      context: [],
      history: [],
    };
  }
  if (reference === "mira-face") {
    return {
      reference,
      canonical_reference: reference,
      kind: "face",
      id: reference,
      status: "active",
      label: "Field-first decision style",
      summary: correctionApplied ? correctedFace : previousFace,
      timestamp: null,
      path: null,
      metadata: { confidence: 0.94, observations: 7 },
      sources: [
        {
          relation: "direct_evidence",
          kind: "memory",
          id: "mem-01",
          reference: "⟨mem-01:user-mira.md⟩",
          label: "Original field note",
          timestamp: "2026-08-06T03:20:00.000Z",
        },
      ],
      context: [],
      history: [],
    };
  }
  const memory = (Array.isArray(persona.searchHits) ? persona.searchHits : [])
    .find((hit) => String(hit.id || "") === reference);
  if (memory) {
    return {
      reference,
      canonical_reference: reference,
      kind: "memory",
      id: reference,
      status: "available",
      label: path.basename(String(memory.path || reference)),
      summary: String(memory.content || memory.text || ""),
      timestamp: memory.timestamp || null,
      path: memory.path || null,
      metadata: { source_kind: "memory", app_name: "Persome" },
      sources: [],
      context: [],
      history: [],
    };
  }
  return {
    reference,
    canonical_reference: reference,
    kind: "unknown",
    id: reference,
    status: "missing",
    label: reference,
    summary: "",
    timestamp: null,
    path: null,
    metadata: { reason: "source_not_found_or_retained" },
    sources: [],
    context: [],
    history: [],
  };
}

const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    return;
  }
  if (request.id == null) return;
  let result = {};
  if (request.method === "initialize") {
    result = {
      protocolVersion: "2025-03-26",
      capabilities: { tools: {} },
      serverInfo: { name: "fake-persome", version: "0.3.2" },
    };
  } else if (request.method === "tools/call") {
    const name = request.params?.name;
    const args = request.params?.arguments || {};
    if (
      name === "search"
      && persona.searchErrorQuery
      && String(args.query).includes(persona.searchErrorQuery)
    ) {
      process.stdout.write(`${JSON.stringify({
        jsonrpc: "2.0",
        id: request.id,
        error: { code: -32000, message: "private fake MCP search failure" },
      })}\n`);
      return;
    }
    const toolResult = name === "search"
      ? searchResult(args)
      : name === "correct_memory"
        ? applyCorrection(args)
        : name === "resolve_evidence"
          ? resolveEvidenceResult(String(args.reference || ""))
          : name === "get_model_snapshot"
            ? modelSnapshotResult(args)
          : toolResults[name] || {};
    result = {
      structuredContent: {
        result: toolResult,
      },
      content: [
        {
          type: "text",
          text: JSON.stringify(toolResult),
        },
      ],
    };
  }
  process.stdout.write(`${JSON.stringify({
    jsonrpc: "2.0",
    id: request.id,
    result,
  })}\n`);
});
