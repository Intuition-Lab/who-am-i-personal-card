import assert from "node:assert/strict";
import test from "node:test";

import {
  GrantTokenService,
  PersonalModelAuthorizationError,
} from "../../src/auth/index.mjs";

const NOW = Date.parse("2026-08-07T08:00:00.000Z");
const SECRET = Buffer.from(
  "personal-card-v5-test-secret-contains-more-than-32-bytes",
);
const AUDIENCE = "personal-card-v5";

function claims(overrides = {}) {
  return {
    grantId: "grant_lin_viewer_01",
    modelId: "lin-demo",
    subject: "viewer_01",
    scopes: ["card:read", "identity:read", "now:read"],
    expiresAt: "2026-08-08T08:00:00.000Z",
    audience: AUDIENCE,
    issuedAt: "2026-08-07T07:55:00.000Z",
    ...overrides,
  };
}

function service() {
  return new GrantTokenService({
    secret: SECRET,
    audience: AUDIENCE,
    clock: () => NOW,
  });
}

function assertGrantError(code) {
  return (error) =>
    error instanceof PersonalModelAuthorizationError &&
    error.status === 403 &&
    error.code === code;
}

test("HMAC Grant round-trips validated, frozen claims", () => {
  const grants = service();
  const token = grants.sign(claims());
  const verified = grants.verify(token, {
    modelId: "lin-demo",
    audience: AUDIENCE,
  });

  assert.equal(verified.grantId, "grant_lin_viewer_01");
  assert.equal(verified.modelId, "lin-demo");
  assert.deepEqual(verified.scopes, [
    "card:read",
    "identity:read",
    "now:read",
  ]);
  assert.ok(Object.isFrozen(verified));
});

test("Grant signature rejects modified signatures and payloads", () => {
  const grants = service();
  const token = grants.sign(claims());
  const [header, payload, signature] = token.split(".");
  const changedSignature = `${signature.slice(0, -1)}${
    signature.endsWith("A") ? "B" : "A"
  }`;

  assert.throws(
    () => grants.verify(`${header}.${payload}.${changedSignature}`),
    assertGrantError("GRANT_SIGNATURE_INVALID"),
  );

  const decoded = JSON.parse(
    Buffer.from(payload, "base64url").toString("utf8"),
  );
  decoded.modelId = "cecilia";
  const changedPayload = Buffer.from(
    JSON.stringify(decoded),
    "utf8",
  ).toString("base64url");
  assert.throws(
    () => grants.verify(`${header}.${changedPayload}.${signature}`),
    assertGrantError("GRANT_SIGNATURE_INVALID"),
  );
});

test("Grant rejects expiry, wrong audience, and wrong model", () => {
  const grants = service();
  const expired = grants.sign(
    claims({ expiresAt: "2026-08-07T07:59:59.000Z" }),
  );
  assert.throws(
    () => grants.verify(expired, { modelId: "lin-demo" }),
    assertGrantError("GRANT_EXPIRED"),
  );

  const wrongAudience = grants.sign(
    claims({ audience: "another-application" }),
  );
  assert.throws(
    () => grants.verify(wrongAudience, { modelId: "lin-demo" }),
    assertGrantError("GRANT_AUDIENCE_MISMATCH"),
  );

  const wrongModel = grants.sign(claims());
  assert.throws(
    () => grants.verify(wrongModel, { modelId: "cecilia" }),
    assertGrantError("GRANT_MODEL_MISMATCH"),
  );
});

test("Grant refuses unknown scopes and weak signing secrets", () => {
  const grants = service();
  assert.throws(
    () => grants.sign(claims({ scopes: ["card:read", "database:dump"] })),
    assertGrantError("UNKNOWN_SCOPE"),
  );
  assert.throws(
    () =>
      new GrantTokenService({
        secret: "too-short",
        audience: AUDIENCE,
      }),
    TypeError,
  );
});
