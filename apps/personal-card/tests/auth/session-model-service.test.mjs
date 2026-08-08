import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  GrantTokenService,
  PersonalModelAuthorizationError,
  SessionModelService,
  ViewerSessionStore,
  createModelRequestContext,
} from "../../src/auth/index.mjs";
import {
  parsePersonalModelCardSnapshot,
} from "../../src/contracts/personal-model-card.mjs";
import { FixtureProvider } from "../../src/providers/fixture-provider.mjs";
import { LocalPersomeProvider } from "../../src/providers/local-persome-provider.mjs";
import { ProviderRegistry } from "../../src/providers/provider-registry.mjs";

const NOW = Date.parse("2026-08-07T08:00:00.000Z");
const AUDIENCE = "personal-card-v5";
const SECRET = Buffer.from(
  "personal-card-v5-session-tests-use-at-least-32-bytes",
);

function sequenceRandomBytes() {
  let value = 0;
  return (size) => {
    value += 1;
    return Buffer.alloc(size, value);
  };
}

function createStore() {
  return new ViewerSessionStore({
    clock: () => NOW,
    randomBytesFn: sequenceRandomBytes(),
  });
}

function createGrants() {
  return new GrantTokenService({
    secret: SECRET,
    audience: AUDIENCE,
    clock: () => NOW,
  });
}

function grantToken(grants, overrides = {}) {
  return grants.sign({
    grantId: "grant_lin_viewer_01",
    modelId: "lin-demo",
    subject: "viewer_01",
    scopes: [
      "card:read",
      "identity:read",
      "now:read",
      "rewind:read",
      "reports:read",
    ],
    expiresAt: "2026-08-08T08:00:00.000Z",
    audience: AUDIENCE,
    ...overrides,
  });
}

function registry() {
  const fixtures = new FixtureProvider();
  return new ProviderRegistry({
    cecilia: fixtures,
    "lin-demo": fixtures,
  });
}

function createService({
  sessionStore,
  providerRegistry = registry(),
  grantTokenService = createGrants(),
  isOwner = () => false,
  isPubliclyReadable = () => true,
}) {
  return new SessionModelService({
    sessionStore,
    providerRegistry,
    grantTokenService,
    audience: AUDIENCE,
    isOwner,
    isPubliclyReadable,
  });
}

function errorCode(code, status = 403) {
  return (error) =>
    error instanceof PersonalModelAuthorizationError &&
    error.code === code &&
    error.status === status;
}

async function fixture(name) {
  return parsePersonalModelCardSnapshot(
    JSON.parse(
      await readFile(
        new URL(`../../fixtures/models/${name}.json`, import.meta.url),
        "utf8",
      ),
    ),
  );
}

test("two browser cookies create independent viewer sessions", () => {
  const store = createStore();
  const first = store.getOrCreateFromCookie("");
  const second = store.getOrCreateFromCookie("");

  assert.notEqual(first.session.id, second.session.id);
  assert.notEqual(first.setCookie, second.setCookie);

  const repeated = store.getOrCreateFromCookie(
    first.setCookie.split(";", 1)[0],
  );
  assert.equal(repeated.session.id, first.session.id);
  assert.equal(repeated.setCookie, null);
  assert.equal(store.getSession(second.session.id).activeModelId, null);
});

