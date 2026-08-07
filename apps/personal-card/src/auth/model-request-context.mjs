import { PersonalModelAuthorizationError } from "./errors.mjs";
import { requireScope } from "./scope-policy.mjs";

const MODEL_OVERRIDE_KEYS = new Set(["modelId", "model_id"]);

function bodyContainsModelOverride(value, depth = 0, seen = new Set()) {
  if (
    value === null ||
    typeof value !== "object" ||
    depth > 12 ||
    seen.has(value)
  ) {
    return false;
  }
  seen.add(value);

  for (const [key, child] of Object.entries(value)) {
    if (MODEL_OVERRIDE_KEYS.has(key)) return true;
    if (bodyContainsModelOverride(child, depth + 1, seen)) return true;
  }
  return false;
}

function queryContainsModelOverride(query) {
  if (!query) return false;
  if (query instanceof URLSearchParams) {
    return [...MODEL_OVERRIDE_KEYS].some((key) => query.has(key));
  }
  if (typeof query !== "object") return false;
  return [...MODEL_OVERRIDE_KEYS].some((key) =>
    Object.prototype.hasOwnProperty.call(query, key),
  );
}

export function assertNoModelOverride({ body, query } = {}) {
  if (
    bodyContainsModelOverride(body) ||
    queryContainsModelOverride(query)
  ) {
    throw new PersonalModelAuthorizationError(
      "MODEL_OVERRIDE_FORBIDDEN",
      "The active Personal Model is selected by the viewer session.",
      { status: 403 },
    );
  }
}

export function createModelRequestContext({
  sessionStore,
  sessionId,
  body,
  query,
  requiredScope,
}) {
  if (!sessionStore || typeof sessionStore.getSession !== "function") {
    throw new TypeError("A viewer session store is required.");
  }
  assertNoModelOverride({ body, query });

  const session = sessionStore.getSession(sessionId);
  if (!session.activeModelId || !session.snapshot || !session.authorization) {
    throw new PersonalModelAuthorizationError(
      "ACTIVE_MODEL_REQUIRED",
      "The viewer session does not have an active Personal Model.",
      { status: 409 },
    );
  }
  if (requiredScope) requireScope(session.authorization, requiredScope);

  return Object.freeze({
    sessionId: session.id,
    viewerUserId: session.viewerUserId,
    modelId: session.activeModelId,
    grant: session.grant,
    authorization: session.authorization,
    scopes: session.scopes,
    revision: session.revision,
    snapshot: session.snapshot,
  });
}
