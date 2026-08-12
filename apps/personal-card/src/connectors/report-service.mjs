import { createHash } from "node:crypto";

import { ConnectorIsolationError } from "./connector-session-service.mjs";
import {
  connectorDisplayName,
  contextTypeForEvent,
  isContextReadEvent,
  recordedOutcomeForEvent,
} from "./connector-event-semantics.mjs";

function freezeReport(report) {
  for (const section of report.sections) {
    Object.freeze(section);
  }
  Object.freeze(report.sections);
  Object.freeze(report.evidenceRefs);
  return Object.freeze(report);
}

function reportIdFor(session, events) {
  return `report_${createHash("sha256")
    .update(
      JSON.stringify({
        modelId: session.modelId,
        connectorId: session.connectorId,
        sessionId: session.sessionId,
        grantId: session.grantId,
        eventIds: events.map(({ eventId }) => eventId),
      }),
    )
    .digest("hex")
    .slice(0, 24)}`;
}

function formatActions(events) {
  return events
    .map((event) => {
      const action = event.summary ?? event.tool ?? event.eventType;
      const outcome = event.status === "error" ? "（失败）" : "";
      return `${event.occurredAt} · ${action}${outcome}`;
    })
    .join("\n");
}

function unique(values) {
  return [...new Set(values.filter((value) => value))];
}

export class ReportService {
  constructor({ sessionService, eventStore }) {
    if (typeof sessionService?.resolve !== "function") {
      throw new TypeError("ReportService requires a ConnectorSessionService.");
    }
    if (typeof eventStore?.readEvents !== "function") {
      throw new TypeError("ReportService requires a ConnectorEventStore.");
    }
    this.sessionService = sessionService;
    this.eventStore = eventStore;
  }

  async listReports({
    sessionId,
    viewerSessionId,
    modelId,
    connectorId,
  }) {
    const session = this.sessionService.resolve(sessionId, {
      viewerSessionId,
      modelId,
      connectorId,
    });
    const events = await this.eventStore.readEvents({
      modelId: session.modelId,
      connectorId: session.connectorId,
      sessionId: session.sessionId,
      grantId: session.grantId,
    });
    if (events.length === 0) {
      return Object.freeze([]);
    }

    if (
      events.some(
        (event) =>
          event.modelId !== session.modelId ||
          event.connectorId !== session.connectorId ||
          event.sessionId !== session.sessionId ||
          event.grantId !== session.grantId,
      )
    ) {
      throw new ConnectorIsolationError(
        "REPORT_EVENT_IDENTITY_MISMATCH",
        "Connector events cannot be combined across sessions.",
        { status: 500 },
      );
    }

    // A successful connection is a grant receipt, not evidence that the agent
    // actually used or understood the Personal Model. Reports begin only with
    // observable post-connection tool activity.
    const reportableEvents = events.filter(
      (event) =>
        event.eventType !== "connector/connected"
        && event.tool !== "connectAgent",
    );
    if (reportableEvents.length === 0) {
      return Object.freeze([]);
    }

    const orderedEvents = [...reportableEvents].sort((left, right) =>
      left.occurredAt.localeCompare(right.occurredAt)
    );
    const evidenceRefs = unique(orderedEvents.map(({ receipt }) => receipt));
    const readEvents = orderedEvents.filter(isContextReadEvent);
    const contextTypes = unique(readEvents.map(contextTypeForEvent));
    const outcomes = unique(orderedEvents.flatMap(recordedOutcomeForEvent));
    const updatedAt = orderedEvents.reduce(
      (latest, event) =>
        event.occurredAt > latest ? event.occurredAt : latest,
      orderedEvents[0].occurredAt,
    );
    const connectorName = connectorDisplayName(session.connectorId);
    const sections = [
      {
        kind: "lead",
        title: "Agent 做了什么",
        body: formatActions(orderedEvents),
      },
      {
        kind: contextTypes.length > 0 ? "understanding" : "note",
        title: "读取的上下文",
        body: contextTypes.length > 0
          ? `${connectorName} 实际读取了：${contextTypes.join("、")}。`
          : "这次会话没有记录到 Personal Model 上下文读取。",
      },
      {
        kind: outcomes.length > 0 ? "understanding" : "note",
        title: "结果摘要",
        body: outcomes.length > 0
          ? outcomes.join("；")
          : "Connector 没有记录可展示的结果摘要。",
      },
      {
        kind: evidenceRefs.length > 0 ? "evidence" : "note",
        title: "证据和时间",
        body: evidenceRefs.length > 0
          ? `${evidenceRefs.length} 条 Evidence；首次记录 ${orderedEvents[0].occurredAt}，最近记录 ${updatedAt}。`
          : `没有 Evidence 回执；首次记录 ${orderedEvents[0].occurredAt}，最近记录 ${updatedAt}。`,
      },
    ];
    const report = freezeReport({
      id: reportIdFor(session, events),
      modelId: session.modelId,
      connectorId: session.connectorId,
      title: `${connectorName} · Personal Model 使用报告`,
      summary: contextTypes.length > 0
        ? `${connectorName} 记录了 ${orderedEvents.length} 个实际动作，其中 ${readEvents.length} 次读取 ${contextTypes.join("、")}。`
        : `${connectorName} 记录了 ${orderedEvents.length} 个实际动作，没有记录到上下文读取。`,
      updatedAt,
      readCount: readEvents.length,
      evidenceCount: evidenceRefs.length,
      sections,
      evidenceRefs,
    });

    return Object.freeze([report]);
  }
}
