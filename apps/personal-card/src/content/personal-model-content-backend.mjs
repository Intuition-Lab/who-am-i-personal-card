import { createHash } from "node:crypto";
import { basename } from "node:path";

import { PersonalModelProviderError } from "../contracts/personal-model-provider.mjs";

const DEFAULT_TOP_K = 10;
const MAX_TOP_K = 50;
const MAX_RESULT_BODY_CHARS = 20_000;
const CONTENT_TYPES = new Set(["observed", "inferred", "generated"]);

function providerError(code, message, status = 400) {
  return new PersonalModelProviderError(code, message, { status });
}

function cleanText(value, maximum = MAX_RESULT_BODY_CHARS) {
  const text = String(value ?? "")
    .replace(/\u0000/gu, "")
    .replace(/\r\n?/gu, "\n")
    .trim();
  if (text.length <= maximum) return text;
  return `${text.slice(0, maximum - 1).trimEnd()}…`;
}

function optionalDate(value, field) {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    throw providerError(
      "INVALID_SEARCH_FILTER",
      `${field} must be a valid date-time.`,
    );
  }
  return new Date(value).toISOString();
}

function optionalPaths(value) {
  if (value === undefined || value === null) return undefined;
  if (
    !Array.isArray(value)
    || value.length > 32
    || value.some((path) =>
      typeof path !== "string"
      || path.trim().length === 0
      || path.length > 512
    )
  ) {
    throw providerError(
      "INVALID_SEARCH_FILTER",
      "paths must be an array of non-empty source patterns.",
    );
  }
  return value.map((path) => path.trim());
}

function localOwnerAskBase(value) {
  if (!value) return "";
  try {
    const url = new URL(value);
    if (
      url.protocol !== "http:"
      || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
      || url.username
      || url.password
    ) {
      return "";
    }
    return url.toString();
  } catch {
    return "";
  }
}

export function normalizeSearchOptions(input = {}) {
  const rawTopK = input.top_k ?? input.topK ?? DEFAULT_TOP_K;
  const topK = Number(rawTopK);
  if (!Number.isInteger(topK) || topK < 1 || topK > MAX_TOP_K) {
    throw providerError(
      "INVALID_SEARCH_TOP_K",
      `top_k must be an integer between 1 and ${MAX_TOP_K}.`,
    );
  }
  const rawBreadth = input.breadth ?? 0.25;
  const breadth = Number(rawBreadth);
  if (!Number.isFinite(breadth) || breadth < 0 || breadth > 1) {
    throw providerError(
      "INVALID_SEARCH_BREADTH",
      "breadth must be a number between 0 and 1.",
    );
  }
  return Object.freeze({
    topK,
    breadth,
    paths: optionalPaths(input.paths ?? input.sources),
    since: optionalDate(input.since, "since"),
    until: optionalDate(input.until, "until"),
  });
}

function parseJson(value) {
  if (value && typeof value === "object") return value;
  if (typeof value !== "string" || value.trim().length === 0) return {};
  try {
    return JSON.parse(value);
  } catch {
    return {};
  }
}

export function parseMcpToolPayload(result) {
  const structured = result?.structuredContent?.result;
  const direct = parseJson(structured);
  if (Object.keys(direct).length > 0 || Array.isArray(direct)) return direct;
  const text = result?.content?.find((item) => item?.type === "text")?.text;
  return parseJson(text);
}

function finiteConfidence(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Math.min(1, Math.max(0, number));
}

function inferredContentType(hit) {
  if (CONTENT_TYPES.has(hit?.contentType)) return hit.contentType;
  const kind = String(hit?.kind || "").toLowerCase();
  const path = String(hit?.path || "").toLowerCase();
  if (
    ["root", "face", "volume", "pattern", "identity"].includes(kind)
    || /(?:^|\/)(?:schema|pattern|behavior|identity)-/u.test(path)
  ) {
    return "inferred";
  }
  return "observed";
}

