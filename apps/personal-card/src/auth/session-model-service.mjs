import {
  parsePersonalModelCardSnapshot,
} from "../contracts/personal-model-card.mjs";
import { assertSafeModelId } from "../contracts/personal-model-provider.mjs";
import { PersonalModelAuthorizationError } from "./errors.mjs";
import {
  OWNER_SCOPES,
  PUBLIC_SCOPES,
  normalizeScopes,
  projectSnapshotByScope,
} from "./scope-policy.mjs";

export class SessionModelService {
  constructor({
    sessionStore,
    providerRegistry,
    grantTokenService,
    audience,
    isOwner = () => false,
    isPubliclyReadable = () => false,
  }) {
    if (
      !sessionStore ||
      typeof sessionStore.getSession !== "function" ||
      typeof sessionStore.commitModelSwitch !== "function"
    ) {
      throw new TypeError("SessionModelService requires a viewer session store.");
    }
    if (
      !providerRegistry ||
      typeof providerRegistry.getSnapshot !== "function"
    ) {
      throw new TypeError("SessionModelService requires a Provider registry.");
    }
    if (
      !grantTokenService ||
      typeof grantTokenService.verify !== "function"
    ) {
      throw new TypeError("SessionModelService requires a Grant token service.");
    }
    if (typeof audience !== "string" || audience.length === 0) {
      throw new TypeError("SessionModelService audience is required.");
    }
    if (typeof isOwner !== "function") {
      throw new TypeError("SessionModelService owner resolver must be a function.");
    }
    if (typeof isPubliclyReadable !== "function") {
      throw new TypeError(
        "SessionModelService public access resolver must be a function.",
      );
    }

    this.sessionStore = sessionStore;
    this.providerRegistry = providerRegistry;
    this.grantTokenService = grantTokenService;
    this.audience = audience;
    this.isOwner = isOwner;
    this.isPubliclyReadable = isPubliclyReadable;
  }

  async accessFor(session, modelId, grantToken, requestedAccess) {
    if (requestedAccess === "public") {
      if (!(await this.isPubliclyReadable({ session, modelId }))) {
        throw new PersonalModelAuthorizationError(
          "MODEL_NOT_PUBLIC",
          "This Personal Model is not publicly readable.",
          { status: 403 },
        );
      }
      return Object.freeze({
        viewerMode: "public",
        grant: null,
        scopes: PUBLIC_SCOPES,
        expiresAt: null,
      });
    }

    if (
      requestedAccess !== "authorized"
      && await this.isOwner({ session, modelId })
    ) {
      return Object.freeze({
        viewerMode: "owner",
        grant: null,
        scopes: OWNER_SCOPES,
        expiresAt: null,
      });
    }

    if (grantToken) {
      const grant = this.grantTokenService.verify(grantToken, {
        modelId,
        audience: this.audience,
      });
      return Object.freeze({
        viewerMode: "authorized",
        grant,
        grantId: grant.grantId,
        scopes: normalizeScopes(grant.scopes),
        expiresAt: grant.expiresAt,
        audience: grant.audience,
      });
    }

    if (requestedAccess === "authorized") {
      throw new PersonalModelAuthorizationError(
        "MODEL_GRANT_REQUIRED",
        "Authorized Personal Model access requires a valid Grant.",
        { status: 403 },
      );
    }

    if (
      requestedAccess === "owner"
      || !(await this.isPubliclyReadable({ session, modelId }))
    ) {
      throw new PersonalModelAuthorizationError(
        "MODEL_GRANT_REQUIRED",
        "This Personal Model requires an owner session or a valid Grant.",
        { status: 403 },
      );
    }

    return Object.freeze({
      viewerMode: "public",
      grant: null,
      scopes: PUBLIC_SCOPES,
      expiresAt: null,
    });
  }

  async switchModel({
    sessionId,
    modelId,
    grantToken,
    access,
    signal,
  }) {
    assertSafeModelId(modelId);
    if (access && !["owner", "authorized", "public"].includes(access)) {
      throw new PersonalModelAuthorizationError(
        "VIEWER_MODE_INVALID",
        "The requested Personal Model access mode is invalid.",
        { status: 403 },
      );
    }
    const current = this.sessionStore.getSession(sessionId);
    const expectedRevision = current.revision;
    const accessContext = await this.accessFor(
      current,
      modelId,
      grantToken,
      access,
    );

    const providerSnapshot = await this.providerRegistry.getSnapshot(
      modelId,
      accessContext.grant,
      { signal },
    );
    const snapshot = parsePersonalModelCardSnapshot(providerSnapshot);
    if (snapshot.model.id !== modelId) {
      throw new PersonalModelAuthorizationError(
        "MODEL_RESPONSE_MISMATCH",
        "The Provider returned a different Personal Model.",
        { status: 502 },
      );
    }

    const projectedSnapshot = projectSnapshotByScope(snapshot, accessContext);
    // No session state is mutated until every read, validation, and projection
    // step above has completed successfully.
    return this.sessionStore.commitModelSwitch(sessionId, {
      expectedRevision,
      activeModelId: modelId,
      grant: accessContext.grant,
      authorization: projectedSnapshot.authorization,
      snapshot: projectedSnapshot,
    });
  }
}
