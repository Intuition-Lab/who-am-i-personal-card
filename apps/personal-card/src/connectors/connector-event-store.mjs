import { createHash } from "node:crypto";
import { mkdir, open, readFile } from "node:fs/promises";
import path from "node:path";

import { assertSafeModelId } from "../contracts/personal-model-provider.mjs";
import {
  ConnectorIsolationError,
  assertSafeConnectorId,
  assertSafeConnectorSessionId,
} from "./connector-session-service.mjs";

function assertSessionIdentity(session) {
  if (session === null || typeof session !== "object") {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_SESSION",
      "A Connector Session is required.",
    );
  }
  assertSafeModelId(session.modelId);
  assertSafeConnectorId(session.connectorId);
  assertSafeConnectorSessionId(session.sessionId);
  if (typeof session.grantId !== "string" || session.grantId.length === 0) {
    throw new ConnectorIsolationError(
      "INVALID_GRANT_ID",
      "The Connector Session Grant ID is invalid.",
    );
  }
  return session;
}

function optionalString(value, field) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EVENT",
      `Connector event ${field} must be a string.`,
    );
  }
  return value;
}

function eventHashInput(record) {
  return {
    modelId: record.modelId,
    connectorId: record.connectorId,
    sessionId: record.sessionId,
    grantId: record.grantId,
    eventType: record.eventType,
    requestId: record.requestId,
    tool: record.tool,
    receipt: record.receipt,
    summary: record.summary,
    occurredAt: record.occurredAt,
    durationMs: record.durationMs,
  };
}

export function stableConnectorEventHash(record) {
  return createHash("sha256")
    .update(JSON.stringify(eventHashInput(record)))
    .digest("hex");
}

function createEventRecord(session, event, clock) {
  assertSessionIdentity(session);
  if (event === null || typeof event !== "object") {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EVENT",
      "A Connector event is required.",
    );
  }

  const eventType = optionalString(event.eventType, "eventType") ?? "tools/call";
  const requestId = event.requestId ?? null;
  if (
    requestId !== null &&
    typeof requestId !== "string" &&
    typeof requestId !== "number"
  ) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EVENT",
      "Connector event requestId must be a string or number.",
    );
  }

  const receipt = optionalString(event.receipt, "receipt");
  if (receipt !== null && !receipt.startsWith(`${session.modelId}:`)) {
    throw new ConnectorIsolationError(
      "EVIDENCE_MODEL_MISMATCH",
      "The event receipt belongs to another Personal Model.",
      { status: 403 },
    );
  }

  const occurredAt = event.occurredAt ?? clock().toISOString();
  if (
    typeof occurredAt !== "string" ||
    !Number.isFinite(new Date(occurredAt).getTime())
  ) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EVENT",
      "Connector event occurredAt must be an ISO date-time.",
    );
  }

  const durationMs = event.durationMs ?? null;
  if (
    durationMs !== null &&
    (!Number.isFinite(durationMs) || durationMs < 0)
  ) {
    throw new ConnectorIsolationError(
      "INVALID_CONNECTOR_EVENT",
      "Connector event durationMs must be non-negative.",
    );
  }

  const core = {
    modelId: session.modelId,
    connectorId: session.connectorId,
    sessionId: session.sessionId,
    grantId: session.grantId,
    eventType,
    requestId,
    tool: optionalString(event.tool, "tool"),
    receipt,
    summary: optionalString(event.summary, "summary"),
    occurredAt: new Date(occurredAt).toISOString(),
    durationMs,
  };
  return Object.freeze({
    eventId: stableConnectorEventHash(core),
    ...core,
  });
}

function assertStoredEvent(record, expected) {
  if (
    record === null ||
    typeof record !== "object" ||
    record.modelId !== expected.modelId ||
    record.connectorId !== expected.connectorId ||
    record.sessionId !== expected.sessionId ||
    (expected.grantId !== undefined && record.grantId !== expected.grantId) ||
    typeof record.grantId !== "string" ||
    record.grantId.length === 0 ||
    record.eventId !== stableConnectorEventHash(record)
  ) {
    throw new ConnectorIsolationError(
      "CONNECTOR_EVENT_LOG_CORRUPT",
      "The Connector event log failed its identity check.",
      { status: 500 },
    );
  }
  return Object.freeze(record);
}

export class ConnectorEventStore {
  constructor({
    runtimeRoot = path.resolve(".whoami-runtime"),
    clock = () => new Date(),
    sessionService,
  } = {}) {
    if (typeof sessionService?.resolve !== "function") {
      throw new TypeError(
        "ConnectorEventStore requires a ConnectorSessionService.",
      );
    }
    this.runtimeRoot = path.resolve(runtimeRoot);
    this.clock = clock;
    this.sessionService = sessionService;
    this.writeChains = new Map();
  }

  eventLogPath({ modelId, connectorId, sessionId }) {
    assertSafeModelId(modelId);
    assertSafeConnectorId(connectorId);
    assertSafeConnectorSessionId(sessionId);
    return path.join(
      this.runtimeRoot,
      "models",
      modelId,
      "connectors",
      connectorId,
      "sessions",
      sessionId,
      "events.jsonl",
    );
  }

  async appendEvent(session, event) {
    assertSessionIdentity(session);
    const activeSession = this.sessionService.resolve(session.sessionId, {
      viewerSessionId: session.viewerSessionId,
      modelId: session.modelId,
      connectorId: session.connectorId,
    });
    if (activeSession.grantId !== session.grantId) {
      throw new ConnectorIsolationError(
        "CONNECTOR_GRANT_MISMATCH",
        "The Connector Session Grant does not match.",
        { status: 403 },
      );
    }

    const record = createEventRecord(activeSession, event, this.clock);
    const logPath = this.eventLogPath(activeSession);
    const previous = this.writeChains.get(logPath) ?? Promise.resolve();
    const pending = previous
      .catch(() => {})
      .then(async () => {
        await mkdir(path.dirname(logPath), {
          recursive: true,
          mode: 0o700,
        });
        const file = await open(logPath, "a", 0o600);
        try {
          await file.appendFile(`${JSON.stringify(record)}\n`, "utf8");
        } finally {
          await file.close();
        }
      });
    this.writeChains.set(logPath, pending);

    try {
      await pending;
    } finally {
      if (this.writeChains.get(logPath) === pending) {
        this.writeChains.delete(logPath);
      }
    }
    return record;
  }

  async readEvents(identity) {
    const logPath = this.eventLogPath(identity);
    let text;
    try {
      text = await readFile(logPath, "utf8");
    } catch (error) {
      if (error?.code === "ENOENT") {
        return Object.freeze([]);
      }
      throw new ConnectorIsolationError(
        "CONNECTOR_EVENT_LOG_UNAVAILABLE",
        "The Connector event log is unavailable.",
        { status: 503 },
      );
    }

    const lines = text.split("\n");
    let lastContentIndex = lines.length - 1;
    while (
      lastContentIndex >= 0 &&
      lines[lastContentIndex].trim().length === 0
    ) {
      lastContentIndex -= 1;
    }

    const records = [];
    for (let index = 0; index <= lastContentIndex; index += 1) {
      if (lines[index].trim().length === 0) {
        continue;
      }

      let record;
      try {
        record = JSON.parse(lines[index]);
      } catch {
        if (index === lastContentIndex) {
          break;
        }
        throw new ConnectorIsolationError(
          "CONNECTOR_EVENT_LOG_CORRUPT",
          "The Connector event log contains a damaged record.",
          { status: 500 },
        );
      }
      records.push(assertStoredEvent(record, identity));
    }

    return Object.freeze(records);
  }
}
