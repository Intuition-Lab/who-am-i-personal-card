import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  PersonalModelCardValidationError,
  parsePersonalModelCardSnapshot,
  parsePersonalModelCorrectionResponse,
  parsePersonalModelEvidenceResponse,
  parsePersonalModelGrantClaims,
  parsePublicPersonalModelCardSnapshot,
  projectPublicPersonalModelCardSnapshot,
} from "../../src/contracts/personal-model-card.mjs";

const fixtureUrl = (name) =>
  new URL(`../../fixtures/models/${name}.json`, import.meta.url);
const schemaUrl = new URL(
  "../../src/contracts/personal-model-card.schema.json",
  import.meta.url,
);

async function loadJson(url) {
  return JSON.parse(await readFile(url, "utf8"));
}

function clone(value) {
  return structuredClone(value);
}

function removeAtPath(value, path) {
  const parent = path
    .slice(0, -1)
    .reduce((current, segment) => current[segment], value);
  delete parent[path.at(-1)];
}

function collectRequiredLocations(schema, value, path = []) {
  const locations = [];

  if (
    schema?.type === "object" &&
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value)
  ) {
    for (const key of schema.required ?? []) {
      if (Object.hasOwn(value, key)) {
        locations.push([...path, key]);
      }
    }

    for (const [key, childSchema] of Object.entries(
      schema.properties ?? {},
    )) {
      if (Object.hasOwn(value, key)) {
        locations.push(
          ...collectRequiredLocations(childSchema, value[key], [...path, key]),
        );
      }
    }
  }

  if (schema?.type === "array" && Array.isArray(value) && value.length > 0) {
    locations.push(...collectRequiredLocations(schema.items, value[0], [
      ...path,
      0,
    ]));
  }

  return locations;
}

test("Cecilia and Lin fixtures parse into detached, deeply frozen Snapshots", async () => {
  const [ceciliaInput, linInput] = await Promise.all([
    loadJson(fixtureUrl("cecilia")),
    loadJson(fixtureUrl("lin")),
  ]);

  const cecilia = parsePersonalModelCardSnapshot(ceciliaInput);
  const lin = parsePersonalModelCardSnapshot(linInput);

  assert.equal(cecilia.model.id, "cecilia");
  assert.equal(lin.model.id, "lin-demo");
  assert.notEqual(cecilia.model.handle, lin.model.handle);
  assert.ok(Object.isFrozen(cecilia));
  assert.ok(Object.isFrozen(cecilia.personalModel.faces));
  assert.ok(Object.isFrozen(cecilia.reports[0].sections[0]));

  for (const snapshot of [cecilia, lin]) {
    const future = snapshot.now.items.find(({ kind }) => kind === "future");
    assert.equal(future.metadata.provenance, "generated");
    assert.match(future.metadata.method, /continuation-suggestion/);
    assert.ok(future.metadata.sourceRefs.length > 0);
    assert.ok(future.metadata.timeRange.start.length > 0);
    assert.ok(future.metadata.timeRange.end.length > 0);
    assert.ok(future.dayId.length > 0);
    assert.ok(future.app.length > 0);
  }

  ceciliaInput.model.handle = "@changed-after-parse";
  assert.equal(cecilia.model.handle, "@cecilia");
});

test("deleting every required field represented by each fixture fails", async () => {
  const [schema, cecilia, lin] = await Promise.all([
    loadJson(schemaUrl),
    loadJson(fixtureUrl("cecilia")),
    loadJson(fixtureUrl("lin")),
  ]);

  let cases = 0;
  for (const fixture of [cecilia, lin]) {
    const requiredLocations = collectRequiredLocations(schema, fixture);
    assert.ok(requiredLocations.length >= 60);

    for (const path of requiredLocations) {
      const invalid = clone(fixture);
      removeAtPath(invalid, path);
      assert.throws(
        () => parsePersonalModelCardSnapshot(invalid),
        PersonalModelCardValidationError,
        `expected deletion at /${path.join("/")} to fail`,
      );
      cases += 1;
    }
  }

  assert.ok(cases >= 120);
});

test("authorized Snapshot requires audience-bearing Grant metadata", async () => {
  const lin = await loadJson(fixtureUrl("lin"));

  for (const requiredClaim of ["grantId", "expiresAt", "audience"]) {
    const invalid = clone(lin);
    delete invalid.authorization[requiredClaim];
    assert.throws(
      () => parsePersonalModelCardSnapshot(invalid),
      PersonalModelCardValidationError,
    );
  }
});

