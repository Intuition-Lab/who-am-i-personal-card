import {
  PersonalModelProviderError,
  assertPersonalModelProvider,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";
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