test("owner, authorized viewer, and public viewer receive distinct projections", async () => {
  const store = createStore();
  const grants = createGrants();
  const owner = store.createSession({ viewerUserId: "owner_cecilia" });
  const authorized = store.createSession({ viewerUserId: "viewer_01" });
  const publicViewer = store.createSession();
  const service = createService({
    sessionStore: store,
    grantTokenService: grants,
    isOwner: ({ session, modelId }) =>
      session.viewerUserId === "owner_cecilia" && modelId === "cecilia",
  });

  const ownerState = await service.switchModel({
    sessionId: owner.id,
    modelId: "cecilia",
  });
  assert.equal(ownerState.authorization.viewerMode, "owner");
  assert.ok(ownerState.snapshot.personalModel);
  assert.ok(ownerState.snapshot.reports);

  const authorizedState = await service.switchModel({
    sessionId: authorized.id,
    modelId: "lin-demo",
    grantToken: grantToken(grants),
  });
  assert.equal(authorizedState.authorization.viewerMode, "authorized");
  assert.ok(authorizedState.snapshot.personalModel);
  assert.ok(authorizedState.snapshot.time);
  assert.ok(authorizedState.snapshot.reports);
  assert.equal(Object.hasOwn(authorizedState.snapshot, "connectors"), false);

  const publicState = await service.switchModel({
    sessionId: publicViewer.id,
    modelId: "lin-demo",
  });
  assert.equal(publicState.authorization.viewerMode, "public");
  assert.deepEqual(Object.keys(publicState.snapshot).sort(), [
    "authorization",
    "card",
    "identity",
    "model",
    "projection",
    "schemaVersion",
  ]);

  assert.equal(store.getSession(owner.id).activeModelId, "cecilia");
  assert.equal(store.getSession(authorized.id).activeModelId, "lin-demo");
  assert.equal(store.getSession(publicViewer.id).activeModelId, "lin-demo");
});

test("an owner can explicitly request the strict public projection", async () => {
  const store = createStore();
  const owner = store.createSession({ viewerUserId: "owner_cecilia" });
  const service = createService({
    sessionStore: store,
    isOwner: ({ session, modelId }) =>
      session.viewerUserId === "owner_cecilia" && modelId === "cecilia",
    isPubliclyReadable: ({ modelId }) => modelId === "cecilia",
  });

  const state = await service.switchModel({
    sessionId: owner.id,
    modelId: "cecilia",
    access: "public",
  });

  assert.equal(state.authorization.viewerMode, "public");
  assert.equal(state.snapshot.projection, "public");
  assert.deepEqual(Object.keys(state.snapshot).sort(), [
    "authorization",
    "card",
    "identity",
    "model",
    "projection",
    "schemaVersion",
  ]);
  assert.equal(Object.hasOwn(state.snapshot, "personalModel"), false);
  assert.equal(Object.hasOwn(state.snapshot, "time"), false);
  assert.equal(Object.hasOwn(state.snapshot, "reports"), false);
});

test("explicit authorized access requires a Grant and never downgrades to public", async () => {
  const store = createStore();
  const session = store.createSession();
  const service = createService({
    sessionStore: store,
    isPubliclyReadable: () => true,
  });

  await assert.rejects(
    service.switchModel({
      sessionId: session.id,
      modelId: "lin-demo",
      access: "authorized",
    }),
    errorCode("MODEL_GRANT_REQUIRED"),
  );
  const unchanged = store.getSession(session.id);
  assert.equal(unchanged.activeModelId, null);
  assert.equal(unchanged.revision, 0);
});

test("invalid requested access is rejected with 403 before Provider reads", async () => {
  const store = createStore();
  const session = store.createSession();
  let providerReads = 0;
  const service = createService({
    sessionStore: store,
    providerRegistry: {
      async getSnapshot() {
        providerReads += 1;
        return fixture("lin");
      },
    },
  });

  await assert.rejects(
    service.switchModel({
      sessionId: session.id,
      modelId: "lin-demo",
      access: "superuser",
    }),
    errorCode("VIEWER_MODE_INVALID"),
  );
  assert.equal(providerReads, 0);
  assert.equal(store.getSession(session.id).revision, 0);
});

