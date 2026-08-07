import {
  PersonalModelProviderError,
  assertPersonalModelProvider,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";
import {
  freezeCopy,
  validateSnapshotForModel,
} from "./snapshot-backed-provider.mjs";

export class ProviderRegistry {
  constructor(entries = {}) {
    const source =
      entries instanceof Map ? [...entries.entries()] : Object.entries(entries);
    this.providers = new Map();

    for (const [modelId, provider] of source) {
      this.providers.set(
        assertSafeModelId(modelId),
        assertPersonalModelProvider(provider),
      );
    }
  }

  get modelIds() {
    return Object.freeze([...this.providers.keys()]);
  }

  resolve(modelId) {
    assertSafeModelId(modelId);
    const provider = this.providers.get(modelId);
    if (!provider) {
      throw new PersonalModelProviderError(
        "MODEL_NOT_FOUND",
        "The requested Personal Model is not registered.",
        { status: 404 },
      );
    }
    return provider;
  }

  register(modelId, provider) {
    const safeModelId = assertSafeModelId(modelId);
    this.providers.set(
      safeModelId,
      assertPersonalModelProvider(provider),
    );
    return this;
  }

  unregister(modelId) {
    return this.providers.delete(assertSafeModelId(modelId));
  }

  async listModels() {
    const providerModels = new Map();
    for (const provider of new Set(this.providers.values())) {
      providerModels.set(provider, await provider.listModels());
    }

    const allowedModels = [];
    for (const [modelId, provider] of this.providers.entries()) {
      const descriptor = providerModels
        .get(provider)
        .find((model) => model.id === modelId);
      if (!descriptor) {
        throw new PersonalModelProviderError(
          "INVALID_PROVIDER_RESPONSE",
          "A registered Provider did not return its model descriptor.",
          { status: 502 },
        );
      }
      allowedModels.push(descriptor);
    }

    return freezeCopy(allowedModels);
  }

  async getSnapshot(modelId, grant, options) {
    const provider = this.resolve(modelId);
    const snapshot = await provider.getSnapshot(modelId, grant, options);
    return validateSnapshotForModel(snapshot, modelId);
  }
}
