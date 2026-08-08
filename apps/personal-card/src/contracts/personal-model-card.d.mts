export type PersonalModelViewerMode = "owner" | "authorized" | "public";
export type PersonalModelStatus = "online" | "offline" | "snapshot";
export type PersonalModelNowKind = "past" | "present" | "future";
export type ConnectorStatus =
  | "connected"
  | "available"
  | "missing"
  | "connecting";
export type ReportSectionKind =
  | "lead"
  | "understanding"
  | "evidence"
  | "note";
export type PersonalModelContentProvenance =
  | "observed"
  | "inferred"
  | "generated";

export interface PersonalModelContentMetadata {
  readonly provenance?: PersonalModelContentProvenance;
  readonly sourceRefs?: readonly string[];
  readonly confidence?: number;
  readonly timeRange?: {
    readonly start: string;
    readonly end: string;
  };
  readonly generatedAt?: string;
  readonly method?: string;
}

export interface PersonalModelDescriptor {
  readonly id: string;
  readonly displayName: string;
  readonly handle: string;
  readonly memberNumber: string;
  readonly sinceYear: number;
  readonly status: PersonalModelStatus;
  readonly avatarUrl?: string;
}

export interface PersonalModelAuthorization {
  readonly viewerMode: PersonalModelViewerMode;
  readonly grantId?: string;
  readonly scopes: readonly string[];
  readonly expiresAt?: string | null;
  readonly audience?: string;
}

export interface PersonalModelCard {
  readonly monthYear: string;
  readonly tagline: string;
  readonly publicUrl: string;
  readonly material?: string;
  readonly metadata?: PersonalModelContentMetadata;
  readonly glyph: readonly boolean[];
}

