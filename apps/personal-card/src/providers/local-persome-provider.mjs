import {
  PersonalModelProviderError,
  assertPersonalModelProvider,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";
import { parsePersonalModelEvidenceResponse } from "../contracts/personal-model-card.mjs";
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
      try {
        const evidence = parsePersonalModelEvidenceResponse(
          await this.operations.getEvidence({
            modelId,
            reference,
            grant,
            signal: options.signal,
          }),
        );
        if (evidence.modelId !== modelId) throw new Error("model mismatch");
        return evidence;
      } catch {
        // Snapshot evidence remains available for legacy Card references.
      }
    }
    return super.getEvidence(modelId, reference, grant, options);
  }

  async correct(modelId, correction, grant, options = {}) {
    this.assertAvailableModel(modelId);
    if (typeof this.operations.correct !== "function") {
      return super.correct(modelId, correction, grant, options);
    }

    try {
      const result = await this.operations.correct({
        modelId,
        correction,
        grant,
        signal: options.signal,
      });
      return freezeCopy({
        modelId,
        result,
      });
    } catch {
      throw new PersonalModelProviderError(
        "LOCAL_OPERATION_FAILED",
        "The local Personal Model operation failed.",
        { status: 502 },
      );
    }
  }
}
