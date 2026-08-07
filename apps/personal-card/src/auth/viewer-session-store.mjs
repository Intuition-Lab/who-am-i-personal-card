import { randomBytes } from "node:crypto";

import { assertSafeModelId } from "../contracts/personal-model-provider.mjs";
import { PersonalModelAuthorizationError } from "./errors.mjs";
import { normalizeScopes } from "./scope-policy.mjs";

const SESSION_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

function fail(code, message, status) {
  throw new PersonalModelAuthorizationError(code, message, { status });
}

function immutableSession(value) {
  return Object.freeze({
    ...value,
    scopes: Object.freeze([...(value.scopes ?? [])]),
  });
}

function sessionIdFromCookie(cookieHeader, cookieName) {
  const matches = String(cookieHeader || "")
    .split(/;\s*/)
    .map((entry) => entry.split("=", 2))
    .filter(([name]) => name === cookieName)
    .map(([, value]) => value)
    .filter((value) => SESSION_ID_PATTERN.test(value || ""));

  return matches.length === 1 ? matches[0] : null;
}

export class ViewerSessionStore {
  constructor({
    cookieName = "whoami_viewer_session",
    clock = () => Date.now(),
    randomBytesFn = randomBytes,
  } = {}) {
    if (!/^[A-Za-z0-9_-]+$/.test(cookieName)) {
      throw new TypeError("Viewer session cookie name is invalid.");
    }
    if (typeof clock !== "function" || typeof randomBytesFn !== "function") {
      throw new TypeError("Viewer session dependencies are invalid.");
    }

    this.cookieName = cookieName;
    this.clock = clock;
    this.randomBytesFn = randomBytesFn;
    this.sessions = new Map();
  }

  createSession({ viewerUserId = null } = {}) {
    let id;
    do {
      id = Buffer.from(this.randomBytesFn(32)).toString("base64url");
    } while (this.sessions.has(id));

    const now = new Date(Number(this.clock())).toISOString();
    const session = immutableSession({
      id,
      viewerUserId,
      activeModelId: null,
      grant: null,
      authorization: null,
      scopes: [],
      revision: 0,
      snapshot: null,
      createdAt: now,
      updatedAt: now,
    });
    this.sessions.set(id, session);
    return session;
  }

  getSession(sessionId) {
    if (
      typeof sessionId !== "string" ||
      !SESSION_ID_PATTERN.test(sessionId) ||
      !this.sessions.has(sessionId)
    ) {
      fail("SESSION_NOT_FOUND", "The viewer session is not available.", 401);
    }
    return this.sessions.get(sessionId);
  }

  getOrCreateFromCookie(cookieHeader, options = {}) {
    const sessionId = sessionIdFromCookie(cookieHeader, this.cookieName);
    if (sessionId && this.sessions.has(sessionId)) {
      return Object.freeze({
        session: this.sessions.get(sessionId),
        setCookie: null,
      });
    }

    const session = this.createSession(options);
    return Object.freeze({
      session,
      setCookie:
        `${this.cookieName}=${session.id}; Path=/; HttpOnly; SameSite=Strict`,
    });
  }

  commitModelSwitch(sessionId, {
    expectedRevision,
    activeModelId,
    grant,
    authorization,
    snapshot,
  }) {
    const current = this.getSession(sessionId);
    if (
      !Number.isSafeInteger(expectedRevision) ||
      current.revision !== expectedRevision
    ) {
      fail(
        "SESSION_REVISION_CONFLICT",
        "The viewer session changed during the model switch.",
        409,
      );
    }
    assertSafeModelId(activeModelId);
    if (!snapshot || typeof snapshot !== "object" || Object.isFrozen(snapshot) === false) {
      throw new TypeError("Committed Snapshot must be an immutable object.");
    }
    if (!authorization || typeof authorization !== "object") {
      throw new TypeError("Committed authorization context is required.");
    }

    const scopes = normalizeScopes(authorization.scopes);
    const updated = immutableSession({
      ...current,
      activeModelId,
      grant,
      authorization: Object.freeze({
        ...authorization,
        scopes,
      }),
      scopes,
      revision: current.revision + 1,
      snapshot,
      updatedAt: new Date(Number(this.clock())).toISOString(),
    });
    this.sessions.set(sessionId, updated);
    return updated;
  }
}
