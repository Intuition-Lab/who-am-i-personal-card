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
  whose namespace starts with that exact model ID.

Evidence references are canonicalized as `<modelId>:<kind>:<reference>`. Report
`modelId` must equal the Snapshot model, its connector must exist in the same
Snapshot, and `evidenceCount` must equal the number of `evidenceRefs`.
