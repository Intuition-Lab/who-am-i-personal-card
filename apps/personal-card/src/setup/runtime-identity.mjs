const IDENTITY_KEYS = Object.freeze([
  "RUNTIME_REPOSITORY",
  "RUNTIME_COMMIT",
  "RUNTIME_TREE",
  "RUNTIME_PROJECT_NAME",
  "RUNTIME_PROJECT_VERSION",
]);

function parseAssignments(text) {
  const assignments = new Map();
  for (const line of String(text).split(/\r?\n/u)) {
    if (line === "" || line.startsWith("#")) continue;
    const match = /^([A-Z][A-Z0-9_]*)="([^"]*)"$/u.exec(line);
    if (!match || assignments.has(match[1])) return null;
    assignments.set(match[1], match[2]);
  }
  return assignments;
}

export function managedRuntimeIdentityMatches({
  managementLockText,
  externalReceiptText,
  internalReceiptText,
}) {
  const lock = parseAssignments(managementLockText);
  const external = parseAssignments(externalReceiptText);
  const internal = parseAssignments(internalReceiptText);
  if (!lock || !external || !internal) return false;
  if (lock.get("RUNTIME_LOCK_SCHEMA") !== "1") return false;
  if (
    external.get("RECEIPT_SCHEMA") !== "1"
    || internal.get("RECEIPT_SCHEMA") !== "1"
    || external.size !== IDENTITY_KEYS.length + 1
    || internal.size !== IDENTITY_KEYS.length + 1
  ) {
    return false;
  }
  if (
    lock.get("RUNTIME_REPOSITORY")
      !== "https://github.com/Intuition-Lab/personal-model.git"
    || !/^[0-9a-f]{40}$/u.test(lock.get("RUNTIME_COMMIT") || "")
    || !/^[0-9a-f]{40}$/u.test(lock.get("RUNTIME_TREE") || "")
  ) {
    return false;
  }
  return IDENTITY_KEYS.every((key) => (
    typeof lock.get(key) === "string"
    && external.get(key) === lock.get(key)
    && internal.get(key) === lock.get(key)
  ));
}
