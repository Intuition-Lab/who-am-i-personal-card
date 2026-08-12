import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));

test("release asset construction is blocked by the complete beta gate", async () => {
  const [gate, builder, packageBuilder] = await Promise.all([
    readFile(path.join(productRoot, "scripts/beta-release-gate.sh"), "utf8"),
    readFile(path.join(productRoot, "scripts/build-release-assets.sh"), "utf8"),
    readFile(
      path.join(productRoot, "scripts/build-self-contained-package.sh"),
      "utf8",
    ),
  ]);

  for (const requiredGate of [
    "JavaScript syntax",
    "Python syntax",
    "28 content evals and Connector isolation",
    "browser and production no-demo flows",
    "Swift typecheck",
    "universal native launcher",
    "website typecheck, build, rendered HTML, and lint",
    "package source, foundation, and Runtime lock",
  ]) {
    assert.match(gate, new RegExp(requiredGate));
  }
  assert.match(gate, /\[beta gate\] FAIL:/);
  assert.match(gate, /NativeLifecycle\.swift/);
  assert.match(builder, /bash scripts\/beta-release-gate\.sh/);
  assert.ok(
    builder.indexOf("bash scripts/beta-release-gate.sh") <
      builder.indexOf("bash scripts/build-self-contained-package.sh"),
    "The beta gate must run before package construction.",
  );
  assert.match(
    packageBuilder,
    /rev-list --objects "\$\{RUNTIME_COMMIT\}\^\{tree\}"/,
  );
  assert.match(packageBuilder, /pack-objects --stdout/);
  assert.doesNotMatch(packageBuilder, /runtime_parents|pack-objects --stdout --revs/);
});
