import assert from "node:assert/strict";
import test from "node:test";

await import("../../src/client/active-model-store.js");

const {
  ActivePersonalModelStore,
  StaleModelResponseError,
} = globalThis;

function snapshot(modelId, displayName = modelId) {
  return {
    schemaVersion: "1.0.0",
    model: {
      id: modelId,
      displayName,
      handle: `@${modelId}`,
      memberNumber: "001",
      sinceYear: 2026,
      status: "snapshot",
    },
  };
}

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() {
      return structuredClone(body);
    },
  };
}

test("switchModel atomically commits one complete Snapshot", async () => {
  let revision = 0;
  const fetchImpl = async (_url, options) => {
    const { modelId } = JSON.parse(options.body);
    revision += 1;
    return jsonResponse({
      ok: true,
      modelId,
      revision,
      snapshot: snapshot(modelId, modelId === "lin-demo" ? "Lin" : "Cecilia"),
    });
  };
  const store = new ActivePersonalModelStore({ fetchImpl });
  const observed = [];
  store.subscribe((state, event) => {
    observed.push({
      type: event.type,
      activeModelId: state.activeModelId,
      snapshotModelId: state.snapshot?.model?.id || null,
      loadingModelId: state.loadingModelId,
    });
  });

  await store.switchModel("cecilia");
  await store.switchModel("lin-demo");

  assert.equal(store.getState().activeModelId, "lin-demo");
  assert.equal(store.getState().snapshot.model.id, "lin-demo");
  assert.equal(Object.isFrozen(store.getState().snapshot), true);
  assert.deepEqual(
    observed.filter(({ type }) => type === "model-switch-commit"),
    [
      {
        type: "model-switch-commit",
        activeModelId: "cecilia",
        snapshotModelId: "cecilia",
        loadingModelId: null,
      },
      {
        type: "model-switch-commit",
        activeModelId: "lin-demo",
        snapshotModelId: "lin-demo",
        loadingModelId: null,
      },
    ],
  );
  const switchingToLin = observed.find(
    ({ type, loadingModelId }) => type === "model-switch-start" && loadingModelId === "lin-demo",
  );
  assert.equal(switchingToLin.activeModelId, "cecilia");
  assert.equal(switchingToLin.snapshotModelId, "cecilia");
});

test("a failed switch keeps the previous complete model", async () => {
  const fetchImpl = async (_url, options) => {
    const { modelId } = JSON.parse(options.body);
    if (modelId === "lin-demo") {
      return jsonResponse({ ok: false, error: "grant denied", code: "FORBIDDEN" }, 403);
    }
    return jsonResponse({
      ok: true,
      modelId,
      revision: 1,
      snapshot: snapshot(modelId),
    });
  };
  const store = new ActivePersonalModelStore({ fetchImpl });
  await store.switchModel("cecilia");
  await assert.rejects(() => store.switchModel("lin-demo"), /grant denied/);

  assert.equal(store.getState().activeModelId, "cecilia");
  assert.equal(store.getState().snapshot.model.id, "cecilia");
  assert.equal(store.getState().switchError, "grant denied");
});

test("a later switch aborts and discards the earlier response", async () => {
  const pending = new Map();
  const fetchImpl = async (_url, options) => {
    const { modelId } = JSON.parse(options.body);
    return new Promise((resolve, reject) => {
      const abort = () => {
        const error = new Error("aborted");
        error.name = "AbortError";
        reject(error);
      };
      options.signal.addEventListener("abort", abort, { once: true });
      pending.set(modelId, (revision) => {
        options.signal.removeEventListener("abort", abort);
        resolve(jsonResponse({
          ok: true,
          modelId,
          revision,
          snapshot: snapshot(modelId),
        }));
      });
    });
  };
  const store = new ActivePersonalModelStore({ fetchImpl });
  const first = store.switchModel("cecilia");
  await new Promise((resolve) => setImmediate(resolve));
  const second = store.switchModel("lin-demo");
  pending.get("lin-demo")(2);

  await assert.rejects(first, StaleModelResponseError);
  await second;
  assert.equal(store.getState().activeModelId, "lin-demo");
  assert.equal(store.getState().revision, 2);
});

test("model-bound requests reject mismatched model or revision", async () => {
  let mode = "bootstrap";
  const fetchImpl = async (_url, options) => {
    if (mode === "bootstrap") {
      const { modelId } = JSON.parse(options.body);
      return jsonResponse({
        ok: true,
        modelId,
        revision: 7,
        snapshot: snapshot(modelId),
      });
    }
    return jsonResponse({
      ok: true,
      modelId: "lin-demo",
      revision: 7,
      value: "wrong partition",
    });
  };
  const store = new ActivePersonalModelStore({ fetchImpl });
  await store.switchModel("cecilia");
  mode = "request";

  await assert.rejects(
    () => store.request("/api/model/reports"),
    StaleModelResponseError,
  );
});
