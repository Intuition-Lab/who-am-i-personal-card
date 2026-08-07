import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { appendFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

function argument(name, fallback = "") {
  const index = process.argv.indexOf(name);
  return String(index >= 0 ? process.argv[index + 1] || "" : fallback);
}

const AGENT = argument("--agent", process.env.WHOAMI_AGENT || "agent").slice(0, 40);
const MODEL_ID = argument("--model", "cecilia");
const CONNECTOR_SESSION_ID = argument("--connector-session", "cs_local_legacy");
const GRANT_ID = argument("--grant", "owner_cecilia_local");
const RUNTIME_DATA_ROOT = argument(
  "--runtime-root",
  resolve(process.env.HOME || "", "Library/Application Support/Who Am I/runtime"),
);
const PERSOME_ROOT = argument(
  "--persome-root",
  resolve(process.env.HOME || "", ".persome"),
);
if (
  !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(MODEL_ID)
  || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(AGENT)
  || !/^cs_[A-Za-z0-9_-]{8,160}$/.test(CONNECTOR_SESSION_ID)
  || !/^[A-Za-z0-9_-]{4,180}$/.test(GRANT_ID)
) {
  process.stderr.write("Who Am I MCP: invalid model-bound Connector identity.\n");
  process.exit(1);
}
const LOG_FILE = resolve(
  RUNTIME_DATA_ROOT,
  "models",
  MODEL_ID,
  "connectors",
  AGENT,
  "sessions",
  CONNECTOR_SESSION_ID,
  "events.jsonl",
);
const PERSOME = resolve(PERSOME_ROOT, "venv/bin/persome");

if (!existsSync(PERSOME)) {
  process.stderr.write("Who Am I MCP: Persome is not installed.\n");
  process.exit(1);
}

const child = spawn(PERSOME, ["mcp"], {
  stdio: ["pipe", "pipe", "pipe"],
  env: { ...process.env, PYTHONUNBUFFERED: "1" },
});
const pending = new Map();
let requestBuffer = "";
let responseBuffer = "";

function cleanText(value, max = 88) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .replace(/[^\p{L}\p{N}\s·，。！？、“”「」:：/_.-]/gu, "")
    .trim()
    .slice(0, max);
}

function summarize(tool, args) {
  if (tool === "search") return `搜索「${cleanText(args?.query || "个人记忆", 58)}」`;
  if (tool === "search_captures") return `回看屏幕记录「${cleanText(args?.query || "最近片段", 58)}」`;
  if (tool === "verify_fact") return `核对「${cleanText(args?.claim || "一条判断", 58)}」`;
  if (tool === "entity_graph") return `查看 ${cleanText(args?.name || "人物", 48)} 的关系`;
  if (tool === "current_context") return "读取当前上下文";
  if (tool === "recent_activity") return "回看最近活动";
  if (tool === "behavior_patterns") return "读取个人行为模式";
  if (tool === "list_memories") return "浏览记忆目录";
  if (tool === "read_memory") return `打开记忆「${cleanText(args?.path || "一条记录", 58)}」`;
  if (tool === "read_receipt") return `打开证据「${cleanText(args?.entry_id || "一条回执", 58)}」`;
  if (tool === "resolve_evidence") return `追溯证据「${cleanText(args?.reference || "一条依据", 58)}」`;
  if (tool === "get_pending_model_work") return "检查尚未沉淀的记录";
  if (tool === "correct_memory") return "更正了一条模型判断";
  if (tool === "remember") return "记住了一条新的发现";
  return `调用 ${cleanText(tool || "Persome", 56)}`;
}

function parseResultData(result) {
  const direct = result?.structuredContent?.result;
  if (direct && typeof direct === "object") return direct;
  const text = result?.content?.find((item) => item?.type === "text")?.text;
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return { text };
  }
}

function readableItem(item, max = 180) {
  if (typeof item === "string") return cleanText(item, max);
  if (!item || typeof item !== "object") return "";
  return cleanText(
    item.text
      || item.summary
      || item.title
      || item.name
      || item.content
      || item.body
      || item.description
      || item.narrative
      || "",
    max
  );
}

function firstArray(data, names) {
  for (const name of names) {
    if (Array.isArray(data?.[name])) return data[name];
    if (Array.isArray(data?.result?.[name])) return data.result[name];
  }
  return [];
}

function describeResult(tool, result) {
  const data = parseResultData(result);
  const details = [];
  let interpretation = "";

  if (tool === "behavior_patterns") {
    const patterns = firstArray(data, ["faces", "patterns", "behavior_patterns", "promoted", "regularities"]);
    for (const pattern of patterns.slice(0, 3)) {
      const text = readableItem(pattern);
      if (text) details.push(text);
    }
    interpretation = readableItem(data?.root?.narrative || data?.root || data?.narrative, 240);
  } else if (tool === "search" || tool === "search_captures" || tool === "recent_activity") {
    const hits = firstArray(data, ["hits", "results", "captures", "events", "items", "activities"]);
    for (const hit of hits.slice(0, 3)) {
      const text = readableItem(hit);
      if (text) details.push(text);
    }
  } else if (tool === "current_context") {
    const context = data?.current || data?.context || data;
    const text = readableItem(context, 220);
    if (text) details.push(text);
  } else if (tool === "list_memories") {
    const memories = firstArray(data, ["memories", "files", "paths", "items"]);
    for (const memory of memories.slice(0, 4)) {
      const text = readableItem(memory, 120);
      if (text) details.push(text);
    }
  } else if (tool === "read_memory" || tool === "read_receipt" || tool === "resolve_evidence") {
    const text = readableItem(data?.entry || data?.memory || data?.evidence || data, 220);
    if (text) details.push(text);
  }

  return {
    details: [...new Set(details)].slice(0, 3),
    interpretation,
  };
}