function resultTimeRange(hit) {
  const raw = hit?.timeRange ?? hit?.time_range;
  if (raw && typeof raw === "object") {
    const start = raw.start ?? raw.since ?? raw.from ?? null;
    const end = raw.end ?? raw.until ?? raw.to ?? start;
    if (start || end) return { start: start || end, end: end || start };
  }
  const occurred = hit?.occurred_at ?? hit?.occurredAt;
  if (occurred && typeof occurred === "object") {
    const start = occurred.start ?? occurred.since ?? null;
    const end = occurred.end ?? occurred.until ?? start;
    if (start || end) return { start: start || end, end: end || start };
  }
  const timestamp = cleanText(
    hit?.timestamp ?? hit?.capturedAt ?? hit?.updatedAt,
    128,
  );
  return timestamp ? { start: timestamp, end: timestamp } : null;
}

function sourceTitle(hit, index) {
  const explicit = cleanText(hit?.title, 240);
  if (explicit) return explicit;
  const path = cleanText(hit?.path ?? hit?.source, 512);
  if (path) {
    return basename(path)
      .replace(/\.(?:md|markdown|txt|json)$/iu, "")
      .replace(/[-_]+/gu, " ");
  }
  return `Memory ${index + 1}`;
}

function evidenceReference(modelId, hit, index) {
  const identity = [
    hit?.id,
    hit?.path,
    hit?.timestamp,
    hit?.content,
    hit?.text,
    index,
  ].filter((value) => value !== undefined && value !== null).join("\u001f");
  const digest = createHash("sha256").update(identity).digest("hex").slice(0, 24);
  return `${modelId}:memory:${digest}`;
}

function boundSourceRefs(modelId, value) {
  if (!Array.isArray(value)) return [];
  return value.filter((sourceRef) => {
    if (typeof sourceRef !== "string" || sourceRef.length === 0) return false;
    const namespace = sourceRef.match(/^([A-Za-z0-9_-]+):/u)?.[1];
    return !namespace || namespace === modelId;
  });
}

function rawHits(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.results)) return payload.results;
  if (Array.isArray(payload?.hits)) return payload.hits;
  if (Array.isArray(payload?.evidence)) return payload.evidence;
  return [];
}

