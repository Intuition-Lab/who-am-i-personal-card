import {
  parsePersonalModelCardSnapshot,
  projectPublicPersonalModelCardSnapshot,
} from "../contracts/personal-model-card.mjs";
import { PersonalModelAuthorizationError } from "./errors.mjs";

export const PERSONAL_MODEL_SCOPES = Object.freeze([
  "card:read",
  "identity:read",
  "now:read",
  "rewind:read",
  "evidence:read",
  "reports:read",
  "model:search",
  "model:ask",
  "model:correct",
  "connectors:read",
  "connectors:connect",
]);

export const OWNER_SCOPES = PERSONAL_MODEL_SCOPES;
export const PUBLIC_SCOPES = Object.freeze([
  "card:read",
  "identity:read",
]);

const KNOWN_SCOPES = new Set(PERSONAL_MODEL_SCOPES);

function deny(code, message) {
  throw new PersonalModelAuthorizationError(code, message, { status: 403 });
}

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  for (const child of Object.values(value)) {
    deepFreeze(child);
  }
  return Object.freeze(value);
}

function frozenClone(value) {
  return deepFreeze(structuredClone(value));
}

function stripMetadataSourceRefs(value) {
  if (value === null || typeof value !== "object") return value;
  if (
    !Array.isArray(value) &&
    value.metadata &&
    typeof value.metadata === "object"
  ) {
    delete value.metadata.sourceRefs;
    if (Object.keys(value.metadata).length === 0) delete value.metadata;
  }
  for (const child of Object.values(value)) stripMetadataSourceRefs(child);
  return value;
}

export function normalizeScopes(scopes) {
  if (!Array.isArray(scopes)) {
    deny("INVALID_SCOPE_SET", "Personal Model scopes must be an array.");
  }

  const requested = new Set();
  for (const scope of scopes) {
    if (typeof scope !== "string" || !KNOWN_SCOPES.has(scope)) {
      deny("UNKNOWN_SCOPE", "The Grant contains an unknown Personal Model scope.");
    }
    requested.add(scope);
  }

  return Object.freeze(
    PERSONAL_MODEL_SCOPES.filter((scope) => requested.has(scope)),
  );
}

export function hasScope(authorization, scope) {
  if (!KNOWN_SCOPES.has(scope)) {
    throw new TypeError(`Unknown Personal Model scope: ${scope}`);
  }
  return Array.isArray(authorization?.scopes) &&
    authorization.scopes.includes(scope);
}

export function requireScope(authorization, scope) {
  if (!hasScope(authorization, scope)) {
    deny(
      "SCOPE_REQUIRED",
      "The current viewer is not authorized for this operation.",
    );
  }
  return authorization;
}

function ownerProjection(snapshot) {
  return parsePersonalModelCardSnapshot({
    ...structuredClone(snapshot),
    authorization: {
      viewerMode: "owner",
      scopes: OWNER_SCOPES,
      expiresAt: null,
    },
  });
}

function authorizedReports(reports, canReadEvidence) {
  return reports.map((report) => {
    if (canReadEvidence) return report;
    return {
      ...report,
      evidenceCount: 0,
      evidenceRefs: [],
      sections: report.sections.filter((section) => section.kind !== "evidence"),
    };
  });
}

function authorizedPersonalModel(personalModel, canReadEvidence) {
  if (canReadEvidence) return personalModel;
  return {
    ...personalModel,
    faces: personalModel.faces.map(({ evidenceRefs, ...face }) => face),
  };
}

function authorizedTime(time, canReadEvidence) {
  if (canReadEvidence) return time;
  return {
    ...time,
    days: time.days.map((day) => ({
      ...day,
      events: day.events.map(({ evidenceRef, ...event }) => event),
    })),
  };
}

function authorizedConnectors(connectors, canConnect) {
  if (canConnect) return connectors;
  return connectors.map(({ sessionId, ...connector }) => connector);
}

function authorizedProjection(snapshot, authorization) {
  const scopes = normalizeScopes(authorization.scopes);
  const canReadCard = scopes.includes("card:read");
  const canReadIdentity = scopes.includes("identity:read");
  const canReadEvidence = scopes.includes("evidence:read");
  const projected = {
    schemaVersion: snapshot.schemaVersion,
    projection: "authorized",
    model:
      canReadCard || canReadIdentity
        ? snapshot.model
        : { id: snapshot.model.id },
    authorization: {
      viewerMode: "authorized",
      grantId: authorization.grantId,
      scopes,
      expiresAt: authorization.expiresAt,
      audience: authorization.audience,
    },
  };

  if (canReadCard) {
    projected.card = snapshot.card;
    // Root and Faces are the model content displayed on the Personal Card.
    // Public viewers remain on the stricter E1 projection below.
    projected.personalModel = authorizedPersonalModel(
      snapshot.personalModel,
      canReadEvidence,
    );
  }
  if (canReadIdentity) projected.identity = snapshot.identity;
  if (scopes.includes("now:read")) projected.now = snapshot.now;
  if (scopes.includes("rewind:read")) {
    projected.time = authorizedTime(snapshot.time, canReadEvidence);
  }
  if (scopes.includes("connectors:read")) {
    projected.connectors = authorizedConnectors(
      snapshot.connectors,
      scopes.includes("connectors:connect"),
    );
  }
  if (scopes.includes("reports:read")) {
    projected.reports = authorizedReports(
      snapshot.reports,
      canReadEvidence,
    );
  }

  const detached = structuredClone(projected);
  if (!canReadEvidence) stripMetadataSourceRefs(detached);
  return deepFreeze(detached);
}

export function projectSnapshotByScope(snapshot, authorization) {
  if (!authorization || typeof authorization !== "object") {
    throw new TypeError("Snapshot authorization context is required.");
  }

  if (authorization.viewerMode === "owner") {
    return ownerProjection(snapshot);
  }
  if (authorization.viewerMode === "public") {
    // This exact E1 projection rejects every private top-level field.
    return projectPublicPersonalModelCardSnapshot(snapshot);
  }
  if (authorization.viewerMode === "authorized") {
    if (
      typeof authorization.grantId !== "string" ||
      typeof authorization.expiresAt !== "string" ||
      typeof authorization.audience !== "string"
    ) {
      deny("GRANT_CLAIMS_INVALID", "Authorized projection requires a valid Grant.");
    }
    return authorizedProjection(snapshot, authorization);
  }

  deny("VIEWER_MODE_INVALID", "The Personal Model viewer mode is invalid.");
}
