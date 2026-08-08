import { parsePersonalModelEvidenceResponse } from "../contracts/personal-model-card.mjs";

const SOURCE_TYPE_ALIASES = Object.freeze({
  memory: "persome-memory",
  activity: "persome-activity",
  "persome-memory": "persome-memory",
  "persome-activity": "persome-activity",
});

function nullableString(value) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function normalizedSupports(resolved) {
  if (Array.isArray(resolved.supports)) return resolved.supports;
  const relationship = ["direct", "indirect"].includes(
    resolved.relationship ?? resolved.support,
  )
    ? resolved.relationship ?? resolved.support
    : "direct";
  return (Array.isArray(resolved.supportedClaims)
    ? resolved.supportedClaims
    : [resolved.supportedClaim ?? resolved.claim]
  )
    .filter((claim) => typeof claim === "string" && claim.trim())
    .map((claim) => ({ claim: claim.trim(), relationship }));
}

/**
 * Product-owned adapter for an injected Persome evidence resolver. A resolver
 * may return the canonical response directly or the flatter fields documented
 * below; in both cases the result crosses the shared validation boundary.
 */
export function parseResolvedPersonalModelEvidence({
  modelId,
  reference,
  resolved,
}) {
  if (resolved === null || typeof resolved !== "object") {
    throw new TypeError("The Evidence resolver returned no record.");
  }

  if (
    resolved.source &&
    resolved.supports &&
    resolved.availability
  ) {
    return parsePersonalModelEvidenceResponse({
      ...resolved,
      modelId: resolved.modelId ?? modelId,
      reference: resolved.reference ?? reference,
    });
  }

  const sourceType = SOURCE_TYPE_ALIASES[
    resolved.sourceType ?? resolved.type
  ];
  if (!sourceType) {
    throw new TypeError("The Evidence resolver returned an unknown source type.");
  }

  return parsePersonalModelEvidenceResponse({
    modelId: resolved.modelId ?? modelId,
    reference: resolved.reference ?? reference,
    source: {
      type: sourceType,
      originalTime: nullableString(
        resolved.originalTime ?? resolved.occurredAt ?? resolved.timestamp,
      ),
      application: nullableString(
        resolved.sourceApp ?? resolved.application ?? resolved.app,
      ),
      title: nullableString(resolved.sourceTitle ?? resolved.title),
      ...(nullableString(resolved.recordId ?? resolved.id)
        ? { recordId: nullableString(resolved.recordId ?? resolved.id) }
        : {}),
    },
    supports: normalizedSupports(resolved),
    availability: {
      status: "available",
    },
    content: Object.hasOwn(resolved, "content") ? resolved.content : null,
    ...(typeof resolved.receipt === "string"
      ? { receipt: resolved.receipt }
      : {}),
    ...(typeof resolved.capturedAt === "string"
      ? { capturedAt: resolved.capturedAt }
      : {}),
  });
}

export function connectorReceiptEvidence({ modelId, reference, event }) {
  const claim =
    typeof event.summary === "string" && event.summary.trim()
      ? event.summary.trim()
      : null;
  return parsePersonalModelEvidenceResponse({
    modelId,
    reference,
    source: {
      type: "agent-connector-receipt",
      originalTime: event.occurredAt,
      application: event.connectorId,
      title: event.tool || event.eventType || "Agent connector event",
      recordId: event.eventId,
    },
    supports: claim
      ? [{ claim, relationship: "indirect" }]
      : [],
    availability: { status: "available" },
    content: {
      eventId: event.eventId,
      eventType: event.eventType,
      tool: event.tool,
      summary: event.summary,
    },
    receipt: event.eventId,
    capturedAt: event.occurredAt,
  });
}

export function coastFrameEvidence({ modelId, reference, frameId, content }) {
  const claim =
    typeof content?.supportedClaim === "string"
      ? content.supportedClaim.trim()
      : "";
  return parsePersonalModelEvidenceResponse({
    modelId,
    reference,
    source: {
      type: "coast-frame",
      originalTime:
        typeof content?.timestamp === "string" ? content.timestamp : null,
      application:
        typeof content?.application === "string"
          ? content.application
          : "Coast",
      title: typeof content?.title === "string" ? content.title : null,
      recordId: frameId,
    },
    supports: claim
      ? [{ claim, relationship: "direct" }]
      : [],
    availability: { status: "available" },
    content,
    ...(typeof content?.timestamp === "string"
      ? { capturedAt: content.timestamp }
      : {}),
  });
}
