import {
  createHmac,
  timingSafeEqual,
} from "node:crypto";

import {
  parsePersonalModelGrantClaims,
} from "../contracts/personal-model-card.mjs";
import { assertSafeModelId } from "../contracts/personal-model-provider.mjs";
import { PersonalModelAuthorizationError } from "./errors.mjs";
import { normalizeScopes } from "./scope-policy.mjs";

const TOKEN_HEADER = Object.freeze({
  alg: "HS256",
  typ: "PM-GRANT",
  v: 1,
});
const TOKEN_PATTERN = /^[A-Za-z0-9_-]+$/;
const DEFAULT_MAX_TOKEN_BYTES = 16 * 1024;

function fail(code, message) {
  throw new PersonalModelAuthorizationError(code, message, { status: 403 });
}

function secretBytes(secret) {
  const bytes =
    typeof secret === "string"
      ? Buffer.from(secret, "utf8")
      : Buffer.isBuffer(secret) || secret instanceof Uint8Array
        ? Buffer.from(secret)
        : null;

  if (!bytes || bytes.length < 32) {
    throw new TypeError("Grant signing secret must contain at least 32 bytes.");
  }
  return bytes;
}

function encodeJson(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function decodeSegment(segment, label) {
  if (
    typeof segment !== "string" ||
    segment.length === 0 ||
    !TOKEN_PATTERN.test(segment)
  ) {
    fail("GRANT_MALFORMED", `The Grant ${label} is malformed.`);
  }

  let bytes;
  try {
    bytes = Buffer.from(segment, "base64url");
  } catch {
    fail("GRANT_MALFORMED", `The Grant ${label} is malformed.`);
  }
  if (bytes.toString("base64url") !== segment) {
    fail("GRANT_MALFORMED", `The Grant ${label} is malformed.`);
  }
  return bytes;
}

function decodeJson(segment, label) {
  const bytes = decodeSegment(segment, label);
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch {
    fail("GRANT_MALFORMED", `The Grant ${label} is not valid JSON.`);
  }
}

function assertHeader(header) {
  const keys =
    header !== null && typeof header === "object" && !Array.isArray(header)
      ? Object.keys(header).sort()
      : [];
  if (
    keys.join(",") !== "alg,typ,v" ||
    header.alg !== TOKEN_HEADER.alg ||
    header.typ !== TOKEN_HEADER.typ ||
    header.v !== TOKEN_HEADER.v
  ) {
    fail("GRANT_ALGORITHM_REJECTED", "The Grant signing algorithm is not allowed.");
  }
}

export class GrantTokenService {
  constructor({
    secret,
    audience,
    clock = () => Date.now(),
    maxTokenBytes = DEFAULT_MAX_TOKEN_BYTES,
  }) {
    if (typeof audience !== "string" || audience.length === 0) {
      throw new TypeError("Grant audience is required.");
    }
    if (typeof clock !== "function") {
      throw new TypeError("Grant clock must be a function.");
    }
    if (!Number.isSafeInteger(maxTokenBytes) || maxTokenBytes < 256) {
      throw new TypeError("Grant token size limit is invalid.");
    }

    this.secret = secretBytes(secret);
    this.audience = audience;
    this.clock = clock;
    this.maxTokenBytes = maxTokenBytes;
  }

  signature(value) {
    return createHmac("sha256", this.secret).update(value).digest();
  }

  sign(inputClaims) {
    const claims = parsePersonalModelGrantClaims(inputClaims);
    assertSafeModelId(claims.modelId);
    normalizeScopes(claims.scopes);

    const encodedHeader = encodeJson(TOKEN_HEADER);
    const encodedClaims = encodeJson(claims);
    const signingInput = `${encodedHeader}.${encodedClaims}`;
    const signature = this.signature(signingInput).toString("base64url");
    return `${signingInput}.${signature}`;
  }

  verify(token, {
    modelId,
    audience = this.audience,
  } = {}) {
    if (
      typeof token !== "string" ||
      token.length === 0 ||
      Buffer.byteLength(token, "utf8") > this.maxTokenBytes
    ) {
      fail("GRANT_MALFORMED", "The Grant token is malformed.");
    }

    const segments = token.split(".");
    if (segments.length !== 3) {
      fail("GRANT_MALFORMED", "The Grant token is malformed.");
    }
    const [encodedHeader, encodedClaims, encodedSignature] = segments;
    assertHeader(decodeJson(encodedHeader, "header"));

    const suppliedSignature = decodeSegment(encodedSignature, "signature");
    const expectedSignature = this.signature(
      `${encodedHeader}.${encodedClaims}`,
    );
    if (
      suppliedSignature.length !== expectedSignature.length ||
      !timingSafeEqual(suppliedSignature, expectedSignature)
    ) {
      fail("GRANT_SIGNATURE_INVALID", "The Grant signature is invalid.");
    }

    let claims;
    try {
      claims = parsePersonalModelGrantClaims(
        decodeJson(encodedClaims, "claims"),
      );
      assertSafeModelId(claims.modelId);
      normalizeScopes(claims.scopes);
    } catch (error) {
      if (error instanceof PersonalModelAuthorizationError) {
        throw error;
      }
      fail("GRANT_CLAIMS_INVALID", "The Grant claims are invalid.");
    }

    const expiresAt = Date.parse(claims.expiresAt);
    if (!Number.isFinite(expiresAt) || expiresAt <= Number(this.clock())) {
      fail("GRANT_EXPIRED", "The Grant has expired.");
    }
    if (claims.audience !== audience) {
      fail(
        "GRANT_AUDIENCE_MISMATCH",
        "The Grant is not valid for this application.",
      );
    }
    if (modelId !== undefined && claims.modelId !== modelId) {
      fail(
        "GRANT_MODEL_MISMATCH",
        "The Grant does not authorize the requested Personal Model.",
      );
    }

    return claims;
  }
}