export interface PersonalModelFace {
  readonly id: string;
  readonly text: string;
  readonly observations: number;
  readonly confidence: number;
  readonly evidenceRefs?: readonly string[];
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelSummary {
  readonly memoryCount: number;
  readonly root: string;
  readonly faces: readonly PersonalModelFace[];
  readonly updatedAt: string;
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelNowItem {
  readonly id: string;
  readonly kind: PersonalModelNowKind;
  readonly title: string;
  readonly why: string;
  readonly when: string;
  readonly dayId?: string;
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelNow {
  readonly items: readonly PersonalModelNowItem[];
}

export interface PersonalModelTimeEvent {
  readonly id: string;
  readonly time: string;
  readonly title: string;
  readonly detail: string;
  readonly app?: string;
  readonly evidenceRef?: string;
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelDay {
  readonly id: string;
  readonly title: string;
  readonly portrait: string;
  readonly letter?: string;
  readonly events: readonly PersonalModelTimeEvent[];
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelTime {
  readonly days: readonly PersonalModelDay[];
}

export interface PersonalModelIdentity {
  readonly description: string;
  readonly dailyLine: string;
  readonly weeklyLetter: readonly string[];
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelConnector {
  readonly id: string;
  readonly name: string;
  readonly product: string;
  readonly status: ConnectorStatus;
  readonly iconUrl?: string;
  readonly sessionId?: string;
}

export interface PersonalModelReportSection {
  readonly kind: ReportSectionKind;
  readonly title: string;
  readonly body: string;
  readonly metadata?: PersonalModelContentMetadata;
}

export interface PersonalModelReport {
  readonly id: string;
  readonly modelId: string;
  readonly connectorId: string;
  readonly title: string;
  readonly summary: string;
  readonly updatedAt: string;
  readonly readCount: number;
  readonly evidenceCount: number;
  readonly sections: readonly PersonalModelReportSection[];
  readonly evidenceRefs: readonly string[];
  readonly metadata?: PersonalModelContentMetadata;
}

/**
 * The only user-facing data shape the UI may consume.
 *
 * Instances are produced by `parsePersonalModelCardSnapshot`, are detached from
 * the Provider response, and are recursively frozen.
 */
export interface PersonalModelCardSnapshot {
  readonly schemaVersion: "1.0.0";
  readonly model: PersonalModelDescriptor;
  readonly authorization: PersonalModelAuthorization;
  readonly card: PersonalModelCard;
  readonly personalModel: PersonalModelSummary;
  readonly now: PersonalModelNow;
  readonly time: PersonalModelTime;
  readonly identity: PersonalModelIdentity;
  readonly connectors: readonly PersonalModelConnector[];
  readonly reports: readonly PersonalModelReport[];
}

/**
 * A public, server-projected response. Private fields are absent from the
 * object rather than replaced by empty values.
 */
export interface PublicPersonalModelCardSnapshot {
  readonly schemaVersion: "1.0.0";
  readonly projection: "public";
  readonly model: PersonalModelDescriptor;
  readonly authorization: {
    readonly viewerMode: "public";
    readonly scopes: readonly ["card:read", "identity:read"];
    readonly expiresAt: null;
  };
  readonly card: PersonalModelCard;
  readonly identity: PersonalModelIdentity;
}

/**
 * Claims decoded from a Grant token. Signature, audience match, and expiry are
 * enforced by the authorization layer; this type defines the payload contract.
 */
export interface PersonalModelGrantClaims {
  readonly grantId: string;
  readonly modelId: string;
  readonly subject?: string;
  readonly scopes: readonly string[];
  readonly expiresAt: string;
  readonly audience: string;
  readonly issuedAt?: string;
}

/**
 * Evidence never travels without the model partition key used to resolve it.
 */
export interface PersonalModelEvidenceResponse {
  readonly modelId: string;
  readonly reference: string;
  readonly source: {
    readonly type:
      | "persome-memory"
      | "persome-activity"
      | "derived-summary"
      | "agent-connector-receipt"
      | "coast-frame";
    readonly originalTime: string | null;
    readonly application: string | null;
    readonly title: string | null;
    readonly recordId?: string;
  };
  readonly supports: readonly {
    readonly claim: string;
    readonly relationship: "direct" | "indirect";
  }[];
  readonly availability: {
    readonly status: "available" | "unavailable";
    readonly reason?: string;
  };
  readonly content: unknown;
  readonly receipt?: string;
  readonly capturedAt?: string;
}

export interface PersonalModelCorrectionResponse {
  readonly modelId: string;
  readonly status: "accepted" | "applied";
  readonly receipt: string | null;
  readonly receiptSource?: "runtime" | "product" | "remote";
  readonly affected: readonly {
    readonly reference?: string;
    readonly previousConclusion: string;
    readonly replacement?: string;
    readonly state: "deprioritized" | "pending";
  }[];
  readonly verification: {
    readonly status: "unverified" | "verified";
    readonly refreshed: boolean;
    readonly oldConclusionDeprioritized: boolean;
    readonly previousUpdatedAt?: string | null;
    readonly updatedAt?: string | null;
  };
}

export interface PersonalModelCardValidationIssue {
  readonly path: string;
  readonly keyword: string;
  readonly message: string;
}

export class PersonalModelCardValidationError extends TypeError {
  readonly issues: readonly PersonalModelCardValidationIssue[];
}

/**
 * Clone, validate, verify model ownership, and recursively freeze an unknown
 * Provider payload. This is the single ingress into UI-safe Snapshot data.
 *
 * @throws {PersonalModelCardValidationError}
 */
export function parsePersonalModelCardSnapshot(
  input: unknown,
): PersonalModelCardSnapshot;

/**
 * Parse an already-scoped public response. Private Snapshot fields are
 * rejected as additional properties.
 */
export function parsePublicPersonalModelCardSnapshot(
  input: unknown,
): PublicPersonalModelCardSnapshot;

/**
 * Produce a public response only from a value returned by the full parser.
 */
export function projectPublicPersonalModelCardSnapshot(
  snapshot: PersonalModelCardSnapshot,
): PublicPersonalModelCardSnapshot;

export function parsePersonalModelGrantClaims(
  input: unknown,
): PersonalModelGrantClaims;

export function parsePersonalModelEvidenceResponse(
  input: unknown,
): PersonalModelEvidenceResponse;

export function parsePersonalModelCorrectionResponse(
  input: unknown,
): PersonalModelCorrectionResponse;

export const PERSONAL_MODEL_CARD_SCHEMA_ID: string;
export const PERSONAL_MODEL_GRANT_SCHEMA_ID: string;
export const PERSONAL_MODEL_EVIDENCE_SCHEMA_ID: string;
export const PERSONAL_MODEL_CORRECTION_SCHEMA_ID: string;
