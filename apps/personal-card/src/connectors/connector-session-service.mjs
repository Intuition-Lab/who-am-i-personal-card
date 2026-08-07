import { randomUUID } from "node:crypto";

import { assertSafeModelId } from "../contracts/personal-model-provider.mjs";

const SAFE_CONNECTOR_ID =
  /^[A-Za-z0-9](?:[A-Za-z0-9_-]{0,126}[A-Za-z0-9])?$/;
const SAFE_SESSION_ID = /^cs_[A-Za-z0-9_-]{8,160}$/;
const SAFE_VIEWER_SESSION_ID =
  /^(?:vs_[A-Za-z0-9_-]{4,160}|[A-Za-z0-9_-]{32,128})$/;

export class ConnectorIsolationError extends Error {
  constructor(code, message, { status = 400 } = {}) {
    super(message);
    this.name = "ConnectorIsolationError";
    this.code = code;
    this.status = status;
  }

  toJSON() {
    return {
      code: this.code,
      message: this.message,
    };
  }
}

export function assertSafeConnectorId(connectorId) {
  if (
    typeof connectorId !== "string" ||
    !SAFE_CONNECTOR_ID.test(connectorId) ||
    connectorId.includes("..")
  ) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_ID",
      "The Connector ID is invalid.",
    );
  }
  return connectorId;
}

export function assertSafeConnectorSessionId(sessionId) {
  if (
    typeof sessionId !== "string" ||
    !SAFE_SESSION_ID.test(sessionId) ||
    sessionId.includes("..")
  ) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_SESSION_ID",
      "The Connector Session ID is invalid.",
    );
  }
  return sessionId;
}

export function assertSafeViewerSessionId(viewerSessionId) {
  if (
    typeof viewerSessionId !== "string" ||
    !SAFE_VIEWER_SESSION_ID.test(viewerSessionId) ||
    viewerSessionId.includes("..")
  ) {
    throw new ConnectorIsolationError(
      "INVALID_VIEWER_SESSION_ID",
      "The viewer session ID is invalid.",
    );
  }
  return viewerSessionId;
}

function parseFutureExpiry(expiresAt, now) {
  if (typeof expiresAt !== "string") {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EXPIRY",
      "A Connector Session expiry is required.",
    );
  }
  const expiry = new Date(expiresAt);
  if (!Number.isFinite(expiry.getTime()) || expiry <= now) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EXPIRY",
      "The Connector Session expiry must be in the future.",
    );
  }
  return expiry.toISOString();
}

function validateScopes(scopes) {
  if (
    !Array.isArray(scopes) ||
    scopes.some((scope) => typeof scope !== "string" || scope.length === 0) ||
    new Set(scopes).size !== scopes.length
  ) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_SCOPES",
      "Connector Session scopes are invalid.",
    );
  }
  return Object.freeze([...scopes]);
}

function freezeSession(session) {
  return Object.freeze({
    ...session,
    scopes: Object.freeze([...session.scopes]),
  });
}

export class ConnectorSessionService {
  constructor({
    clock = () => new Date(),
    idFactory = () => `cs_${randomUUID().replaceAll("-", "")}`,
  } = {}) {
    this.clock = clock;
    this.idFactory = idFactory;
    this.sessions = new Map();
    this.viewerSessions = new Map();
  }

  create({
    viewerSessionId,
    modelId,
    connectorId,
    grantId,
    scopes,
    expiresAt,
  }) {
    assertSafeViewerSessionId(viewerSessionId);
    assertSafeModelId(modelId);
    assertSafeConnectorId(connectorId);
    if (typeof grantId !== "string" || grantId.length === 0) {
      throw new ConnectorIsolationError(
        "INVALID_GRANT_ID",
        "A Grant ID is required for a Connector Session.",
      );
    }

    const now = this.clock();
    const sessionId = assertSafeConnectorSessionId(this.idFactory());
    if (this.sessions.has(sessionId)) {
      throw new ConnectorIsolationError(
        "CONNECTOR_SESSION_COLLISION",
        "A unique Connector Session could not be created.",
        { status: 500 },
      );
    }

    const session = freezeSession({
      sessionId,
      viewerSessionId,
      modelId,
      connectorId,
      grantId,
      scopes: validateScopes(scopes),
      createdAt: now.toISOString(),
      expiresAt: parseFutureExpiry(expiresAt, now),
      revokedAt: null,
      revokeReason: null,
    });
    this.sessions.set(sessionId, session);

    const viewerIndex = this.viewerSessions.get(viewerSessionId) ?? new Set();
    viewerIndex.add(sessionId);
    this.viewerSessions.set(viewerSessionId, viewerIndex);
    return session;
  }

  resolve(
    sessionId,
    { viewerSessionId, modelId, connectorId, requiredScope } = {},
  ) {
    assertSafeConnectorSessionId(sessionId);
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new ConnectorIsolationError(
        "CONNECTOR_SESSION_NOT_FOUND",
        "The Connector Session was not found.",
        { status: 404 },
      );
    }
    if (session.revokedAt !== null) {
      throw new ConnectorIsolationError(
        "CONNECTOR_SESSION_REVOKED",
        "The Connector Session is no longer active.",
        { status: 403 },
      );
    }
    if (new Date(session.expiresAt) <= this.clock()) {
      this.revoke(sessionId, "expired");
      throw new ConnectorIsolationError(
        "CONNECTOR_SESSION_EXPIRED",
        "The Connector Session has expired.",
        { status: 403 },
      );
    }
    if (
      viewerSessionId !== undefined &&
      session.viewerSessionId !== viewerSessionId
    ) {
      throw new ConnectorIsolationError(
        "VIEWER_SESSION_MISMATCH",
        "The Connector Session belongs to another viewer session.",
        { status: 403 },
      );
    }
    if (modelId !== undefined && session.modelId !== modelId) {
      throw new ConnectorIsolationError(
        "CONNECTOR_MODEL_MISMATCH",
        "The Connector Session belongs to another Personal Model.",
        { status: 403 },
      );
    }
    if (connectorId !== undefined && session.connectorId !== connectorId) {
      throw new ConnectorIsolationError(
        "CONNECTOR_ID_MISMATCH",
        "The Connector Session belongs to another Connector.",
        { status: 403 },
      );
    }
    if (
      requiredScope !== undefined &&
      !session.scopes.includes(requiredScope)
    ) {
      throw new ConnectorIsolationError(
        "CONNECTOR_SCOPE_DENIED",
        "The Connector Session does not grant this operation.",
        { status: 403 },
      );
    }
    return session;
  }

  revoke(sessionId, reason = "revoked") {
    assertSafeConnectorSessionId(sessionId);
    const existing = this.sessions.get(sessionId);
    if (!existing || existing.revokedAt !== null) {
      return false;
    }
    const revoked = freezeSession({
      ...existing,
      revokedAt: this.clock().toISOString(),
      revokeReason: reason,
    });
    this.sessions.set(sessionId, revoked);
    return true;
  }

  revokeForModelSwitch(viewerSessionId, activeModelId) {
    assertSafeViewerSessionId(viewerSessionId);
    assertSafeModelId(activeModelId);
    let revokedCount = 0;

    for (const sessionId of this.viewerSessions.get(viewerSessionId) ?? []) {
      const session = this.sessions.get(sessionId);
      if (
        session &&
        session.modelId !== activeModelId &&
        this.revoke(sessionId, "model-switched")
      ) {
        revokedCount += 1;
      }
    }
    return revokedCount;
  }
}
