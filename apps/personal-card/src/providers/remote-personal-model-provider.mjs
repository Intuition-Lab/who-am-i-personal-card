import {
  parsePersonalModelCardSnapshot,
  parsePersonalModelCorrectionResponse,
  parsePersonalModelEvidenceResponse,
} from "../contracts/personal-model-card.mjs";
import {
  PersonalModelProvider,
  PersonalModelProviderError,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";
import { freezeCopy } from "./snapshot-backed-provider.mjs";
import {
  normalizeSearchOptions,
  normalizeSearchResults,
  publicSearchResult,
} from "../content/personal-model-content-backend.mjs";

const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

function cleanBearerToken(token) {
  if (
    typeof token !== "string" ||
    token.trim().length === 0 ||
    /[\r\n]/u.test(token)
  ) {
    throw new PersonalModelProviderError(
      "REMOTE_AUTH_UNAVAILABLE",
      "Remote Personal Model authorization is unavailable.",
      { status: 503 },
    );
  }
  return token.trim();
}

function cleanBaseUrl(baseUrl) {
  let url;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new TypeError("Remote Provider baseUrl must be a valid URL.");
  }

  if (!["http:", "https:"].includes(url.protocol)) {
    throw new TypeError("Remote Provider baseUrl must use HTTP or HTTPS.");
  }
  if (url.username || url.password) {
    throw new TypeError("Remote Provider baseUrl must not include credentials.");
  }

  url.pathname = `${url.pathname.replace(/\/+$/u, "")}/`;
  url.search = "";
  url.hash = "";
  return url;
}

function validateModelDescriptor(model) {
  if (
    model === null ||
    typeof model !== "object" ||
    typeof model.displayName !== "string" ||
    typeof model.handle !== "string" ||
    typeof model.memberNumber !== "string" ||
    !Number.isInteger(model.sinceYear) ||
    !["online", "offline", "snapshot"].includes(model.status)
  ) {
    throw new PersonalModelProviderError(
      "INVALID_PROVIDER_RESPONSE",
      "The remote Personal Model service returned invalid data.",
      { status: 502 },
    );
  }
  assertSafeModelId(model.id);
  return model;
}

function assertBoundObject(payload, modelId) {
  if (
    payload === null ||
    typeof payload !== "object" ||
    payload.modelId !== modelId
  ) {
    throw new PersonalModelProviderError(
      "MODEL_ID_MISMATCH",
      "The remote Personal Model service returned a different model.",
      { status: 502 },
    );
  }
  return freezeCopy(payload);
}

function assertBoundArray(payload, modelId) {
  if (
    !Array.isArray(payload) ||
    payload.some(
      (entry) =>
        entry === null ||
        typeof entry !== "object" ||
        entry.modelId !== modelId,
    )
  ) {
    throw new PersonalModelProviderError(
      "MODEL_ID_MISMATCH",
      "The remote Personal Model service returned mixed model data.",
      { status: 502 },
    );
  }
  return freezeCopy(payload);
}

export class RemotePersonalModelProvider extends PersonalModelProvider {
  constructor({
    baseUrl,
    bearerToken,
    tokenProvider,
    fetchImpl = globalThis.fetch,
    timeoutMs = 5_000,
  }) {
    super();
    if (typeof fetchImpl !== "function") {
      throw new TypeError("Remote Provider requires a fetch implementation.");
    }
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      throw new TypeError("Remote Provider timeoutMs must be positive.");
    }

