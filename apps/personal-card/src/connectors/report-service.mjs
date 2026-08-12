import { createHash } from "node:crypto";

import { ConnectorIsolationError } from "./connector-session-service.mjs";

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

    const evidenceRefs = [
      ...new Set(
        reportableEvents.map(({ receipt }) => receipt).filter((receipt) => receipt),
      ),
    ];
    const updatedAt = reportableEvents.reduce(
      (latest, event) =>
        event.occurredAt > latest ? event.occurredAt : latest,
      reportableEvents[0].occurredAt,
    );
    const sections = reportableEvents.map((event) => ({
      kind: event.receipt ? "evidence" : "note",
      title: event.tool ?? event.eventType,
      body: event.summary ?? "Connector activity recorded.",
    }));
    const report = freezeReport({
      id: reportIdFor(session, reportableEvents),
      modelId: session.modelId,
      connectorId: session.connectorId,
      title: `${session.connectorId} · Context`,
      summary: `${reportableEvents.length} connector event${reportableEvents.length === 1 ? "" : "s"} recorded for this model session.`,
      updatedAt,
      readCount: reportableEvents.length,
      evidenceCount: evidenceRefs.length,
      sections,
      evidenceRefs,
    });

    return Object.freeze([report]);
  }
}
