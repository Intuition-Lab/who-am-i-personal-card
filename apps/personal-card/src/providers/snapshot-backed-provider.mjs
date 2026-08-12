import {
  parsePersonalModelCardSnapshot,
  parsePersonalModelEvidenceResponse,
} from "../contracts/personal-model-card.mjs";
import {
  PersonalModelProvider,
  PersonalModelProviderError,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";

export function freezeCopy(value) {
  const copy = structuredClone(value);

  function freeze(current) {
    if (
      current === null ||
      typeof current !== "object" ||
      Object.isFrozen(current)
    ) {
      return current;
    }

    for (const child of Object.values(current)) {
      freeze(child);
    }
    return Object.freeze(current);
  }

  return freeze(copy);
}

export function validateSnapshotForModel(rawSnapshot, requestedModelId) {
  let snapshot;
  try {
    snapshot = parsePersonalModelCardSnapshot(rawSnapshot);
  } catch {
    throw new PersonalModelProviderError(
      "INVALID_PROVIDER_RESPONSE",
      "The Personal Model Provider returned an invalid Snapshot.",
      { status: 502 },
    );
  }

  if (snapshot.model.id !== requestedModelId) {
    throw new PersonalModelProviderError(
      "MODEL_ID_MISMATCH",
      "The Personal Model Provider returned a different model.",
      { status: 502 },
    );
  }

  return snapshot;
}

function searchableEntries(snapshot) {
  const entries = [
    {
      kind: "root",
      id: `${snapshot.model.id}:root`,
      title: "Root",
      text: snapshot.personalModel.root,
      evidenceRefs: [],
    },
    {
      kind: "identity",
      id: `${snapshot.model.id}:identity`,
      title: snapshot.model.displayName,
      text: [
        snapshot.identity.description,
        snapshot.identity.dailyLine,
        ...snapshot.identity.weeklyLetter,
      ].join("\n"),
      evidenceRefs: [],
    },
  ];

  for (const face of snapshot.personalModel.faces) {
    entries.push({
      kind: "face",
      id: face.id,
      title: "Face",
      text: face.text,
      evidenceRefs: face.evidenceRefs ?? [],
    });
  }

  for (const item of snapshot.now.items) {
    entries.push({
      kind: "now",
      id: item.id,
      title: item.title,
      text: `${item.title}\n${item.why}\n${item.when}`,
      evidenceRefs: [],
    });
  }

  for (const day of snapshot.time.days) {
    for (const event of day.events) {
      entries.push({
        kind: "event",
        id: event.id,
        title: event.title,
        text: `${event.title}\n${event.detail}`,
        evidenceRefs: event.evidenceRef ? [event.evidenceRef] : [],
      });
    }
  }

  return entries;
}

function evidenceContent(snapshot, reference) {
  for (const face of snapshot.personalModel.faces) {
    if (face.evidenceRefs?.includes(reference)) {
      return {
        kind: "face",
        face,
      };
    }
  }

  for (const day of snapshot.time.days) {
    const event = day.events.find(
      (candidate) => candidate.evidenceRef === reference,
    );
    if (event) {
      return {
        kind: "event",
        day: {
          id: day.id,
          title: day.title,
        },
        event,
      };
    }
  }

  const report = snapshot.reports.find((candidate) =>
    candidate.evidenceRefs.includes(reference),
  );
  if (report) {
    return {
      kind: "report",
      reportId: report.id,
      title: report.title,
    };
  }

  return null;
}

export class SnapshotBackedPersonalModelProvider extends PersonalModelProvider {
  async getCurrentContext(modelId, grant, options) {
    const snapshot = await this.getSnapshot(modelId, grant, options);
    return freezeCopy({
      modelId: snapshot.model.id,
      updatedAt: snapshot.personalModel.updatedAt,
      root: snapshot.personalModel.root,
      now: snapshot.now.items,
      identity: {
        dailyLine: snapshot.identity.dailyLine,
      },
    });
  }

  async search(modelId, query, grant, options) {
    assertSafeModelId(modelId);
    if (typeof query !== "string" || query.trim().length === 0) {
      throw new PersonalModelProviderError(
        "INVALID_SEARCH_QUERY",
        "A non-empty search query is required.",
        { status: 400 },
      );
    }

    const snapshot = await this.getSnapshot(modelId, grant, options);
    const terms = query
      .trim()
      .toLocaleLowerCase()
      .split(/\s+/u)
      .filter(Boolean);
    const results = searchableEntries(snapshot)
      .filter((entry) => {
        const haystack = `${entry.title}\n${entry.text}`.toLocaleLowerCase();
        return terms.every((term) => haystack.includes(term));
      })
      .map((entry) => ({
        modelId: snapshot.model.id,
        ...entry,
      }));

    return freezeCopy(results);
  }

  async getEvidence(modelId, reference, grant, options) {
    assertSafeModelId(modelId);
    if (
      typeof reference !== "string" ||
      !reference.startsWith(`${modelId}:`)
    ) {
      throw new PersonalModelProviderError(
        "EVIDENCE_MODEL_MISMATCH",
        "The Evidence reference does not belong to the requested model.",
        { status: 403 },
      );
    }

    const snapshot = await this.getSnapshot(modelId, grant, options);
    const content = evidenceContent(snapshot, reference);
    if (content === null) {
      throw new PersonalModelProviderError(
        "EVIDENCE_NOT_FOUND",
        "The requested Evidence was not found.",
        { status: 404 },
      );
    }

    return parsePersonalModelEvidenceResponse({
      modelId,
      reference,
      content,
    });
  }

  async correct() {
    throw new PersonalModelProviderError(
      "PROVIDER_READ_ONLY",
      "This Personal Model Provider is read-only.",
      { status: 405 },
    );
  }

  async jot() {
    throw new PersonalModelProviderError(
      "PROVIDER_READ_ONLY",
      "This Personal Model Provider is read-only.",
      { status: 405 },
    );
  }

  async connectAgent(modelId, connectorId, grant, options) {
    assertSafeModelId(modelId);
    if (typeof connectorId !== "string" || connectorId.length === 0) {
      throw new PersonalModelProviderError(
        "INVALID_CONNECTOR_ID",
        "A Connector ID is required.",
        { status: 400 },
      );
    }

    const snapshot = await this.getSnapshot(modelId, grant, options);
    const connector = snapshot.connectors.find(
      (candidate) => candidate.id === connectorId,
    );
    if (!connector) {
      throw new PersonalModelProviderError(
        "CONNECTOR_NOT_FOUND",
        "The requested Connector was not found.",
        { status: 404 },
      );
    }

    return freezeCopy({
      modelId,
      connectorId,
      status: connector.status,
    });
  }

  async listAgentReports(modelId, grant, options) {
    const snapshot = await this.getSnapshot(modelId, grant, options);
    return freezeCopy(snapshot.reports);
  }
}