test("invalid Grant cases are 403 and never change the session", async () => {
  const store = createStore();
  const grants = createGrants();
  const session = store.createSession();
  const service = createService({
    sessionStore: store,
    grantTokenService: grants,
  });

  const cases = [
    {
      code: "GRANT_EXPIRED",
      token: grantToken(grants, {
        expiresAt: "2026-08-07T07:59:59.000Z",
      }),
    },
    {
      code: "GRANT_AUDIENCE_MISMATCH",
      token: grantToken(grants, { audience: "wrong-application" }),
    },
    {
      code: "GRANT_MODEL_MISMATCH",
      token: grantToken(grants, { modelId: "cecilia" }),
    },
  ];

  for (const entry of cases) {
    await assert.rejects(
      service.switchModel({
        sessionId: session.id,
        modelId: "lin-demo",
        grantToken: entry.token,
      }),
      errorCode(entry.code),
    );
    const unchanged = store.getSession(session.id);
    assert.equal(unchanged.revision, 0);
    assert.equal(unchanged.activeModelId, null);
    assert.equal(unchanged.snapshot, null);
  }

  const valid = grantToken(grants);
  const [header, payload, signature] = valid.split(".");
  const forged = `${header}.${payload}.${signature.slice(0, -1)}${
    signature.endsWith("A") ? "B" : "A"
  }`;
  await assert.rejects(
    service.switchModel({
      sessionId: session.id,
      modelId: "lin-demo",
      grantToken: forged,
    }),
    errorCode("GRANT_SIGNATURE_INVALID"),
  );
});

test("a registered model is not public unless the server policy says so", async () => {
  const store = createStore();
  const session = store.createSession();
  const service = createService({
    sessionStore: store,
    isPubliclyReadable: () => false,
  });

  await assert.rejects(
    service.switchModel({
      sessionId: session.id,
      modelId: "lin-demo",
    }),
    errorCode("MODEL_GRANT_REQUIRED"),
  );
  const unchanged = store.getSession(session.id);
  assert.equal(unchanged.revision, 0);
  assert.equal(unchanged.activeModelId, null);
});

test("failed model switch preserves the prior model, revision, and Snapshot", async () => {
  const store = createStore();
  const session = store.createSession();
  const goodRegistry = registry();
  const initialService = createService({
    sessionStore: store,
    providerRegistry: goodRegistry,
  });
  const initial = await initialService.switchModel({
    sessionId: session.id,
    modelId: "cecilia",
  });

  const failingService = createService({
    sessionStore: store,
    providerRegistry: {
      async getSnapshot() {
        throw new Error("provider failed before a complete Snapshot existed");
      },
    },
  });
  await assert.rejects(
    failingService.switchModel({
      sessionId: session.id,
      modelId: "lin-demo",
    }),
  );

  const afterProviderFailure = store.getSession(session.id);
  assert.equal(afterProviderFailure.activeModelId, "cecilia");
  assert.equal(afterProviderFailure.revision, initial.revision);
  assert.equal(afterProviderFailure.snapshot, initial.snapshot);

  const invalidService = createService({
    sessionStore: store,
    providerRegistry: {
      async getSnapshot() {
        const lin = structuredClone(await fixture("lin"));
        delete lin.card;
        return lin;
      },
    },
  });
  await assert.rejects(
    invalidService.switchModel({
      sessionId: session.id,
      modelId: "lin-demo",
    }),
  );

  const afterValidationFailure = store.getSession(session.id);
  assert.equal(afterValidationFailure.activeModelId, "cecilia");
  assert.equal(afterValidationFailure.revision, initial.revision);
  assert.equal(afterValidationFailure.snapshot, initial.snapshot);
});

