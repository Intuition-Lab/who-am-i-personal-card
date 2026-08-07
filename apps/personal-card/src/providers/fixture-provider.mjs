import { readFile } from "node:fs/promises";

import {
  PersonalModelProviderError,
  assertSafeModelId,
} from "../contracts/personal-model-provider.mjs";
import {
  SnapshotBackedPersonalModelProvider,
  freezeCopy,
  validateSnapshotForModel,
} from "./snapshot-backed-provider.mjs";

const DEFAULT_FIXTURES = Object.freeze({
  cecilia: new URL("../../fixtures/models/cecilia.json", import.meta.url),
  "lin-demo": new URL("../../fixtures/models/lin.json", import.meta.url),
});

export class FixtureProvider extends SnapshotBackedPersonalModelProvider {
  constructor({ fixtures = DEFAULT_FIXTURES } = {}) {
    super();
    this.fixtures = new Map();

    for (const [modelId, fixtureLocation] of Object.entries(fixtures)) {
      this.fixtures.set(assertSafeModelId(modelId), fixtureLocation);
    }
  }

  async listModels() {
    const snapshots = await Promise.all(
      [...this.fixtures.keys()].map((modelId) => this.getSnapshot(modelId)),
    );
    return freezeCopy(snapshots.map(({ model }) => model));
  }

  async getSnapshot(modelId) {
    assertSafeModelId(modelId);
    const fixtureLocation = this.fixtures.get(modelId);
    if (!fixtureLocation) {
      throw new PersonalModelProviderError(
        "MODEL_NOT_FOUND",
        "The requested Personal Model is not available.",
        { status: 404 },
      );
    }

    let rawSnapshot;
    try {
      rawSnapshot = JSON.parse(await readFile(fixtureLocation, "utf8"));
    } catch {
      throw new PersonalModelProviderError(
        "FIXTURE_UNAVAILABLE",
        "The fixture Personal Model is unavailable.",
        { status: 503 },
      );
    }

    return validateSnapshotForModel(rawSnapshot, modelId);
  }
}

export const FIXTURE_MODEL_IDS = Object.freeze(Object.keys(DEFAULT_FIXTURES));
