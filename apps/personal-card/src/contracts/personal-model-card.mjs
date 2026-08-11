import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import personalModelCardSchema from "./personal-model-card.schema.json" with {
  type: "json",
};
import publicPersonalModelCardSchema from "./public-personal-model-card.schema.json" with {
  type: "json",
};
import personalModelGrantSchema from "./personal-model-grant.schema.json" with {
  type: "json",
};
import personalModelEvidenceSchema from "./personal-model-evidence.schema.json" with {
  type: "json",
};
import personalModelCorrectionSchema from "./personal-model-correction.schema.json" with {
  type: "json",
};

export const PERSONAL_MODEL_CARD_SCHEMA_ID = personalModelCardSchema.$id;
export const PERSONAL_MODEL_GRANT_SCHEMA_ID = personalModelGrantSchema.$id;
export const PERSONAL_MODEL_EVIDENCE_SCHEMA_ID = personalModelEvidenceSchema.$id;
export const PERSONAL_MODEL_CORRECTION_SCHEMA_ID =
  personalModelCorrectionSchema.$id;

const ajv = new Ajv2020({
  allErrors: true,
  strict: true,
  validateFormats: true,
});
addFormats(ajv);

const validateSchema = ajv.compile(personalModelCardSchema);
const validatePublicSchema = ajv.compile(publicPersonalModelCardSchema);
const validateGrantSchema = ajv.compile(personalModelGrantSchema);
const validateEvidenceSchema = ajv.compile(personalModelEvidenceSchema);
const validateCorrectionSchema = ajv.compile(personalModelCorrectionSchema);
const validatedFullSnapshots = new WeakSet();

export class PersonalModelCardValidationError extends TypeError {
  constructor(issues) {
    const summary = issues
      .slice(0, 3)
      .map(({ path, message }) => `${path || "/"} ${message}`)
      .join("; ");
    super(`Invalid PersonalModelCardSnapshot: ${summary}`);
    this.name = "PersonalModelCardValidationError";
    this.issues = Object.freeze(issues.map((issue) => Object.freeze(issue)));
  }
}

function cloneProviderPayload(input) {
  try {
    return structuredClone(input);
  } catch {
    throw new PersonalModelCardValidationError([
      {
        path: "/",
        keyword: "clone",
        message: "must be structured-cloneable data",
      },
    ]);
  }
}

function schemaIssues(errors) {
  return (errors ?? []).map((error) => ({
    path: error.instancePath || "/",
    keyword: error.keyword,
    message: error.message ?? "failed schema validation",
  }));
}

function evidenceOwnershipKeys(snapshot) {
  return new Set([snapshot.model.id]);
}

function metadataSourceReferences(value, path = "") {
  const references = [];
  if (value === null || typeof value !== "object") return references;
  if (Array.isArray(value)) {
    value.forEach((child, index) => {
      references.push(
        ...metadataSourceReferences(child, `${path}/${index}`),
      );
    });
    return references;
  }

  if (Array.isArray(value.metadata?.sourceRefs)) {
    value.metadata.sourceRefs.forEach((reference, index) => {
      references.push({
        path: `${path}/metadata/sourceRefs/${index}`,
        value: reference,
      });
    });
  }
  for (const [key, child] of Object.entries(value)) {
    if (key !== "metadata") {
      references.push(...metadataSourceReferences(child, `${path}/${key}`));
    }
  }
  return references;
}

function evidenceReferences(snapshot) {
  const references = [];

  for (const [faceIndex, face] of snapshot.personalModel.faces.entries()) {
    for (const [referenceIndex, reference] of (
      face.evidenceRefs ?? []
    ).entries()) {
      references.push({
        path: `/personalModel/faces/${faceIndex}/evidenceRefs/${referenceIndex}`,
        value: reference,
      });
    }
  }

  for (const [dayIndex, day] of snapshot.time.days.entries()) {
    for (const [eventIndex, event] of day.events.entries()) {
      if (event.evidenceRef !== undefined) {
        references.push({
          path: `/time/days/${dayIndex}/events/${eventIndex}/evidenceRef`,
          value: event.evidenceRef,
        });
      }
    }
  }

  for (const [reportIndex, report] of snapshot.reports.entries()) {
    for (const [referenceIndex, reference] of report.evidenceRefs.entries()) {
      references.push({
        path: `/reports/${reportIndex}/evidenceRefs/${referenceIndex}`,
        value: reference,
      });
    }
  }

  references.push(...metadataSourceReferences(snapshot));

  return references;
}

