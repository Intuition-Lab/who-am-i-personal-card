import { createHash } from "node:crypto";

import {
  PersonalModelProviderError,
  assertPersonalModelProvider,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";
import {
  parsePersonalModelCorrectionResponse,
  parsePersonalModelEvidenceResponse,
} from "../contracts/personal-model-card.mjs";
import {
  buildGroundedAnswer,
  normalizeSearchOptions,
  normalizeSearchResults,
  publicSearchResult,
} from "../content/personal-model-content-backend.mjs";
import {
  SnapshotBackedPersonalModelProvider,
  freezeCopy,
  validateSnapshotForModel,
} from "./snapshot-backed-provider.mjs";
import { parseResolvedPersonalModelEvidence } from "../evidence/evidence-record.mjs";

function normalizeConclusion(value) {
  return String(value || "")
    .normalize("NFKC")
    .replace(/\s+/gu, " ")
    .trim()
    .toLocaleLowerCase();
}

function sourceReference(value) {
  return value?.metadata?.sourceRefs?.[0] ?? value?.evidenceRefs?.[0];
}

function prioritizedConclusionEntries(snapshot) {
  const entries = [];
  const add = (text, value) => {
    const normalized = normalizeConclusion(text);
    if (!normalized) return;
    const reference = sourceReference(value);
    entries.push({
      text: String(text).trim(),
      normalized,
      ...(typeof reference === "string" ? { reference } : {}),
    });
  };

  add(snapshot.personalModel.root, snapshot.personalModel);
  snapshot.personalModel.faces.forEach((face) => add(face.text, face));
  add(snapshot.identity.description, snapshot.identity);
  add(snapshot.identity.dailyLine, snapshot.identity);
  snapshot.identity.weeklyLetter.forEach((line) =>
    add(line, snapshot.identity),
  );
  snapshot.now.items.forEach((item) => {
    add(item.title, item);
    add(item.why, item);
  });
  snapshot.time.days.forEach((day) => {
    add(day.portrait, day);
    add(day.letter, day);
  });
  snapshot.reports.forEach((report) => {
    add(report.summary, report);
    report.sections
      .filter(({ kind }) => kind === "understanding")
      .forEach((section) => add(section.body, section));
  });

  const unique = new Map();
  entries.forEach((entry) => {
    if (!unique.has(entry.normalized)) unique.set(entry.normalized, entry);
  });
  return [...unique.values()];
}

function normalizeCorrectionRequest(correction) {
  if (typeof correction === "string") {
    const text = correction.trim();
    if (text) return { text, affected: [] };
  }
  if (correction !== null && typeof correction === "object") {
    const text = String(correction.text ?? correction.correction ?? "").trim();
    if (text) {
      const affected = Array.isArray(correction.affected)
        ? correction.affected
        : correction.previousConclusion
          ? [{
              reference: correction.reference,
              previousConclusion: correction.previousConclusion,
              replacement: correction.replacement,
            }]
          : [];
      return { text, affected };
    }
  }
  throw new PersonalModelProviderError(
    "INVALID_CORRECTION",
    "A non-empty correction is required.",
    { status: 400 },
  );
}

function operationCorrectionPayload(result) {
  if (
    result?.result &&
    typeof result.result === "object" &&
    !Array.isArray(result.result)
  ) {
    return result.result;
  }
  return result;
}

function affectedConclusions(result, request) {
  const candidates = Array.isArray(result?.affected)
    ? result.affected
    : request.affected;
  return candidates
    .map((affected) =>
      typeof affected === "string"
        ? { previousConclusion: affected }
        : affected,
    )
    .filter((affected) =>
      affected &&
      typeof affected.previousConclusion === "string" &&
      affected.previousConclusion.trim(),
    )
    .map((affected) => ({
      ...(typeof affected.reference === "string"
        ? { reference: affected.reference }
        : {}),
      previousConclusion: affected.previousConclusion.trim(),
      ...(typeof affected.replacement === "string"
        ? { replacement: affected.replacement }
        : {}),
    }));
}

function deriveAffectedConclusions(beforeEntries, afterConclusions) {
  return beforeEntries
    .filter(({ normalized }) => !afterConclusions.has(normalized))
    .map(({ text, reference }) => ({
      ...(reference ? { reference } : {}),
      previousConclusion: text,
    }));
}

function productCorrectionReceipt({
  modelId,
  request,
  result,
  before,
  after,
  affected,
}) {
  const snapshotFingerprint = (snapshot) =>
    createHash("sha256").update(JSON.stringify(snapshot)).digest("hex");
  const digest = createHash("sha256")
    .update(
      JSON.stringify({
        version: 1,
        modelId,
        correction: request.text,
        runtime: {
          kind: result.kind ?? null,
          applied: Array.isArray(result.applied) ? result.applied : null,
          reason: result.reason ?? null,
          ok: result.ok ?? null,
        },
        previousUpdatedAt: before.personalModel.updatedAt,
        updatedAt: after.personalModel.updatedAt,
        beforeSnapshot: snapshotFingerprint(before),
        afterSnapshot: snapshotFingerprint(after),
        affected: affected.map(({ reference, previousConclusion }) => ({
          reference: reference ?? null,
          previousConclusion: normalizeConclusion(previousConclusion),
        })),
      }),
    )
    .digest("hex");
  return `${modelId}:correction:${digest}`;
}

function correctionVerificationError() {
  return new PersonalModelProviderError(
    "CORRECTION_VERIFICATION_FAILED",
    "The correction was not confirmed by a refreshed Personal Model.",
    { status: 409 },
  );
}

export class LocalPersomeProvider extends SnapshotBackedPersonalModelProvider {
  constructor({
    modelIds = [],
    loadSnapshot,
    fallbackProvider,
    operations = {},
  } = {}) {
    super();
    this.modelIds = Object.freeze(modelIds.map(assertSafeModelId));
    this.loadSnapshot =
      typeof loadSnapshot === "function" ? loadSnapshot : null;
    this.fallbackProvider = fallbackProvider
      ? assertPersonalModelProvider(fallbackProvider)
      : null;
    this.operations = operations;

    if (!this.loadSnapshot && !this.fallbackProvider) {
      throw new TypeError(
        "LocalPersomeProvider requires loadSnapshot or fallbackProvider.",
      );
    }
  }

  assertAvailableModel(modelId) {
    assertSafeModelId(modelId);
    if (!this.modelIds.includes(modelId)) {
      throw new PersonalModelProviderError(
        "MODEL_NOT_FOUND",
        "The requested local Personal Model is not available.",
        { status: 404 },
      );
    }
  }

  async listModels(options) {
    const snapshots = await Promise.all(
      this.modelIds.map((modelId) =>
        this.getSnapshot(modelId, undefined, options),
      ),
    );
    return freezeCopy(snapshots.map(({ model }) => model));
  }

  async getSnapshot(modelId, grant, options = {}) {
    this.assertAvailableModel(modelId);

    if (this.loadSnapshot) {
      try {
        const rawSnapshot = await this.loadSnapshot({
          modelId,
          grant,
          signal: options.signal,
        });
        return validateSnapshotForModel(rawSnapshot, modelId);
      } catch {
        // The local Runtime can expose sensitive paths or MCP payloads in its
        // errors. Fall through to a configured fixture without forwarding it.
      }
    }

    if (this.fallbackProvider) {
      try {
        return await this.fallbackProvider.getSnapshot(
          modelId,
          grant,
          options,
        );
      } catch {
        // Normalize fallback failures into the same content-free boundary.
      }
    }

    throw new PersonalModelProviderError(
      "LOCAL_PROVIDER_UNAVAILABLE",
      "The local Personal Model is unavailable.",
      { status: 503 },
    );
  }

  async search(modelId, query, grant, options = {}) {
    this.assertAvailableModel(modelId);
    if (typeof query !== "string" || query.trim().length === 0) {
      throw new PersonalModelProviderError(
        "INVALID_SEARCH_QUERY",
        "A non-empty search query is required.",
        { status: 400 },
      );
    }
    const searchOptions = normalizeSearchOptions(options);
    if (typeof this.operations.search === "function") {
      try {
        const rawResults = await this.operations.search({
          modelId,
          query: query.trim(),
          grant,
          options: searchOptions,
          signal: options.signal,
        });
        const results = normalizeSearchResults({
          modelId,
          payload: rawResults,
          topK: searchOptions.topK,
          method: "local-persome-search",
          generateEvidenceRefs: true,
        }).map(publicSearchResult);
        return freezeCopy(results);
      } catch {
        // A complete Snapshot is still a safe, model-bound degraded search.
      }
    }
    return super.search(modelId, query, grant, options);
  }

  async ask(modelId, question, grant, options = {}) {
    this.assertAvailableModel(modelId);
    if (typeof question !== "string" || question.trim().length === 0) {
      throw new PersonalModelProviderError(
        "INVALID_QUESTION",
        "A non-empty question is required.",
        { status: 400 },
      );
    }
    const searchOptions = normalizeSearchOptions(options);
    if (typeof this.operations.ask === "function") {
      try {
        const answer = await this.operations.ask({
          modelId,
          question: question.trim(),
          grant,
          displayName: options.displayName,
          options: searchOptions,
          signal: options.signal,
        });
        if (answer?.modelId !== modelId) throw new Error("model mismatch");
        if (answer.refused !== true) {
          const evidenceRefs = Array.isArray(answer.evidenceRefs)
            ? answer.evidenceRefs
            : [];
          const results = Array.isArray(answer.results) ? answer.results : [];
          if (
            evidenceRefs.length === 0
            || evidenceRefs.some((reference) =>
              typeof reference !== "string"
              || !reference.startsWith(`${modelId}:`)
            )
            || results.length === 0
            || results.some((result) => result?.modelId !== modelId)
          ) {
            throw new Error("ungrounded answer");
          }
        }
        return freezeCopy(answer);
      } catch {
        // Owner ask is optional. Fall back to the same grounded search path.
      }
    }
    let results = [];
    try {
      results = await this.search(modelId, question, grant, searchOptions);
    } catch {
      // Evidence absence is represented as an explicit refusal, not an error.
    }
    return freezeCopy(buildGroundedAnswer({
      modelId,
      displayName: options.displayName,
      results,
    }));
  }

  async getEvidence(modelId, reference, grant, options = {}) {
    this.assertAvailableModel(modelId);
    if (
      typeof reference !== "string"
      || !reference.startsWith(`${modelId}:`)
    ) {
      throw new PersonalModelProviderError(
        "EVIDENCE_MODEL_MISMATCH",
        "The Evidence reference does not belong to the requested model.",
        { status: 403 },
      );
    }
    if (typeof this.operations.getEvidence === "function") {
      let resolved = null;
      try {
        resolved = await this.operations.getEvidence({
          modelId,
          reference,
          grant,
          signal: options.signal,
        });
      } catch {
        // Search Evidence may have expired from the bounded content cache.
      }
      if (resolved !== null && resolved !== undefined) {
        try {
          const evidence = parsePersonalModelEvidenceResponse(resolved);
          if (
            evidence.modelId !== modelId ||
            evidence.reference !== reference
          ) {
            throw new TypeError("The cached Evidence changed ownership.");
          }
          return evidence;
        } catch {
          throw new PersonalModelProviderError(
            "INVALID_PROVIDER_RESPONSE",
            "The local content backend returned invalid Evidence.",
            { status: 502 },
          );
        }
      }
    }

    if (typeof this.operations.resolveEvidence === "function") {
      let resolved = null;
      try {
        resolved = await this.operations.resolveEvidence({
          modelId,
          reference,
          grant,
          signal: options.signal,
        });
      } catch {
        // A disconnected resolver is treated like a broken legacy link. The
        // Snapshot fallback below remains explicit about unavailability.
      }
      if (resolved !== null && resolved !== undefined) {
        try {
          const evidence = parseResolvedPersonalModelEvidence({
            modelId,
            reference,
            resolved,
          });
          if (
            evidence.modelId !== modelId ||
            evidence.reference !== reference
          ) {
            throw new TypeError("The resolved Evidence changed ownership.");
          }
          return evidence;
        } catch {
          throw new PersonalModelProviderError(
            "INVALID_PROVIDER_RESPONSE",
            "The local Evidence resolver returned an invalid record.",
            { status: 502 },
          );
        }
      }
    }

    return super.getEvidence(modelId, reference, grant, options);
  }

  async correct(modelId, correction, grant, options = {}) {
    this.assertAvailableModel(modelId);
    if (typeof this.operations.correct !== "function") {
      return super.correct(modelId, correction, grant, options);
    }

    const request = normalizeCorrectionRequest(correction);
    if (
      request.affected.some(
        (affected) =>
          affected !== null &&
          typeof affected === "object" &&
          typeof affected.reference === "string" &&
          !affected.reference.startsWith(`${modelId}:`),
      )
    ) {
      throw new PersonalModelProviderError(
        "EVIDENCE_MODEL_MISMATCH",
        "The correction target belongs to another Personal Model.",
        { status: 403 },
      );
    }
    const before = await this.getSnapshot(modelId, grant, options);
    let rawResult;
    try {
      rawResult = await this.operations.correct({
        modelId,
        correction: request.text,
        request: freezeCopy(request),
        grant,
        signal: options.signal,
      });
    } catch {
      throw new PersonalModelProviderError(
        "LOCAL_OPERATION_FAILED",
        "The local Personal Model operation failed.",
        { status: 502 },
      );
    }

    const result = operationCorrectionPayload(rawResult);
    if (result === null || typeof result !== "object" || result.ok === false) {
      throw new PersonalModelProviderError(
        "LOCAL_OPERATION_FAILED",
        "The local Personal Model operation failed.",
        { status: 502 },
      );
    }

    const runtimeReceipt =
      typeof result.receipt === "string" && result.receipt.trim()
        ? result.receipt.trim()
        : typeof result.correctionReceipt === "string" &&
            result.correctionReceipt.trim()
          ? result.correctionReceipt.trim()
          : null;
    if (Array.isArray(result.applied) && result.applied.length === 0) {
      throw new PersonalModelProviderError(
        "LOCAL_OPERATION_FAILED",
        "The local Personal Model operation did not apply a correction.",
        { status: 409 },
      );
    }

    let after;
    try {
      after = await this.getSnapshot(modelId, grant, options);
    } catch {
      throw correctionVerificationError();
    }
    const beforeEntries = prioritizedConclusionEntries(before);
    const afterEntries = prioritizedConclusionEntries(after);
    const beforeConclusions = new Set(
      beforeEntries.map(({ normalized }) => normalized),
    );
    const afterConclusions = new Set(
      afterEntries.map(({ normalized }) => normalized),
    );
    let affected = affectedConclusions(result, request);
    if (affected.length === 0) {
      // Pinned Persome 0.3.2 returns {kind, applied, reason, ok}. Reconstruct
      // affected visible conclusions from two independently validated reads.
      affected = deriveAffectedConclusions(beforeEntries, afterConclusions);
    }
    if (
      affected.length === 0 ||
      affected.some(
        ({ reference }) =>
          typeof reference === "string" &&
          !reference.startsWith(`${modelId}:`),
      )
    ) {
      throw correctionVerificationError();
    }
    if (
      affected.some(({ previousConclusion }) => {
        const oldConclusion = normalizeConclusion(previousConclusion);
        return (
          !beforeConclusions.has(oldConclusion) ||
          afterConclusions.has(oldConclusion)
        );
      })
    ) {
      throw correctionVerificationError();
    }

    const receipt = runtimeReceipt ?? productCorrectionReceipt({
      modelId,
      request,
      result,
      before,
      after,
      affected,
    });

    return parsePersonalModelCorrectionResponse({
      modelId,
      status: "applied",
      receipt,
      receiptSource: runtimeReceipt ? "runtime" : "product",
      affected: affected.map((entry) => ({
        ...entry,
        state: "deprioritized",
      })),
      verification: {
        status: "verified",
        refreshed: true,
        oldConclusionDeprioritized: true,
        previousUpdatedAt: before.personalModel.updatedAt,
        updatedAt: after.personalModel.updatedAt,
      },
    });
  }
}