test("reports, connectors, counts, and Evidence stay in the active model partition", async () => {
  const cecilia = await loadJson(fixtureUrl("cecilia"));

  const crossedReport = clone(cecilia);
  crossedReport.reports[0].modelId = "lin-demo";
  assert.throws(
    () => parsePersonalModelCardSnapshot(crossedReport),
    (error) =>
      error instanceof PersonalModelCardValidationError &&
      error.issues.some(
        ({ path, keyword }) =>
          path === "/reports/0/modelId" && keyword === "modelOwnership",
      ),
  );

  const crossedEvidence = clone(cecilia);
  crossedEvidence.time.days[0].events[0].evidenceRef =
    "lin-demo:event:2026-08-07:01";
  assert.throws(
    () => parsePersonalModelCardSnapshot(crossedEvidence),
    (error) =>
      error instanceof PersonalModelCardValidationError &&
      error.issues.some(
        ({ path, keyword }) =>
          path === "/time/days/0/events/0/evidenceRef" &&
          keyword === "modelOwnership",
      ),
  );

  const missingConnector = clone(cecilia);
  missingConnector.reports[0].connectorId = "foreign-agent";
  assert.throws(
    () => parsePersonalModelCardSnapshot(missingConnector),
    PersonalModelCardValidationError,
  );

  const wrongEvidenceCount = clone(cecilia);
  wrongEvidenceCount.reports[0].evidenceCount = 99;
  assert.throws(
    () => parsePersonalModelCardSnapshot(wrongEvidenceCount),
    PersonalModelCardValidationError,
  );
});

test("Public projection contains only card and identity data", async () => {
  const ceciliaInput = await loadJson(fixtureUrl("cecilia"));
  const cecilia = parsePersonalModelCardSnapshot(ceciliaInput);
  const projected = projectPublicPersonalModelCardSnapshot(cecilia);

  assert.deepEqual(Object.keys(projected).sort(), [
    "authorization",
    "card",
    "identity",
    "model",
    "projection",
    "schemaVersion",
  ]);
  assert.deepEqual(projected.authorization.scopes, [
    "card:read",
    "identity:read",
  ]);

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
  assert.equal(serialized.includes(cecilia.personalModel.root), false);
  assert.equal(serialized.includes(cecilia.reports[0].summary), false);

  assert.throws(
    () => projectPublicPersonalModelCardSnapshot(ceciliaInput),
    PersonalModelCardValidationError,
  );

  const leakedResponse = { ...projected, reports: cecilia.reports };
  assert.throws(
    () => parsePublicPersonalModelCardSnapshot(leakedResponse),
    PersonalModelCardValidationError,
  );

  const leakedMetadataReference = clone(projected);
  leakedMetadataReference.identity.metadata = {
    sourceRefs: ["cecilia:event:2026-08-07:01"],
  };
  assert.throws(
    () => parsePublicPersonalModelCardSnapshot(leakedMetadataReference),
    PersonalModelCardValidationError,
  );
});

test("Grant claims require audience and reject malformed expiry", () => {
  const validClaims = {
    grantId: "grant_lin_demo_viewer",
    modelId: "lin-demo",
    subject: "viewer_01",
    scopes: ["card:read", "identity:read"],
    expiresAt: "2026-08-08T08:00:00+08:00",
    audience: "personal-card-v5",
    issuedAt: "2026-08-07T08:00:00+08:00",
  };

  const claims = parsePersonalModelGrantClaims(validClaims);
  assert.ok(Object.isFrozen(claims));

  const withoutAudience = clone(validClaims);
  delete withoutAudience.audience;
  assert.throws(
    () => parsePersonalModelGrantClaims(withoutAudience),
    PersonalModelCardValidationError,
  );

  assert.throws(
    () =>
      parsePersonalModelGrantClaims({
        ...validClaims,
        expiresAt: "tomorrow morning",
      }),
    PersonalModelCardValidationError,
  );
});

