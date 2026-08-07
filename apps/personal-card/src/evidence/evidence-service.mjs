import { parsePersonalModelEvidenceResponse } from "../contracts/personal-model-card.mjs";
import { assertSafeModelId } from "../contracts/personal-model-provider.mjs";
import {
  ConnectorIsolationError,
  assertSafeViewerSessionId,
} from "../connectors/connector-session-service.mjs";

const SAFE_FRAME_ID = /^[A-Za-z0-9_-]{1,180}$/;

function assertSafeFrameId(frameId) {
  if (
    typeof frameId !== "string" ||
    !SAFE_FRAME_ID.test(frameId) ||
    frameId.includes("..")
  ) {
    throw new ConnectorIsolationError(
      "INVALID_COAST_FRAME_ID",
      "The Coast frame ID is invalid.",
    );
  }
  return frameId;
}

function allowlistKey(viewerSessionId, modelId) {
  return JSON.stringify([viewerSessionId, modelId]);
}

function assertModelReference(modelId, reference) {
  assertSafeModelId(modelId);
  if (
    typeof reference !== "string" ||
    !reference.startsWith(`${modelId}:`)
  ) {
    throw new ConnectorIsolationError(
      "EVIDENCE_MODEL_MISMATCH",
      "The Evidence reference belongs to another Personal Model.",
      { status: 403 },
    );
  }
}

export class EvidenceService {
  constructor({
    providerRegistry,
    sessionService,
    loadCoastFrame = async () => null,
  }) {
    if (typeof providerRegistry?.resolve !== "function") {
      throw new TypeError("EvidenceService requires a ProviderRegistry.");
    }
    if (typeof sessionService?.resolve !== "function") {
      throw new TypeError(
        "EvidenceService requires a ConnectorSessionService.",
      );
    }
    if (typeof loadCoastFrame !== "function") {
      throw new TypeError("loadCoastFrame must be a function.");
    }
    this.providerRegistry = providerRegistry;
    this.sessionService = sessionService;
    this.loadCoastFrame = loadCoastFrame;
    this.coastFrames = new Map();
  }

  async getEvidence({
    viewerSessionId,
    activeModelId,
    connectorSessionId,
    reference,
  }) {
    assertSafeViewerSessionId(viewerSessionId);
    assertModelReference(activeModelId, reference);
    const connectorSession = this.sessionService.resolve(
      connectorSessionId,
      {
        viewerSessionId,
        modelId: activeModelId,
        requiredScope: "evidence:read",
      },
    );
    const provider = this.providerRegistry.resolve(activeModelId);
    const evidence = await provider.getEvidence(
      activeModelId,
      reference,
      {
        grantId: connectorSession.grantId,
        scopes: connectorSession.scopes,
      },
    );
    if (
      evidence?.modelId !== activeModelId ||
      evidence?.reference !== reference
    ) {
      throw new ConnectorIsolationError(
        "EVIDENCE_RESPONSE_MISMATCH",
        "The Evidence response belongs to another Personal Model.",
        { status: 502 },
      );
    }
    return evidence;
  }

  allowCoastFrame({ viewerSessionId, modelId, frameId }) {
    assertSafeViewerSessionId(viewerSessionId);
    assertSafeModelId(modelId);
    assertSafeFrameId(frameId);
    const key = allowlistKey(viewerSessionId, modelId);
    const allowed = this.coastFrames.get(key) ?? new Set();
    allowed.add(frameId);
    this.coastFrames.set(key, allowed);
  }

  async getCoastFrame({
    viewerSessionId,
    activeModelId,
    reference,
  }) {
    assertSafeViewerSessionId(viewerSessionId);
    assertModelReference(activeModelId, reference);
    const prefix = `${activeModelId}:coast:`;
    if (!reference.startsWith(prefix)) {
      throw new ConnectorIsolationError(
        "INVALID_COAST_REFERENCE",
        "The Evidence reference is not a Coast frame.",
      );
    }
    const frameId = assertSafeFrameId(reference.slice(prefix.length));
    const allowed = this.coastFrames.get(
      allowlistKey(viewerSessionId, activeModelId),
    );
    if (!allowed?.has(frameId)) {
      throw new ConnectorIsolationError(
        "COAST_FRAME_NOT_AUTHORIZED",
        "The Coast frame is not authorized for this viewer session.",
        { status: 403 },
      );
    }

    const content = await this.loadCoastFrame({
      viewerSessionId,
      modelId: activeModelId,
      frameId,
    });
    if (content === null || content === undefined) {
      throw new ConnectorIsolationError(
        "COAST_FRAME_NOT_FOUND",
        "The Coast frame was not found.",
        { status: 404 },
      );
    }
    return parsePersonalModelEvidenceResponse({
      modelId: activeModelId,
      reference,
      content,
    });
  }

  revokeCoastFramesForModelSwitch(viewerSessionId, activeModelId) {
    assertSafeViewerSessionId(viewerSessionId);
    assertSafeModelId(activeModelId);
    let revokedCount = 0;

    for (const key of this.coastFrames.keys()) {
      const [keyViewerSessionId, keyModelId] = JSON.parse(key);
      if (
        keyViewerSessionId === viewerSessionId &&
        keyModelId !== activeModelId
      ) {
        revokedCount += this.coastFrames.get(key).size;
        this.coastFrames.delete(key);
      }
    }
    return revokedCount;
  }
}
