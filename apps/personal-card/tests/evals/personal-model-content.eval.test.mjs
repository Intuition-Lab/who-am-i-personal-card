import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { DeterministicPersonalModelFixture } from "./deterministic-personal-model-fixture.mjs";

const fixture = JSON.parse(await readFile(
  new URL("../fixtures/evals/personal-model-content.json", import.meta.url),
  "utf8",
));

const EXPECTED_CATEGORIES = Object.freeze({
  complete_search: 5,
  paraphrase: 5,
  unsupported_refusal: 4,
  evidence_alignment: 4,
  correct_updates: 3,
  rewind_grounding: 3,
  cross_model_isolation: 4,
});

function textOf(value) {
  return JSON.stringify(value);
}

function assertFragments(value, expected = [], forbidden = []) {
  const text = textOf(value);
  for (const fragment of expected) assert.ok(
    text.includes(fragment),
    `Expected ${JSON.stringify(fragment)} in ${text}`,
  );
  for (const fragment of forbidden) assert.equal(
    text.includes(fragment),
    false,
    `Forbidden ${JSON.stringify(fragment)} leaked into ${text}`,
  );
}

test("content eval fixture contains 28 synthetic scenarios across every beta quality category", () => {
  assert.equal(fixture.schemaVersion, 1);
  assert.equal(fixture.scenarios.length, 28);
  assert.equal(new Set(fixture.scenarios.map(({ id }) => id)).size, 28);
  const counts = Object.fromEntries(Object.keys(EXPECTED_CATEGORIES).map(
    (category) => [
      category,
      fixture.scenarios.filter((scenario) => scenario.category === category)
        .length,
    ],
  ));
  assert.deepEqual(counts, EXPECTED_CATEGORIES);
  assert.doesNotMatch(textOf(fixture), /@cecilia|lin-demo|\/Users\//);
});

for (const scenario of fixture.scenarios) {
  test(`content eval ${scenario.id}: ${scenario.category}`, () => {
    const model = new DeterministicPersonalModelFixture(fixture.models);
    let result;
    if (scenario.operation === "search") {
      result = model.search(scenario.modelId, scenario.query);
      assert.deepEqual(
        result.map(({ id }) => id),
        scenario.expectedMemoryIds ?? result.map(({ id }) => id),
      );
    } else if (scenario.operation === "ask") {
      result = model.ask(scenario.modelId, scenario.query);
      if (scenario.expectRefusal !== undefined) {
        assert.equal(result.refused, scenario.expectRefusal);
      }
      if (scenario.expectedEvidenceRefs) {
        assert.deepEqual(result.evidenceRefs, scenario.expectedEvidenceRefs);
      }
      for (const reference of result.evidenceRefs) {
        const evidence = model.evidence(scenario.modelId, reference);
        assert.equal(evidence.reference, reference);
        assertFragments(result.answer, [evidence.content.text]);
      }
    } else if (scenario.operation === "evidence") {
      if (scenario.expectErrorCode) {
        assert.throws(
          () => model.evidence(scenario.modelId, scenario.reference),
          (error) => error.code === scenario.expectErrorCode,
        );
        return;
      }
      result = model.evidence(scenario.modelId, scenario.reference);
    } else if (scenario.operation === "correct") {
      const before = model.search(scenario.modelId, scenario.queryAfter);
      const corrected = model.correct(
        scenario.modelId,
        scenario.memoryId,
        scenario.replacementText,
      );
      result = model.search(scenario.modelId, scenario.queryAfter);
      assert.equal(corrected.revision, 2);
      assert.notDeepEqual(result, before);
    } else if (scenario.operation === "rewind") {
      result = model.rewind(scenario.modelId, scenario.from, scenario.to);
      assert.deepEqual(
        result.map(({ id }) => id),
        scenario.expectedEventIds,
      );
    } else {
      assert.fail(`Unknown eval operation: ${scenario.operation}`);
    }

    assertFragments(
      result,
      scenario.expectedTextFragments,
      scenario.forbiddenFragments,
    );
  });
}