    this.baseUrl = cleanBaseUrl(baseUrl);
    this.bearerToken = bearerToken;
    this.tokenProvider =
      typeof tokenProvider === "function" ? tokenProvider : null;
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
  }

  async resolveToken() {
    try {
      return cleanBearerToken(
        this.tokenProvider ? await this.tokenProvider() : this.bearerToken,
      );
    } catch (error) {
      if (error instanceof PersonalModelProviderError) {
        throw error;
      }
      throw new PersonalModelProviderError(
        "REMOTE_AUTH_UNAVAILABLE",
        "Remote Personal Model authorization is unavailable.",
        { status: 503 },
      );
    }
  }

  async request(pathname, { method = "GET", body, signal } = {}) {
    if (signal?.aborted) {
      throw new PersonalModelProviderError(
        "PROVIDER_ABORTED",
        "The Personal Model request was cancelled.",
        { status: 499 },
      );
    }

    const token = await this.resolveToken();
    if (signal?.aborted) {
      throw new PersonalModelProviderError(
        "PROVIDER_ABORTED",
        "The Personal Model request was cancelled.",
        { status: 499 },
      );
    }

    const controller = new AbortController();
    let timedOut = false;
    const onCallerAbort = () => controller.abort();
    signal?.addEventListener("abort", onCallerAbort, { once: true });
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeoutMs);

    const transportError = () => {
      if (signal?.aborted) {
        return new PersonalModelProviderError(
          "PROVIDER_ABORTED",
          "The Personal Model request was cancelled.",
          { status: 499 },
        );
      }
      if (timedOut) {
        return new PersonalModelProviderError(
          "PROVIDER_TIMEOUT",
          "The remote Personal Model request timed out.",
          { status: 504 },
        );
      }
      return new PersonalModelProviderError(
        "REMOTE_PROVIDER_UNAVAILABLE",
        "The remote Personal Model service is unavailable.",
        { status: 503 },
      );
    };

    try {
      let response;
      try {
        response = await this.fetchImpl(new URL(pathname, this.baseUrl), {
          method,
          headers: {
            accept: "application/json",
            authorization: `Bearer ${token}`,
            ...(body === undefined
              ? {}
              : { "content-type": "application/json" }),
          },
          body: body === undefined ? undefined : JSON.stringify(body),
          signal: controller.signal,
        });
      } catch {
        throw transportError();
      }

      if (!response || typeof response.ok !== "boolean") {
        throw new PersonalModelProviderError(
          "INVALID_PROVIDER_RESPONSE",
          "The remote Personal Model service returned an invalid response.",
          { status: 502 },
        );
      }

      if (!response.ok) {
        if (response.status === 401 || response.status === 403) {
          throw new PersonalModelProviderError(
            "REMOTE_AUTHORIZATION_FAILED",
            "Remote Personal Model authorization was rejected.",
            { status: 403 },
          );
        }
        if (response.status === 404) {
          throw new PersonalModelProviderError(
            "MODEL_NOT_FOUND",
            "The requested Personal Model was not found.",
            { status: 404 },
          );
        }
        throw new PersonalModelProviderError(
          "REMOTE_PROVIDER_ERROR",
          "The remote Personal Model service could not complete the request.",
          { status: 502 },
        );
      }

      let text;
      try {
        text = await response.text();
      } catch {
        if (signal?.aborted || timedOut) {
          throw transportError();
        }
        throw new PersonalModelProviderError(
          "INVALID_PROVIDER_RESPONSE",
          "The remote Personal Model service returned an unreadable response.",
          { status: 502 },
        );
      }

      if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
        throw new PersonalModelProviderError(
          "INVALID_PROVIDER_RESPONSE",
          "The remote Personal Model response exceeded the size limit.",
          { status: 502 },
        );
      }

      try {
        return JSON.parse(text);
      } catch {
        throw new PersonalModelProviderError(
          "INVALID_PROVIDER_RESPONSE",
          "The remote Personal Model service returned invalid JSON.",
          { status: 502 },
        );
      }
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener("abort", onCallerAbort);
    }
  }

  async listModels(options = {}) {
    const models = await this.request("models", options);
    if (!Array.isArray(models)) {
      throw new PersonalModelProviderError(
        "INVALID_PROVIDER_RESPONSE",
        "The remote Personal Model service returned invalid model data.",
        { status: 502 },
      );
    }
    return freezeCopy(models.map(validateModelDescriptor));
  }

  async getSnapshot(modelId, grant, options = {}) {
    assertSafeModelId(modelId);
    const rawSnapshot = await this.request(
      `models/${encodeURIComponent(modelId)}/snapshot`,
      { signal: options.signal },
    );
    let snapshot;
    try {
      snapshot = parsePersonalModelCardSnapshot(rawSnapshot);
    } catch {
      throw new PersonalModelProviderError(
        "INVALID_PROVIDER_RESPONSE",
        "The remote Personal Model service returned an invalid Snapshot.",
        { status: 502 },
      );
    }

    if (snapshot.model.id !== modelId) {
      throw new PersonalModelProviderError(
        "MODEL_ID_MISMATCH",
        "The remote Personal Model service returned a different model.",
        { status: 502 },
      );
    }
    return snapshot;
  }

  async getCurrentContext(modelId, grant, options = {}) {
    assertSafeModelId(modelId);
    return assertBoundObject(
      await this.request(`models/${encodeURIComponent(modelId)}/context`, {
        signal: options.signal,
      }),
      modelId,
    );
  }

  async search(modelId, query, grant, options = {}) {
    assertSafeModelId(modelId);
    if (typeof query !== "string" || query.trim().length === 0) {
      throw new PersonalModelProviderError(
        "INVALID_SEARCH_QUERY",
        "A non-empty search query is required.",
        { status: 400 },
      );
    }
    const searchOptions = normalizeSearchOptions(options);
    const response = assertBoundArray(
      await this.request(`models/${encodeURIComponent(modelId)}/search`, {
        method: "POST",
        // Keep the established remote wire contract. The local compatibility
        // layer applies top_k and metadata without requiring a remote rollout.
        body: { query },
        signal: options.signal,
      }),
      modelId,
    );
    return freezeCopy(normalizeSearchResults({
      modelId,
      payload: response,
      topK: searchOptions.topK,
      method: "remote-provider-search",
    }).map(publicSearchResult));
  }

  async getEvidence(modelId, reference, grant, options = {}) {
    assertSafeModelId(modelId);
    if (
      typeof reference !== "string" ||
      !reference.startsWith(`${modelId}:`)
    ) {
      throw new PersonalModelProviderError(
        "EVIDENCE_MODEL_MISMATCH",
        "The Evidence reference does not belong to the requested model.",
        { status: 403 },
      );
    }
    const rawEvidence = await this.request(
      `models/${encodeURIComponent(modelId)}/evidence/${encodeURIComponent(reference)}`,
      { signal: options.signal },
    );
    let evidence;
    try {
      evidence = parsePersonalModelEvidenceResponse(rawEvidence);
    } catch {
      throw new PersonalModelProviderError(
        "INVALID_PROVIDER_RESPONSE",
        "The remote Personal Model service returned invalid Evidence.",
        { status: 502 },
      );
    }
    if (evidence.modelId !== modelId) {
      throw new PersonalModelProviderError(
        "MODEL_ID_MISMATCH",
        "The remote Personal Model service returned different Evidence.",
        { status: 502 },
      );
    }
    if (evidence.reference !== reference) {
      throw new PersonalModelProviderError(
        "EVIDENCE_RESPONSE_MISMATCH",
        "The remote Personal Model service returned different Evidence.",
        { status: 502 },
      );
    }
    return evidence;
  }

  async correct(modelId, correction, grant, options = {}) {
    assertSafeModelId(modelId);
    const rawCorrection = await this.request(
      `models/${encodeURIComponent(modelId)}/corrections`,
      {
        method: "POST",
        body: { correction },
        signal: options.signal,
      },
    );
    let response;
    try {
      response = parsePersonalModelCorrectionResponse(rawCorrection);
    } catch {
      throw new PersonalModelProviderError(
        "INVALID_PROVIDER_RESPONSE",
        "The remote Personal Model service returned an invalid correction receipt.",
        { status: 502 },
      );
    }
    if (response.modelId !== modelId) {
      throw new PersonalModelProviderError(
        "MODEL_ID_MISMATCH",
        "The remote Personal Model service returned a different model.",
        { status: 502 },
      );
    }
    return response;
  }

  async connectAgent(modelId, connectorId, grant, options = {}) {
    assertSafeModelId(modelId);
    return assertBoundObject(
      await this.request(
        `models/${encodeURIComponent(modelId)}/connectors/${encodeURIComponent(connectorId)}/connect`,
        {
          method: "POST",
          body: {},
          signal: options.signal,
        },
      ),
      modelId,
    );
  }

  async listAgentReports(modelId, grant, options = {}) {
    assertSafeModelId(modelId);
    return assertBoundArray(
      await this.request(`models/${encodeURIComponent(modelId)}/reports`, {
        signal: options.signal,
      }),
      modelId,
    );
  }
}