function ownershipIssues(snapshot) {
  const issues = [];
  const connectorIds = new Set(
    snapshot.connectors.map((connector) => connector.id),
  );

  for (const [reportIndex, report] of snapshot.reports.entries()) {
    if (report.modelId !== snapshot.model.id) {
      issues.push({
        path: `/reports/${reportIndex}/modelId`,
        keyword: "modelOwnership",
        message: `must equal active model id "${snapshot.model.id}"`,
      });
    }

    if (!connectorIds.has(report.connectorId)) {
      issues.push({
        path: `/reports/${reportIndex}/connectorId`,
        keyword: "connectorOwnership",
        message: "must reference a connector in the same Snapshot",
      });
    }

    if (report.evidenceCount !== report.evidenceRefs.length) {
      issues.push({
        path: `/reports/${reportIndex}/evidenceCount`,
        keyword: "evidenceCount",
        message: "must equal the number of evidenceRefs",
      });
    }
  }

  const allowedEvidenceOwners = evidenceOwnershipKeys(snapshot);
  for (const reference of evidenceReferences(snapshot)) {
    const owner = reference.value.split(":", 1)[0];
    if (!allowedEvidenceOwners.has(owner)) {
      issues.push({
        path: reference.path,
        keyword: "modelOwnership",
        message: `must belong to active model "${snapshot.model.id}"`,
      });
    }
  }

  return issues;
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

function cloneWithoutMetadataSourceRefs(value) {
  const clone = structuredClone(value);

  function strip(current) {
    if (current === null || typeof current !== "object") return;
    if (
      !Array.isArray(current) &&
      current.metadata &&
      typeof current.metadata === "object"
    ) {
      delete current.metadata.sourceRefs;
      if (Object.keys(current.metadata).length === 0) {
        delete current.metadata;
      }
    }
    for (const child of Object.values(current)) strip(child);
  }

  strip(clone);
  return clone;
}

function legacyEvidenceClaim(content) {
  if (typeof content === "string" && content.trim()) return content.trim();
  if (content === null || typeof content !== "object") return null;

  for (const candidate of [
    content.face?.text,
    content.event?.detail,
    content.report?.summary,
    content.detail,
    content.text,
    content.title,
  ]) {
    if (typeof candidate === "string" && candidate.trim()) {
      return candidate.trim();
    }
  }
  return null;
}

function normalizeLegacyEvidence(evidence) {
  if (
    Object.hasOwn(evidence, "source") ||
    Object.hasOwn(evidence, "supports") ||
    Object.hasOwn(evidence, "availability")
  ) {
    return evidence;
  }

  const claim = legacyEvidenceClaim(evidence.content);
  return {
    ...evidence,
    source: {
      type: "derived-summary",
      originalTime: null,
      application: null,
      title:
        typeof evidence.content?.title === "string"
          ? evidence.content.title
          : null,
    },
    supports: claim
      ? [{ claim, relationship: "indirect" }]
      : [],
    availability: {
      status: "unavailable",
      reason: "original-source-unavailable",
    },
  };
}

function normalizeLegacyCorrection(correction) {
  if (Object.hasOwn(correction, "status")) return correction;
  return {
    modelId: correction.modelId,
    status: "accepted",
    receipt:
      typeof correction.receipt === "string" ? correction.receipt : null,
    affected: [],
    verification: {
      status: "unverified",
      refreshed: false,
      oldConclusionDeprioritized: false,
      previousUpdatedAt: null,
      updatedAt: null,
    },
  };
}

/**
 * The single ingress from unknown Provider data into UI-safe Snapshot data.
 * It returns a detached, recursively frozen value or throws.
 */
export function parsePersonalModelCardSnapshot(input) {
  const snapshot = cloneProviderPayload(input);

  if (!validateSchema(snapshot)) {
    throw new PersonalModelCardValidationError(
      schemaIssues(validateSchema.errors),
    );
  }

  const semanticIssues = ownershipIssues(snapshot);
  if (semanticIssues.length > 0) {
    throw new PersonalModelCardValidationError(semanticIssues);
  }

  const frozenSnapshot = deepFreeze(snapshot);
  validatedFullSnapshots.add(frozenSnapshot);
  return frozenSnapshot;
}

export function parsePublicPersonalModelCardSnapshot(input) {
  const snapshot = cloneProviderPayload(input);

  if (!validatePublicSchema(snapshot)) {
    throw new PersonalModelCardValidationError(
      schemaIssues(validatePublicSchema.errors),
    );
  }

  const references = metadataSourceReferences(snapshot);
  if (references.length > 0) {
    throw new PersonalModelCardValidationError(
      references.map(({ path }) => ({
        path,
        keyword: "evidenceScope",
        message: "public projections cannot include Evidence references",
      })),
    );
  }

  return deepFreeze(snapshot);
}

export function projectPublicPersonalModelCardSnapshot(snapshot) {
  if (!validatedFullSnapshots.has(snapshot)) {
    throw new PersonalModelCardValidationError([
      {
        path: "/",
        keyword: "validatedSnapshot",
        message: "must first pass parsePersonalModelCardSnapshot",
      },
    ]);
  }

  return parsePublicPersonalModelCardSnapshot({
    schemaVersion: snapshot.schemaVersion,
    projection: "public",
    model: snapshot.model,
    authorization: {
      viewerMode: "public",
      scopes: ["card:read", "identity:read"],
      expiresAt: null,
    },
    card: cloneWithoutMetadataSourceRefs(snapshot.card),
    identity: cloneWithoutMetadataSourceRefs(snapshot.identity),
  });
}

export function parsePersonalModelGrantClaims(input) {
  const claims = cloneProviderPayload(input);

  if (!validateGrantSchema(claims)) {
    throw new PersonalModelCardValidationError(
      schemaIssues(validateGrantSchema.errors),
    );
  }

  return deepFreeze(claims);
}

export function parsePersonalModelEvidenceResponse(input) {
  const evidence = normalizeLegacyEvidence(cloneProviderPayload(input));

  if (!validateEvidenceSchema(evidence)) {
    throw new PersonalModelCardValidationError(
      schemaIssues(validateEvidenceSchema.errors),
    );
  }

  if (!evidence.reference.startsWith(`${evidence.modelId}:`)) {
    throw new PersonalModelCardValidationError([
      {
        path: "/reference",
        keyword: "modelOwnership",
        message: `must belong to model "${evidence.modelId}"`,
      },
    ]);
  }

  if (
    ["persome-memory", "persome-activity"].includes(evidence.source.type) &&
    (
      evidence.availability.status !== "available" ||
      evidence.source.originalTime === null ||
      evidence.supports.length === 0
    )
  ) {
    throw new PersonalModelCardValidationError([
      {
        path: "/source",
        keyword: "originalSource",
        message:
          "original Persome sources must be available, timestamped, and support at least one claim",
      },
    ]);
  }

  if (
    evidence.source.type === "derived-summary" &&
    evidence.supports.some(({ relationship }) => relationship !== "indirect")
  ) {
    throw new PersonalModelCardValidationError([
      {
        path: "/supports",
        keyword: "derivedSupport",
        message: "derived summaries may only provide indirect support",
      },
    ]);
  }

  return deepFreeze(evidence);
}

export function parsePersonalModelCorrectionResponse(input) {
  const correction = normalizeLegacyCorrection(cloneProviderPayload(input));

  if (!validateCorrectionSchema(correction)) {
    throw new PersonalModelCardValidationError(
      schemaIssues(validateCorrectionSchema.errors),
    );
  }

  for (const [index, affected] of correction.affected.entries()) {
    if (
      affected.reference !== undefined &&
      !affected.reference.startsWith(`${correction.modelId}:`)
    ) {
      throw new PersonalModelCardValidationError([
        {
          path: `/affected/${index}/reference`,
          keyword: "modelOwnership",
          message: `must belong to model "${correction.modelId}"`,
        },
      ]);
    }
  }

  return deepFreeze(correction);
}