export function normalizeSearchResults({
  modelId,
  payload,
  topK = DEFAULT_TOP_K,
  method = "provider-search",
  generatedAt = new Date().toISOString(),
  generateEvidenceRefs = false,
} = {}) {
  const results = [];
  const seen = new Set();
  for (const [index, hit] of rawHits(payload).entries()) {
    if (!hit || typeof hit !== "object") continue;
    if (hit.modelId !== undefined && hit.modelId !== modelId) continue;
    const body = cleanText(
      hit.content ?? hit.text ?? hit.body ?? hit.summary ?? hit.snippet,
    );
    if (!body) continue;
    const rawId = cleanText(hit.id ?? hit.reference, 1024);
    const dedupeKey = rawId
      ? `id:${rawId}`
      : `body:${body.toLocaleLowerCase().replace(/\s+/gu, " ")}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    const boundEvidenceRefs = Array.isArray(hit.evidenceRefs)
      ? hit.evidenceRefs.filter((reference) =>
        typeof reference === "string" && reference.startsWith(`${modelId}:`)
      )
      : [];
    const boundReference = typeof hit.reference === "string"
      && hit.reference.startsWith(`${modelId}:`)
      ? hit.reference
      : "";
    const reference = boundReference
      || boundEvidenceRefs[0]
      || (generateEvidenceRefs ? evidenceReference(modelId, hit, index) : null);
    const path = cleanText(hit.path ?? hit.source?.path ?? hit.source, 1024) || null;
    const timestamp = cleanText(
      hit.timestamp ?? hit.source?.timestamp ?? hit.capturedAt,
      128,
    ) || null;
    const suppliedSourceRefs = boundSourceRefs(modelId, hit.sourceRefs);
    const confidence = finiteConfidence(hit.confidence);
    const rank = Number(hit.rank ?? hit.score);
    results.push({
      modelId,
      id: rawId || reference,
      kind: cleanText(hit.kind, 80) || "memory",
      title: sourceTitle(hit, index),
      text: body,
      body,
      score: Number.isFinite(rank) ? rank : confidence,
      evidenceRefs: boundEvidenceRefs.length
        ? boundEvidenceRefs
        : reference
          ? [reference]
          : [],
      reference,
      contentType: inferredContentType(hit),
      confidence,
      timeRange: resultTimeRange(hit),
      generatedAt: cleanText(hit.generatedAt, 128) || generatedAt,
      method: cleanText(hit.method, 120) || method,
      sourceRefs: suppliedSourceRefs.length
        ? suppliedSourceRefs
        : boundEvidenceRefs.length
          ? boundEvidenceRefs
          : reference
            ? [reference]
            : path
              ? [path]
              : [],
      source: {
        path,
        timestamp,
        ageDays: Number.isFinite(Number(hit.age_days ?? hit.ageDays))
          ? Number(hit.age_days ?? hit.ageDays)
          : null,
      },
      conflicted: hit.conflicted === true,
      relatedFaces: Array.isArray(hit.related_faces)
        ? hit.related_faces
        : Array.isArray(hit.relatedFaces)
          ? hit.relatedFaces
          : [],
      _evidence: {
        rawId: rawId || null,
        raw: structuredClone(hit),
      },
    });
    if (results.length >= topK) break;
  }
  return results;
}

export function publicSearchResult(result) {
  const { _evidence, ...publicResult } = result;
  return publicResult;
}

function answerExcerpt(result) {
  const text = cleanText(result?.text ?? result?.body, 360)
    .replace(/\s+/gu, " ");
  return text;
}

export function buildGroundedAnswer({
  modelId,
  displayName = "这个用户",
  results = [],
  ownerAnswer = "",
  ownerMethod = "retrieval-grounded",
  generatedAt = new Date().toISOString(),
} = {}) {
  const usable = results.filter((result) =>
    result?.modelId === modelId
    && result.conflicted !== true
    && answerExcerpt(result).length > 0
    && Array.isArray(result.evidenceRefs)
    && result.evidenceRefs.some((reference) =>
      typeof reference === "string" && reference.startsWith(`${modelId}:`)
    )
  );
  const evidenceRefs = [...new Set(
    usable.flatMap((result) => result.evidenceRefs),
  )];
  if (usable.length === 0 || evidenceRefs.length === 0) {
    return {
      modelId,
      status: "insufficient_evidence",
      refused: true,
      answer: `${displayName} 的 Personal Model 暂时没有足够证据回答这个问题；我不会根据空白猜测。`,
      results: [],
      evidenceRefs: [],
      contentType: "generated",
      confidence: 0,
      timeRange: null,
      generatedAt,
      method: "insufficient-evidence",
      sourceRefs: [],
      tools: ["search"],
    };
  }

  const directAnswer = cleanText(ownerAnswer, 4_000);
  const excerpts = usable.slice(0, 3).map(answerExcerpt).filter(Boolean);
  const answer = directAnswer || [
    `根据 ${displayName} 的 Personal Model，目前能有依据地确认：`,
    ...excerpts.map((excerpt) => `- ${excerpt}`),
  ].join("\n");
  const confidences = usable
    .map((result) => finiteConfidence(result.confidence))
    .filter((value) => value !== null);
  const confidence = confidences.length
    ? confidences.reduce((sum, value) => sum + value, 0) / confidences.length
    : 0.65;
  const ranges = usable.map((result) => result.timeRange).filter(Boolean);
  return {
    modelId,
    status: "answered",
    refused: false,
    answer,
    results: usable.map(publicSearchResult),
    evidenceRefs,
    contentType: "generated",
    confidence,
    timeRange: ranges.length === 1 ? ranges[0] : null,
    generatedAt,
    method: ownerMethod,
    sourceRefs: evidenceRefs,
    tools: ownerMethod === "owner-ask" ? ["owner-ask", "search"] : ["search"],
  };
}

export class LocalPersomeContentBackend {
  constructor({
    connectPersome,
    ownerAskUrl,
    fetchImpl = globalThis.fetch,
    clock = () => new Date(),
  } = {}) {
    if (typeof connectPersome !== "function") {
      throw new TypeError("Local content backend requires connectPersome.");
    }
    this.connectPersome = connectPersome;
    this.ownerAskUrl = localOwnerAskBase(ownerAskUrl);
    this.fetchImpl = fetchImpl;
    this.clock = clock;
    this.evidence = new Map();
    this.skipOwnerAsk = new Set();
  }

  generatedAt() {
    return this.clock().toISOString();
  }

  rememberEvidence(results) {
    for (const result of results) {
      const reference = result.reference;
      if (!reference) continue;
      this.evidence.delete(reference);
      this.evidence.set(reference, result);
    }
    while (this.evidence.size > 500) {
      this.evidence.delete(this.evidence.keys().next().value);
    }
  }

  invalidate(modelId) {
    for (const [reference, result] of this.evidence) {
      if (result.modelId === modelId) this.evidence.delete(reference);
    }
    this.skipOwnerAsk.add(modelId);
  }

  async search({ modelId, query, options = {} }) {
    const normalized = normalizeSearchOptions(options);
    const client = await this.connectPersome();
    try {
      const result = await client.callTool("search", {
        query,
        top_k: normalized.topK,
        breadth: normalized.breadth,
        include_bodies: true,
        ...(normalized.paths ? { paths: normalized.paths } : {}),
        ...(normalized.since ? { since: normalized.since } : {}),
        ...(normalized.until ? { until: normalized.until } : {}),
      });
      const results = normalizeSearchResults({
        modelId,
        payload: parseMcpToolPayload(result),
        topK: normalized.topK,
        method: "persome-mcp-search",
        generatedAt: this.generatedAt(),
        generateEvidenceRefs: true,
      });
      this.rememberEvidence(results);
      return results.map(publicSearchResult);
    } finally {
      client.close();
    }
  }

  async ownerAsk(question) {
    if (!this.ownerAskUrl || typeof this.fetchImpl !== "function") return null;
    try {
      const response = await this.fetchImpl(
        new URL("/api/owner/ask", `${this.ownerAskUrl.replace(/\/+$/u, "")}/`),
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ question }),
          signal: AbortSignal.timeout(8_000),
        },
      );
      const data = await response.json();
      if (!response.ok || data?.ok === false) return null;
      return data;
    } catch {
      return null;
    }
  }

  async ask({ modelId, question, displayName, options = {} }) {
    const bypassOwner = this.skipOwnerAsk.delete(modelId);
    const owner = bypassOwner ? null : await this.ownerAsk(question);
    let results = [];
    try {
      results = await this.search({ modelId, query: question, options });
    } catch {
      const ownerResults = normalizeSearchResults({
        modelId,
        payload: owner?.results ?? owner?.evidence ?? [],
        topK: normalizeSearchOptions(options).topK,
        method: "owner-ask-evidence",
        generatedAt: this.generatedAt(),
        generateEvidenceRefs: true,
      });
      this.rememberEvidence(ownerResults);
      results = ownerResults.map(publicSearchResult);
    }
    return buildGroundedAnswer({
      modelId,
      displayName,
      results,
      ownerAnswer: owner?.answer,
      ownerMethod: owner?.answer ? "owner-ask" : "retrieval-grounded",
      generatedAt: this.generatedAt(),
    });
  }

  async getEvidence({ modelId, reference }) {
    const cached = this.evidence.get(reference);
    if (!cached || cached.modelId !== modelId) {
      throw providerError(
        "EVIDENCE_NOT_FOUND",
        "The requested Evidence was not found.",
        404,
      );
    }
    let resolved = null;
    const rawId = cached._evidence?.rawId;
    if (rawId) {
      let client;
      try {
        client = await this.connectPersome();
        resolved = parseMcpToolPayload(
          await client.callTool("resolve_evidence", { reference: rawId }),
        );
      } catch {
        resolved = null;
      } finally {
        client?.close();
      }
    }
    const publicResult = publicSearchResult(cached);
    return {
      modelId,
      reference,
      content: {
        kind: "memory",
        ...publicResult,
        resolved,
      },
      ...(rawId ? { receipt: rawId } : {}),
      ...(Number.isFinite(Date.parse(cached.source?.timestamp))
        ? { capturedAt: new Date(cached.source.timestamp).toISOString() }
        : {}),
    };
  }
}