test("request context rejects body/query model overrides and enforces scope", async () => {
  const store = createStore();
  const session = store.createSession();
  const service = createService({ sessionStore: store });
  await service.switchModel({
    sessionId: session.id,
    modelId: "lin-demo",
  });

  assert.throws(
    () =>
      createModelRequestContext({
        sessionStore: store,
        sessionId: session.id,
        body: { request: { modelId: "cecilia" } },
      }),
    errorCode("MODEL_OVERRIDE_FORBIDDEN"),
  );
  assert.throws(
    () =>
      createModelRequestContext({
        sessionStore: store,
        sessionId: session.id,
        query: new URLSearchParams({ modelId: "cecilia" }),
      }),
    errorCode("MODEL_OVERRIDE_FORBIDDEN"),
  );
  assert.throws(
    () =>
      createModelRequestContext({
        sessionStore: store,
        sessionId: session.id,
        requiredScope: "reports:read",
      }),
    errorCode("SCOPE_REQUIRED"),
  );

  const context = createModelRequestContext({
    sessionStore: store,
    sessionId: session.id,
    body: { query: "city navigation" },
    requiredScope: "identity:read",
  });
  assert.equal(context.modelId, "lin-demo");
  assert.equal(context.revision, 1);
  assert.equal(context.snapshot.model.handle, "@lin");
  assert.ok(Object.isFrozen(context));
});

test("concurrent switches cannot let a stale Provider response overwrite a newer model", async () => {
  const store = createStore();
  const session = store.createSession();
  const baseRegistry = registry();
  let releaseSlow;
  const slowGate = new Promise((resolve) => {
    releaseSlow = resolve;
  });
  const service = createService({
    sessionStore: store,
    providerRegistry: {
      async getSnapshot(modelId, grant, options) {
        if (modelId === "cecilia") await slowGate;
        return baseRegistry.getSnapshot(modelId, grant, options);
      },
    },
  });

  const slow = service.switchModel({
    sessionId: session.id,
    modelId: "cecilia",
  });
  const fast = await service.switchModel({
    sessionId: session.id,
    modelId: "lin-demo",
  });
  releaseSlow();

  await assert.rejects(
    slow,
    errorCode("SESSION_REVISION_CONFLICT", 409),
  );
  const finalState = store.getSession(session.id);
  assert.equal(finalState.activeModelId, "lin-demo");
  assert.equal(finalState.revision, fast.revision);
  assert.equal(finalState.snapshot.model.handle, "@lin");
});

test("verified correction refresh propagates into the viewer session atomically", async () => {
  const store = createStore();
  const session = store.createSession({ viewerUserId: "owner_cecilia" });
  let rawSnapshot = structuredClone(await fixture("cecilia"));
  const previousConclusion = rawSnapshot.personalModel.faces[0].text;
  const replacement = "只在来源可追溯并且用户授权后公开分发。";
  const provider = new LocalPersomeProvider({
    modelIds: ["cecilia"],
    loadSnapshot: async () => rawSnapshot,
    operations: {
      correct: async () => {
        rawSnapshot = structuredClone(rawSnapshot);
        rawSnapshot.personalModel.faces[0].text = replacement;
        rawSnapshot.personalModel.updatedAt = "2026-08-07T08:10:00.000Z";
        return {
          receipt: "correction-session-001",
          affected: [
            {
              reference: "cecilia:face:01",
              previousConclusion,
              replacement,
            },
          ],
        };
      },
    },
  });
  const service = createService({
    sessionStore: store,
    providerRegistry: new ProviderRegistry({ cecilia: provider }),
    isOwner: ({ session: viewer, modelId }) =>
      viewer.viewerUserId === "owner_cecilia" && modelId === "cecilia",
  });

  const initial = await service.switchModel({
    sessionId: session.id,
    modelId: "cecilia",
  });
  const correction = await provider.correct(
    "cecilia",
    "Replace the old conclusion.",
  );
  assert.equal(correction.status, "applied");
  assert.equal(
    store.getSession(session.id).snapshot.personalModel.faces[0].text,
    previousConclusion,
  );

  const refreshed = await service.refreshModel({
    sessionId: session.id,
    expectedRevision: initial.revision,
  });
  assert.equal(refreshed.revision, initial.revision + 1);
  assert.equal(refreshed.activeModelId, "cecilia");
  assert.equal(refreshed.snapshot.personalModel.faces[0].text, replacement);
  assert.equal(
    JSON.stringify(refreshed.snapshot).includes(previousConclusion),
    false,
  );
});
