import assert from "node:assert/strict";
import test from "node:test";

import { assertPersonalModelProvider } from "../../src/contracts/personal-model-provider.mjs";

export function defineProviderContract(providerName, createProvider) {
  test(`${providerName}: implements the complete Provider contract`, async () => {
    const provider = createProvider();
    assert.equal(assertPersonalModelProvider(provider), provider);

    const models = await provider.listModels();
    assert.deepEqual(
      models.map(({ id }) => id).sort(),
      ["cecilia", "lin-demo"],
    );
    assert.ok(Object.isFrozen(models));
  });

  test(`${providerName}: returns a fresh validated Snapshot on every read`, async () => {
    const provider = createProvider();
    const first = await provider.getSnapshot("cecilia");
    const second = await provider.getSnapshot("cecilia");

    assert.equal(first.model.id, "cecilia");
    assert.notEqual(first, second);
    assert.notEqual(first.personalModel, second.personalModel);
    assert.ok(Object.isFrozen(first));
    assert.ok(Object.isFrozen(first.reports));
    assert.ok(
      first.reports.every((report) => report.modelId === first.model.id),
    );
  });

  test(`${providerName}: concurrent Cecilia and Lin reads never share model data`, async () => {
    const provider = createProvider();
    const requests = Array.from({ length: 12 }, (_, index) =>
      provider.getSnapshot(index % 2 === 0 ? "cecilia" : "lin-demo"),
    );
    const snapshots = await Promise.all(requests);

    for (const [index, snapshot] of snapshots.entries()) {
      const expectedId = index % 2 === 0 ? "cecilia" : "lin-demo";
      const foreignId = expectedId === "cecilia" ? "lin-demo" : "cecilia";
      assert.equal(snapshot.model.id, expectedId);
      assert.ok(
        snapshot.reports.every((report) => report.modelId === expectedId),
      );
      assert.ok(
        snapshot.reports.every((report) =>
          report.evidenceRefs.every((reference) =>
            reference.startsWith(`${expectedId}:`),
          ),
        ),
      );
      assert.equal(JSON.stringify(snapshot).includes(`"${foreignId}:`), false);
    }

    assert.equal(new Set(snapshots).size, snapshots.length);
  });
}