test("Evidence response carries modelId and rejects cross-model references", () => {
  const evidence = parsePersonalModelEvidenceResponse({
    modelId: "lin-demo",
    reference: "lin-demo:event:2026-08-07:01",
    content: { title: "夜间导航 · 田野记录" },
  });

  assert.equal(evidence.modelId, "lin-demo");
  assert.equal(evidence.source.type, "derived-summary");
  assert.equal(evidence.availability.status, "unavailable");
  assert.equal(evidence.supports[0].relationship, "indirect");
  assert.ok(Object.isFrozen(evidence.content));

  assert.throws(
    () =>
      parsePersonalModelEvidenceResponse({
        modelId: "lin-demo",
        reference: "cecilia:event:2026-08-07:01",
        content: {},
      }),
    PersonalModelCardValidationError,
  );
});

test("Evidence contract preserves traceable original sources and rejects partial provenance", () => {
  const evidence = parsePersonalModelEvidenceResponse({
    modelId: "cecilia",
    reference: "cecilia:memory:mem-01",
    source: {
      type: "persome-memory",
      originalTime: "2026-08-06T03:20:00.000Z",
      application: "Notes",
      title: "Field note",
      recordId: "mem-01",
    },
    supports: [
      {
        claim: "Returns to direct observation before a product decision.",
        relationship: "direct",
      },
    ],
    availability: { status: "available" },
    content: { text: "Original memory text" },
  });

  assert.equal(evidence.source.type, "persome-memory");
  assert.equal(evidence.source.originalTime, "2026-08-06T03:20:00.000Z");
  assert.equal(evidence.supports[0].relationship, "direct");

  const partial = clone(evidence);
  delete partial.availability;
  assert.throws(
    () => parsePersonalModelEvidenceResponse(partial),
    PersonalModelCardValidationError,
  );
});

test("content metadata is optional, deeply frozen, model-bound, and hidden without Evidence scope", async () => {
  const input = await loadJson(fixtureUrl("cecilia"));
  input.identity.metadata = {
    provenance: "generated",
    sourceRefs: ["cecilia:event:2026-08-07:01"],
    confidence: 0.82,
    timeRange: {
      start: "2026-08-07T00:00:00.000Z",
      end: "2026-08-07T08:00:00.000Z",
    },
    generatedAt: "2026-08-07T08:00:00.000Z",
    method: "daily-identity-v2",
  };
  const parsed = parsePersonalModelCardSnapshot(input);
  assert.equal(parsed.identity.metadata.provenance, "generated");
  assert.ok(Object.isFrozen(parsed.identity.metadata.sourceRefs));

  const publicSnapshot = projectPublicPersonalModelCardSnapshot(parsed);
  assert.equal(
    Object.hasOwn(publicSnapshot.identity.metadata, "sourceRefs"),
    false,
  );
  assert.equal(publicSnapshot.identity.metadata.method, "daily-identity-v2");

  input.identity.metadata.sourceRefs = ["lin-demo:event:foreign"];
  assert.throws(
    () => parsePersonalModelCardSnapshot(input),
    (error) =>
      error instanceof PersonalModelCardValidationError &&
      error.issues.some(
        ({ path, keyword }) =>
          path === "/identity/metadata/sourceRefs/0" &&
          keyword === "modelOwnership",
      ),
  );
});

test("Correction contract distinguishes unverified legacy acceptance from verified propagation", () => {
  const legacy = parsePersonalModelCorrectionResponse({
    modelId: "cecilia",
    accepted: true,
  });
  assert.equal(legacy.status, "accepted");
  assert.equal(legacy.receipt, null);
  assert.equal(legacy.verification.status, "unverified");
  assert.equal(legacy.verification.oldConclusionDeprioritized, false);

  const applied = parsePersonalModelCorrectionResponse({
    modelId: "cecilia",
    status: "applied",
    receipt: "correction-001",
    affected: [
      {
        reference: "cecilia:face:01",
        previousConclusion: "Old conclusion",
        replacement: "New conclusion",
        state: "deprioritized",
      },
    ],
    verification: {
      status: "verified",
      refreshed: true,
      oldConclusionDeprioritized: true,
      previousUpdatedAt: "2026-08-07T08:00:00.000Z",
      updatedAt: "2026-08-07T08:05:00.000Z",
    },
  });
  assert.equal(applied.status, "applied");
  assert.ok(Object.isFrozen(applied.affected));

  const crossed = clone(applied);
  crossed.affected[0].reference = "lin-demo:face:01";
  assert.throws(
    () => parsePersonalModelCorrectionResponse(crossed),
    PersonalModelCardValidationError,
  );
});
