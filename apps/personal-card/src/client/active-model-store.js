(function installActivePersonalModelStore(root) {
  "use strict";

  class ActiveModelStoreError extends Error {
    constructor(message, code, status) {
      super(message);
      this.name = "ActiveModelStoreError";
      this.code = code || "ACTIVE_MODEL_ERROR";
      this.status = status || 0;
    }
  }

  class StaleModelResponseError extends ActiveModelStoreError {
    constructor(message) {
      super(message || "Discarded a stale Personal Model response", "STALE_MODEL_RESPONSE", 409);
      this.name = "StaleModelResponseError";
    }
  }

  function cloneAndFreeze(value) {
    const clone = typeof structuredClone === "function"
      ? structuredClone(value)
      : JSON.parse(JSON.stringify(value));

    const freeze = (entry) => {
      if (!entry || typeof entry !== "object" || Object.isFrozen(entry)) return entry;
      for (const child of Object.values(entry)) freeze(child);
      return Object.freeze(entry);
    };

    return freeze(clone);
  }

  function normalizeModelId(value) {
    const modelId = String(value || "").trim();
    if (!/^[a-z0-9][a-z0-9._-]{0,63}$/i.test(modelId)) {
      throw new ActiveModelStoreError("Invalid Personal Model id", "INVALID_MODEL_ID", 400);
    }
    return modelId;
  }

  class ActivePersonalModelStore {
    constructor(options) {
      const config = options || {};
      this.fetchImpl = config.fetchImpl || root.fetch?.bind(root);
      if (typeof this.fetchImpl !== "function") {
        throw new TypeError("ActivePersonalModelStore requires fetch");
      }
      this.baseUrl = String(config.baseUrl || "");
      this.listeners = new Set();
      this.controllers = new Set();
      this.cache = new Map();
      this.generation = 0;
      this.state = Object.freeze({
        activeModelId: null,
        snapshot: null,
        revision: 0,
        loadingModelId: null,
        switchError: null,
        phase: "idle",
      });
    }

    getState() {
      return this.state;
    }

    subscribe(listener) {
      if (typeof listener !== "function") throw new TypeError("listener must be a function");
      this.listeners.add(listener);
      return () => this.listeners.delete(listener);
    }

    destroy() {
      this.abortInflight();
      this.listeners.clear();
      this.cache.clear();
    }

    emit(nextState, event) {
      this.state = Object.freeze(nextState);
      for (const listener of [...this.listeners]) {
        listener(this.state, event || Object.freeze({ type: "state" }));
      }
    }

    abortInflight() {
      for (const controller of this.controllers) controller.abort();
      this.controllers.clear();
    }

    async bootstrap(options) {
      const config = options || {};
      if (config.modelId) return this.switchModel(config.modelId, config);
      return this.loadAndCommit({
        endpoint: "/api/model/bootstrap",
        method: "GET",
        loadingModelId: this.state.activeModelId,
        body: null,
        eventType: "bootstrap",
      });
    }

    async switchModel(modelId, options) {
      const normalizedModelId = normalizeModelId(modelId);
      const config = options || {};
      const body = { modelId: normalizedModelId };
      if (config.access) body.access = String(config.access);
      if (config.grantToken) body.grantToken = String(config.grantToken);

      return this.loadAndCommit({
        endpoint: "/api/session/model",
        method: "POST",
        loadingModelId: normalizedModelId,
        body,
        eventType: "switch",
      });
    }

    async loadAndCommit({ endpoint, method, loadingModelId, body, eventType }) {
      const generation = ++this.generation;
      this.abortInflight();
      const controller = new AbortController();
      this.controllers.add(controller);
      const previous = this.state;

      this.emit({
        ...previous,
        loadingModelId: loadingModelId || previous.activeModelId,
        switchError: null,
        phase: "switching",
      }, Object.freeze({
        type: "model-switch-start",
        modelId: loadingModelId || previous.activeModelId,
      }));

      try {
        const payload = await this.fetchJson(endpoint, {
          method,
          body,
          signal: controller.signal,
        });
        if (generation !== this.generation) throw new StaleModelResponseError();

        const snapshot = payload?.snapshot;
        const responseModelId = normalizeModelId(payload?.modelId || snapshot?.model?.id);
        if (!snapshot || snapshot?.model?.id !== responseModelId) {
          throw new ActiveModelStoreError(
            "Personal Model response did not contain one complete matching Snapshot",
            "INVALID_MODEL_SNAPSHOT",
            502,
          );
        }
        if (loadingModelId && responseModelId !== loadingModelId) {
          throw new StaleModelResponseError("Personal Model response belongs to another model");
        }

        const revision = Number(payload.revision);
        if (!Number.isSafeInteger(revision) || revision < 1) {
          throw new ActiveModelStoreError(
            "Personal Model response did not contain a valid revision",
            "INVALID_MODEL_REVISION",
            502,
          );
        }

        const frozenSnapshot = cloneAndFreeze(snapshot);
        this.cache.clear();
        this.emit({
          activeModelId: responseModelId,
          snapshot: frozenSnapshot,
          revision,
          loadingModelId: null,
          switchError: null,
          phase: "ready",
        }, Object.freeze({
          type: "model-switch-commit",
          modelId: responseModelId,
          revision,
          source: eventType,
        }));
        return this.state;
      } catch (error) {
        if (generation !== this.generation || error?.name === "AbortError") {
          throw new StaleModelResponseError();
        }
        const safeError = error instanceof ActiveModelStoreError
          ? error
          : new ActiveModelStoreError(
              error?.message || "Unable to switch Personal Model",
              error?.code || "MODEL_SWITCH_FAILED",
              error?.status || 0,
            );
        this.emit({
          ...previous,
          loadingModelId: null,
          switchError: safeError.message,
          phase: previous.snapshot ? "ready" : "error",
        }, Object.freeze({
          type: "model-switch-error",
          modelId: loadingModelId || previous.activeModelId,
          error: safeError,
        }));
        throw safeError;
      } finally {
        this.controllers.delete(controller);
      }
    }

    async request(path, options) {
      if (!this.state.activeModelId || !this.state.snapshot) {
        throw new ActiveModelStoreError(
          "No active Personal Model",
          "NO_ACTIVE_MODEL",
          409,
        );
      }
      const config = options || {};
      const expectedModelId = this.state.activeModelId;
      const expectedRevision = this.state.revision;
      const expectedGeneration = this.generation;
      const cacheKey = config.cacheKey
        ? `${expectedModelId}:${expectedRevision}:${String(config.cacheKey)}`
        : "";
      if (cacheKey && this.cache.has(cacheKey)) return this.cache.get(cacheKey);

      const controller = new AbortController();
      this.controllers.add(controller);
      const externalSignal = config.signal;
      const abortFromExternal = () => controller.abort();
      if (externalSignal) {
        if (externalSignal.aborted) controller.abort();
        else externalSignal.addEventListener("abort", abortFromExternal, { once: true });
      }

      try {
        const payload = await this.fetchJson(path, {
          ...config,
          signal: controller.signal,
        });
        if (
          expectedGeneration !== this.generation
          || expectedModelId !== this.state.activeModelId
          || expectedRevision !== this.state.revision
        ) {
          throw new StaleModelResponseError();
        }
        if (payload?.modelId && payload.modelId !== expectedModelId) {
          throw new StaleModelResponseError("Response modelId does not match the active model");
        }
        if (payload?.revision != null && Number(payload.revision) !== expectedRevision) {
          throw new StaleModelResponseError("Response revision does not match the active model");
        }
        const result = cloneAndFreeze(payload);
        if (cacheKey) this.cache.set(cacheKey, result);
        return result;
      } catch (error) {
        if (error?.name === "AbortError") throw new StaleModelResponseError();
        throw error;
      } finally {
        this.controllers.delete(controller);
        if (externalSignal) externalSignal.removeEventListener("abort", abortFromExternal);
      }
    }

    async fetchJson(path, options) {
      const config = options || {};
      const headers = {
        Accept: "application/json",
        ...(config.body == null ? {} : { "Content-Type": "application/json" }),
        ...(config.headers || {}),
      };
      const response = await this.fetchImpl(`${this.baseUrl}${path}`, {
        method: config.method || "GET",
        credentials: "same-origin",
        headers,
        body: config.body == null
          ? undefined
          : typeof config.body === "string"
            ? config.body
            : JSON.stringify(config.body),
        signal: config.signal,
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok || payload?.ok === false) {
        throw new ActiveModelStoreError(
          payload?.error || `Personal Model request failed (${response.status})`,
          payload?.code || "MODEL_REQUEST_FAILED",
          response.status,
        );
      }
      return payload;
    }
  }

  Object.defineProperties(root, {
    ActivePersonalModelStore: {
      configurable: true,
      value: ActivePersonalModelStore,
    },
    ActiveModelStoreError: {
      configurable: true,
      value: ActiveModelStoreError,
    },
    StaleModelResponseError: {
      configurable: true,
      value: StaleModelResponseError,
    },
  });
})(globalThis);