function evidenceReceipt(value) {
  const text = JSON.stringify(value || {});
  const receipt = text.match(/⟨([^⟩]{4,160})⟩/)?.[1]
    || text.match(/"(?:entry_id|receipt)"\s*:\s*"([^"]{4,160})"/i)?.[1]
    || text.match(/\b(?:face|pattern|point|line|capture|event|entry)[_-](?=[A-Za-z0-9_.:-]*\d)[A-Za-z0-9_.:-]{3,120}\b/i)?.[0];
  return receipt ? cleanText(receipt, 150) : "";
}

function stableEvidence(agent, tool, summary, at) {
  return `${MODEL_ID}:mcp:${createHash("sha256")
    .update(`${MODEL_ID}|${CONNECTOR_SESSION_ID}|${agent}|${tool}|${summary}|${at}`)
    .digest("hex")
    .slice(0, 20)}`;
}

function stableEventHash(record) {
  return createHash("sha256").update(JSON.stringify({
    modelId: record.modelId,
    connectorId: record.connectorId,
    sessionId: record.sessionId,
    grantId: record.grantId,
    eventType: record.eventType,
    requestId: record.requestId,
    tool: record.tool,
    receipt: record.receipt,
    summary: record.summary,
    occurredAt: record.occurredAt,
    durationMs: record.durationMs,
  })).digest("hex");
}

async function record(request, response) {
  const endedAt = new Date();
  const localDay = [
    endedAt.getFullYear(),
    String(endedAt.getMonth() + 1).padStart(2, "0"),
    String(endedAt.getDate()).padStart(2, "0"),
  ].join("-");
  const rawReceipt = evidenceReceipt(response?.result);
  const receipt = rawReceipt.startsWith(`${MODEL_ID}:`)
    ? rawReceipt
    : rawReceipt
      ? `${MODEL_ID}:receipt:${createHash("sha256").update(rawReceipt).digest("hex").slice(0, 20)}`
      : stableEvidence(AGENT, request.tool, request.summary, request.startedAt);
  const description = describeResult(request.tool, response?.result);
  const core = {
    modelId: MODEL_ID,
    connectorId: AGENT,
    sessionId: CONNECTOR_SESSION_ID,
    grantId: GRANT_ID,
    eventType: "tools/call",
    requestId: request.requestId,
    tool: request.tool,
    receipt,
    summary: request.summary,
    occurredAt: endedAt.toISOString(),
    durationMs: Math.max(0, Date.now() - request.startedAt),
  };
  const event = {
    eventId: stableEventHash(core),
    ...core,
    id: stableEvidence(AGENT, request.tool, request.summary, request.startedAt),
    at: core.occurredAt,
    day: localDay,
    agent: AGENT,
    evidenceId: receipt,
    receipt,
    status: response?.error ? "error" : "ok",
    details: description.details,
    interpretation: description.interpretation,
  };
  await mkdir(dirname(LOG_FILE), { recursive: true });
  await appendFile(LOG_FILE, `${JSON.stringify(event)}\n`, "utf8");
}

function inspectRequests(chunk) {
  requestBuffer += chunk.toString("utf8");
  const lines = requestBuffer.split(/\r?\n/);
  requestBuffer = lines.pop() || "";
  for (const line of lines) {
    let message;
    try { message = JSON.parse(line); } catch { continue; }
    if (message?.method !== "tools/call" || message.id == null) continue;
    const tool = String(message.params?.name || "persome");
    pending.set(String(message.id), {
      requestId: message.id,
      tool,
      summary: summarize(tool, message.params?.arguments || {}),
      startedAt: Date.now(),
    });
  }
}

function inspectResponses(chunk) {
  responseBuffer += chunk.toString("utf8");
  const lines = responseBuffer.split(/\r?\n/);
  responseBuffer = lines.pop() || "";
  for (const line of lines) {
    let message;
    try { message = JSON.parse(line); } catch { continue; }
    if (message?.id == null) continue;
    const request = pending.get(String(message.id));
    if (!request) continue;
    pending.delete(String(message.id));
    record(request, message).catch(() => {});
  }
}

process.stdin.on("data", (chunk) => {
  inspectRequests(chunk);
  child.stdin.write(chunk);
});
process.stdin.on("end", () => child.stdin.end());
child.stdout.on("data", (chunk) => {
  inspectResponses(chunk);
  process.stdout.write(chunk);
});
child.stderr.on("data", (chunk) => process.stderr.write(chunk));
child.on("exit", (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 0);
});
child.on("error", (error) => {
  process.stderr.write(`Who Am I MCP: ${error.message}\n`);
  process.exit(1);
});
