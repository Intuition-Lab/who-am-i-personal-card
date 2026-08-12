import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  parsePersonalModelCardSnapshot,
} from "../../src/contracts/personal-model-card.mjs";
import {
  OWNER_SCOPES,
  PersonalModelAuthorizationError,
  projectSnapshotByScope,
  requireScope,
} from "../../src/auth/index.mjs";

async function fixture(name) {
  const input = JSON.parse(
    await readFile(
      new URL(`../../fixtures/models/${name}.json`, import.meta.url),
      "utf8",
    ),
  );
  return parsePersonalModelCardSnapshot(input);
}

const authorized = (scopes) => ({
  viewerMode: "authorized",
  grantId: "grant_lin_limited",
  scopes,
  expiresAt: "2026-08-08T08:00:00.000Z",
  audience: "personal-card-v5",
});

test("owner projection receives a validated full Snapshot with all scopes", async () => {
  const cecilia = await fixture("cecilia");
  const owner = projectSnapshotByScope(cecilia, {
    viewerMode: "owner",
    scopes: OWNER_SCOPES,
  });

  assert.equal(owner.model.id, "cecilia");
  assert.equal(owner.authorization.viewerMode, "owner");
  assert.deepEqual(owner.authorization.scopes, OWNER_SCOPES);
  assert.ok(owner.personalModel.root);
  assert.ok(owner.time.days.length);
  assert.ok(owner.reports.length);
  assert.ok(Object.isFrozen(owner));
});

test("public projection is exactly the strict E1 public contract", async () => {
  const lin = await fixture("lin");
  const projected = projectSnapshotByScope(lin, {
    viewerMode: "public",
    scopes: ["card:read", "identity:read"],
  });

  assert.deepEqual(Object.keys(projected).sort(), [
    "authorization",
    "card",
    "identity",
    "model",
    "projection",
    "schemaVersion",
  ]);
  assert.equal(projected.projection, "public");
  assert.equal(projected.model.handle, "@lin");
  for (const privateField of [
    "personalModel",
    "now",
    "time",
    "connectors",
    "reports",
  ]) {
    assert.equal(Object.hasOwn(projected, privateField), false);
  }

  const serialized = JSON.stringify(projected);
  assert.equal(serialized.includes("夜间导航 · 田野记录"), false);
  assert.equal(serialized.includes("report_lin_codex_01"), false);
  assert.equal(serialized.includes("lin-demo:event:"), false);
});

test("authorized projection omits every section without its scope", async () => {
  const lin = await fixture("lin");
  const projected = projectSnapshotByScope(
    lin,
    authorized(["identity:read"]),
  );

  assert.deepEqual(Object.keys(projected).sort(), [
    "authorization",
    "identity",
    "model",
    "projection",
    "schemaVersion",
  ]);
  assert.equal(projected.identity.dailyLine, lin.identity.dailyLine);
  for (const deniedField of [
    "card",
    "personalModel",
    "now",
    "time",
    "connectors",
    "reports",
  ]) {
    assert.equal(Object.hasOwn(projected, deniedField), false);
  }

  const serialized = JSON.stringify(projected);
  assert.equal(serialized.includes(lin.personalModel.root), false);
  assert.equal(serialized.includes(lin.now.items[0].title), false);
  assert.equal(serialized.includes(lin.reports[0].summary), false);
});

test("reports scope without Evidence scope removes references and Evidence sections", async () => {
  const cecilia = await fixture("cecilia");
  const input = structuredClone(cecilia);
  input.reports[0].sections.push({
    kind: "evidence",
    title: "Private source",
    body: "private-evidence-body",
  });
  const snapshot = parsePersonalModelCardSnapshot(input);
  const projected = projectSnapshotByScope(
    snapshot,
    authorized(["reports:read"]),
  );

  assert.equal(projected.reports.length, 1);
  assert.equal(projected.reports[0].evidenceCount, 0);
  assert.deepEqual(projected.reports[0].evidenceRefs, []);
  assert.equal(
    projected.reports[0].sections.some(({ kind }) => kind === "evidence"),
    false,
  );
  assert.equal(JSON.stringify(projected).includes("private-evidence-body"), false);
});

test("Evidence references and connector session IDs require their own scopes", async () => {
  const input = structuredClone(await fixture("lin"));
  input.identity.metadata = {
    provenance: "generated",
    sourceRefs: ["lin-demo:event:2026-08-07:01"],
    method: "identity-summary-v2",
  };
  const lin = parsePersonalModelCardSnapshot(input);
  const projected = projectSnapshotByScope(
    lin,
    authorized([
      "card:read",
      "identity:read",
      "rewind:read",
      "reports:read",
      "connectors:read",
    ]),
  );

  assert.equal(
    projected.personalModel.faces.some((face) =>
      Object.hasOwn(face, "evidenceRefs"),
    ),
    false,
  );
  assert.equal(
    projected.time.days.some((day) =>
      day.events.some((event) => Object.hasOwn(event, "evidenceRef")),
    ),
    false,
  );
  assert.equal(
    projected.connectors.some((connector) =>
      Object.hasOwn(connector, "sessionId"),
    ),
    false,
  );
  assert.equal(
    Object.hasOwn(projected.identity.metadata, "sourceRefs"),
    false,
  );
  assert.equal(projected.identity.metadata.method, "identity-summary-v2");
  assert.equal(JSON.stringify(projected).includes("lin-demo:event:"), false);
  assert.equal(JSON.stringify(projected).includes("cs_lin_codex"), false);

  const evidenceAllowed = projectSnapshotByScope(
    lin,
    authorized([
      "card:read",
      "identity:read",
      "rewind:read",
      "evidence:read",
      "connectors:read",
      "connectors:connect",
    ]),
  );
  assert.equal(
    evidenceAllowed.personalModel.faces[0].evidenceRefs[0].startsWith(
      "lin-demo:",
    ),
    true,
  );
  assert.equal(
    evidenceAllowed.time.days[0].events[0].evidenceRef.startsWith(
      "lin-demo:",
    ),
    true,
  );
  assert.deepEqual(evidenceAllowed.identity.metadata.sourceRefs, [
    "lin-demo:event:2026-08-07:01",
  ]);
  assert.equal(
    evidenceAllowed.connectors.find(({ id }) => id === "codex").sessionId,
    "cs_lin_codex",
  );
});

test("scope guard returns a content-free 403", () => {
  assert.throws(
    () =>
      requireScope(
        { viewerMode: "public", scopes: ["card:read", "identity:read"] },
        "reports:read",
      ),
    (error) =>
      error instanceof PersonalModelAuthorizationError &&
      error.status === 403 &&
      error.code === "SCOPE_REQUIRED" &&
      !error.message.includes("reports:read"),
  );
});
