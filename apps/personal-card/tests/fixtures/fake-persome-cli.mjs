#!/usr/bin/env node
import { readFileSync } from "node:fs";
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
try {
  const scenarioPath = path.resolve(
    process.env.PERSOME_ROOT || "",
    "fake-scenario.json",
  );
  persona = { ...defaultPersona, ...JSON.parse(readFileSync(scenarioPath, "utf8")) };
} catch {
  // Tests without a scenario use the stable Mira fixture.
}

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
      updated: persona.memoryUpdated || "2026-08-07T02:00:00.000Z",
    }],
  },
  behavior_patterns: {
    root: { signature: `${persona.root}. Builds calm tools from field evidence.` },
    faces: [
      {
        id: "mira-face",
        signature: `${persona.face} returns to the field before making a decision.`,
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
        timestamp: "2026-08-07T09:00:00+08:00",
        content:
          `${persona.rewind} (09:00–09:40)\n\n${persona.rewind} reviewed a quiet navigation prototype in the field.\n\n- [09:00–09:40, Notes] ${persona.rewind} notes`,
      },
    ],
  },
  current_context: {
    recent_timeline_blocks: [],
  },
  search: {
    hits: [
      {
        id: "mira-search",
        content: persona.search,
        path: "memory/mira.md",
      },
    ],
  },
  correct_memory: {
    ok: true,
  },
};

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
    result = {
      structuredContent: {
        result: toolResults[name] || {},
      },
      content: [
        {
          type: "text",
          text: JSON.stringify(toolResults[name] || {}),
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
