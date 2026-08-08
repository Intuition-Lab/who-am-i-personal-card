import assert from "node:assert/strict";
import test from "node:test";

import { managedRuntimeIdentityMatches } from "../../src/setup/runtime-identity.mjs";

const identity = Object.freeze({
  repository: "https://github.com/Intuition-Lab/personal-model.git",
  commit: "e1315d03cafb62418503e6d92b9e73400720fcd4",
  tree: "1835049eb58d6aa7006562b2cbe6ad56c6242721",
  project: "persome-core",
  version: "0.3.2",
});

const managementLockText = [
  'RUNTIME_LOCK_SCHEMA="1"',
  `RUNTIME_REPOSITORY="${identity.repository}"`,
  `RUNTIME_COMMIT="${identity.commit}"`,
  `RUNTIME_TREE="${identity.tree}"`,
  `RUNTIME_PROJECT_NAME="${identity.project}"`,
  `RUNTIME_PROJECT_VERSION="${identity.version}"`,
  'RUNTIME_CLI="persome"',
  'RUNTIME_UV_VERSION="0.10.9"',
  "",
].join("\n");

const receiptText = [
  'RECEIPT_SCHEMA="1"',
  `RUNTIME_REPOSITORY="${identity.repository}"`,
  `RUNTIME_COMMIT="${identity.commit}"`,
  `RUNTIME_TREE="${identity.tree}"`,
  `RUNTIME_PROJECT_NAME="${identity.project}"`,
  `RUNTIME_PROJECT_VERSION="${identity.version}"`,
  "",
].join("\n");

test("managed Runtime receipts match the complete product lock identity", () => {
  assert.equal(managedRuntimeIdentityMatches({
    managementLockText,
    externalReceiptText: receiptText,
    internalReceiptText: receiptText,
  }), true);
});

test("managed Runtime identity rejects tampering and extra receipt fields", () => {
  assert.equal(managedRuntimeIdentityMatches({
    managementLockText,
    externalReceiptText: receiptText.replace(identity.commit, "0".repeat(40)),
    internalReceiptText: receiptText,
  }), false);
  assert.equal(managedRuntimeIdentityMatches({
    managementLockText,
    externalReceiptText: `${receiptText}EXTRA="unsafe"\n`,
    internalReceiptText: receiptText,
  }), false);
});
