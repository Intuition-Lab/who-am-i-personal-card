export const PERSONAL_MODEL_PROVIDER_METHODS = Object.freeze([
  "listModels",
  "getSnapshot",
  "getCurrentContext",
  "search",
  "getEvidence",
  "correct",
  "connectAgent",
  "listAgentReports",
]);

const SAFE_MODEL_ID = /^[A-Za-z0-9](?:[A-Za-z0-9_-]{0,126}[A-Za-z0-9])?$/;

export class PersonalModelProviderError extends Error {
  constructor(code, message, { status = 500 } = {}) {
    super(message);
    this.name = "PersonalModelProviderError";
    this.code = code;
    this.status = status;
  }

  toJSON() {
    return {
      code: this.code,
      message: this.message,
    };
  }
}

export function assertSafeModelId(modelId) {
  if (
    typeof modelId !== "string" ||
    !SAFE_MODEL_ID.test(modelId) ||
    modelId.includes("..")
  ) {
    throw new PersonalModelProviderError(
      "INVALID_MODEL_ID",
      "The requested Personal Model ID is invalid.",
      { status: 400 },
    );
  }

  return modelId;
}

export function assertPersonalModelProvider(provider) {
  if (provider === null || typeof provider !== "object") {
    throw new TypeError("Personal Model Provider must be an object.");
  }

  const missing = PERSONAL_MODEL_PROVIDER_METHODS.filter(
    (method) => typeof provider[method] !== "function",
  );
  if (missing.length > 0) {
    throw new TypeError(
      `Personal Model Provider is missing methods: ${missing.join(", ")}`,
    );
  }

  return provider;
}

export class PersonalModelProvider {
  async listModels() {
    throw this.unsupported("listModels");
  }

  async getSnapshot() {
    throw this.unsupported("getSnapshot");
  }

  async getCurrentContext() {
    throw this.unsupported("getCurrentContext");
  }

  async search() {
    throw this.unsupported("search");
  }

  async getEvidence() {
    throw this.unsupported("getEvidence");
  }

  async correct() {
    throw this.unsupported("correct");
  }

  async connectAgent() {
    throw this.unsupported("connectAgent");
  }

  async listAgentReports() {
    throw this.unsupported("listAgentReports");
  }

  unsupported(operation) {
    return new PersonalModelProviderError(
      "PROVIDER_OPERATION_UNSUPPORTED",
      `The Personal Model Provider does not support ${operation}.`,
      { status: 501 },
    );
  }
}
