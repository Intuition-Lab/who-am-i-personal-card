# Personal Model contracts

All Provider payloads cross one shared runtime boundary:

```js
import {
  parsePersonalModelCardSnapshot,
} from "./personal-model-card.mjs";

const snapshot = parsePersonalModelCardSnapshot(providerPayload);
```

The returned Snapshot is detached from the Provider payload, recursively
frozen, and safe for the active-model Store to consume. UI code must not render
an unparsed Provider response.

The shared contract module also defines these narrower boundaries:

- `projectPublicPersonalModelCardSnapshot` removes private fields instead of
  returning empty Rewind, Evidence, Connector, or Report values.
- `parsePersonalModelGrantClaims` validates decoded Grant claims. Signature,
  expiry, and expected-audience enforcement belong to the authorization layer.
- `parsePersonalModelEvidenceResponse` requires both `modelId` and a reference
  whose namespace starts with that exact model ID. Every parsed response also
  carries a typed source, original timestamp/application/title, supported
  claims with direct/indirect relationships, and an availability state. Legacy
  payloads are retained only as `derived-summary` / `unavailable`; they are
  never promoted to original records.
- `parsePersonalModelCorrectionResponse` separates an accepted-but-unverified
  write from an applied correction whose affected conclusions were verified
  after a fresh Snapshot load.

The pinned Persome `0.3.2` / `e1315d03` MCP currently returns
`{kind, applied, reason, ok}` from `correct_memory`, without a receipt or an
affected-conclusion list. `LocalPersomeProvider` keeps that response compatible:
after `ok` plus a non-empty `applied`, it reloads the Snapshot, derives removed
priority conclusions from the before/after pair, verifies they remain absent,
and emits a content-addressed `<modelId>:correction:<sha256>` product receipt.
The receipt is never emitted when the visible propagation check fails.

Evidence references are canonicalized as `<modelId>:<kind>:<reference>`. Report
`modelId` must equal the Snapshot model, its connector must exist in the same
Snapshot, and `evidenceCount` must equal the number of `evidenceRefs`.

Content-bearing Snapshot objects may include `metadata` with `provenance`
(`observed`, `inferred`, or `generated`), `sourceRefs`, `confidence`,
`timeRange`, `generatedAt`, and `method`. These fields are optional for
backward compatibility. Every `sourceRefs` entry is model-bound and is removed
from projections without `evidence:read`.
