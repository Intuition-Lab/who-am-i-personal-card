# Product intake

<!-- product-intake-schema:1 -->

Use this document when the product design and existing-library inventory are
provided. It is deliberately a fillable decision record: unanswered items are
not permission to invent a feature.

## 1. Product definition

| Required input | Answer | Evidence / link | Owner |
| --- | --- | --- | --- |
| Product name and one-sentence promise | Who Am I · Personal Card — install a local Card backed by the Personal Model owned by this macOS account | V5 handoff and repository README | Product owner |
| Primary beta user | invited macOS user who wants an owner-local Personal Model and Card | 100-user beta request | Product owner |
| Problem being solved | make local memory/model state visible and reusable without mixing identities | Card/Provider contract | Product owner |
| Single golden path: trigger → steps → visible result | verified release → open `Who Am I.app` → first-run install → create local name/handle → finish Persome onboarding → Card opens on this user's model | browser, native launcher and server acceptance tests | Product owner |
| Entry surface: menu bar, desktop app, web UI, CLI, agent client, or other | `~/Applications/Who Am I.app` opens a loopback Personal Card; optional Codex plugin | installer and app launcher | Product engineering |
| Definition of a successful first session | stable `local-*` model ID, own handle visible, production has no Cecilia/Lin, Runtime MCP answers; sparse/forming state is truthful | production-owner and two-owner tests | Product owner |
| Explicit beta exclusions | cloud accounts/sync, silent macOS permission approval, multiple people in one macOS account, signed/notarized package, automated product-app uninstall | known issues | Release owner |
| Product source repository name and GitHub organization | `Intuition-Lab/who-am-i-personal-card` | public repository decision | Product owner |
| Product source license and redistribution policy | Apache License 2.0; generated Personal Model data remains the user's data | `LICENSE` and upstream-aligned policy | Product owner |
| Beta owner and release approver | TBD | names/contact route | TBD |
| Support and feedback route | public repository Issues, without Personal Model content | `SECURITY.md`, `SUPPORT.md`, issue template | Product owner |

Attach the product artifact in a reviewable form: design link or exported
screens, complete flow description, copy, and empty/loading/error/permission
states. A collection of hero screens is not enough to implement or test the
golden path.

## 2. Workflow inventory

Create one row for every user-visible workflow. Use stable IDs (`WF-001`,
`WF-002`, …) so requirements, code, tests and release notes can refer to the
same item.

| ID | User trigger | Required inputs | Visible result | Persome capability | External side effect | Failure/degraded state | Beta priority |
| --- | --- | --- | --- | --- | --- | --- | --- |
| WF-001 | Start/resume a Codex task or submit a prompt | installed and onboarded product-managed Runtime; enabled and trusted plugin | Codex receives bounded behavior/recent/relevant durable context for its answer | stdio MCP: `behavior_patterns`, `recent_activity`, `search` | recalled context enters the active Codex conversation; no memory write | fail open with no injected context; conversation continues | must |
| WF-002 | Open Who Am I after install | verified product-managed Runtime; local owner Profile | Card/Rewind/Identity from the current owner Snapshot | stdio MCP: `get_model_snapshot`, `list_memories`, `behavior_patterns`, `recent_activity`, `current_context` | owner profile is stored locally; no remote side effect | first-run overlay for missing Profile/Runtime; forming state for sparse model; no fixture fallback | must |
| WF-003 | Switch Personal Model in explicit development/authorized context | registered Provider and valid owner/Grant access | one atomic UI Snapshot across Card, Rewind, Identity, Connector, Report and Evidence | Provider contract | connector actions only after explicit user action | failed switch keeps previous complete Snapshot | must |

For each `must` row, also supply:

- acceptance scenario with observable start and end conditions;
- all permissions and accounts needed;
- whether the operation reads personal context or performs a write/action;
- what happens when Persome is absent, not onboarded, unhealthy or offline;
- what the user can retry, cancel, undo or delete;
- an owner who can accept the implementation.

## 3. Existing-library inventory

Provide every candidate library, not only the ones believed to be finished.
Pin each candidate to a tag or full commit so its status can be reproduced.

| ID | Repository | Full commit/tag | Claimed capability | Runtime/platform | Public API or contract | Tests/CI | License/notice | Maintainer |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LIB-001 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

For private repositories, provide read access to the implementation team and
its dependency source. Also identify:

- setup and build command;
- secret, account, service and environment requirements;
- network destinations and transmitted data;
- output artifact or callable interface;
- known defects and unsupported conditions;
- whether it has been installed on a clean supported Mac;
- whether Apple Silicon and Intel are both supported;
- redistribution constraints and required notices.

## 4. Classification decision

Classify a library per workflow, not once globally. The same library can be
ready for one use and missing critical behavior for another.

| Class | Required evidence | Resulting work |
| --- | --- | --- |
| **Existing / integrate** | pinned source; compatible license; documented callable contract; supported macOS and architectures; repeatable build; passing relevant tests; behavior satisfies the workflow acceptance scenario; data boundary reviewed | write a thin adapter and contract tests |
| **Adapt** | usable implementation exists, but one or more interface, packaging, UX state, privacy, reliability or platform gaps are explicit and bounded | record each gap, add adapter/change, test the gap |
| **Build** | no usable implementation, critical behavior is absent, source cannot be redistributed, or evidence is insufficient to rely on it | define a new product-owned component and acceptance test |
| **Defer** | not required for the beta golden path, unacceptable risk, or cannot meet the release window | remove from beta promise and publish as an exclusion if users may expect it |

Do not use “finished” as a class. A claim becomes **Existing / integrate** only
when the evidence above is attached.

Record the classification:

| Workflow | Candidate library | Class | Evidence | Gaps / work item | Decision owner |
| --- | --- | --- | --- | --- | --- |
| WF-001 | LIB-001 / none | existing / adapt / build / defer | TBD | TBD | TBD |

## 5. Data, permissions and external systems

| Data or action | Source | Destination | Purpose | Stored where / retention | User consent | Delete/revoke path | Secret/auth method |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Bounded behavior model, recent durable entries and prompt-relevant durable memory | Persome public MCP | active Codex conversation and its configured model processor | cross-session continuity and contextual answers | Persome source remains local; conversation processing/retention follows the user's Codex data controls and still needs release-owner review | explicit plugin install plus exact hook trust | disable/remove plugin; conversation deletion follows Codex controls | existing Codex session; no Persome secret is exported |
| TBD | Persome / user / product / external service | local / named processor | TBD | TBD | TBD | TBD | TBD |

Answer explicitly:

- Does any raw capture, extracted text, model text, evidence, `HUMAN.md` or
  export leave the Mac?
- Does any workflow send a message, change a task, create a file, make a
  purchase or otherwise act outside the product?
- Which actions require preview or per-action confirmation?
- What analytics are proposed, and what is their exact event schema?
- What is usable offline?
- Where are product credentials stored and how are they revoked?

An unresolved answer blocks that data transfer or external action, not the
rest of the local foundation.

## 6. Distribution decisions

| Decision | Answer | Evidence / owner |
| --- | --- | --- |
| Public or private GitHub repository | public: `Intuition-Lab/who-am-i-personal-card` | product owner decision, 2026-08-07 |
| How the 100 testers receive access | controlled 5 → 20 → 75 waves from an immutable GitHub Release | beta runbook |
| Install command and artifact | checksum-verified self-contained DMG; equivalent `.tar.gz` fallback runs the verified recovery command inside `Who Am I.app/Contents/Resources/product` | README / release workflow |
| Code signing/notarization requirement for this beta | unsigned and unnotarized candidate; explicit tester disclosure required | known issues / release owner |
| Auto-update, manual update, or reinstall | manual immutable-release update via `bash update.sh --interactive` | installation docs |
| Product uninstall behavior | not automated in this candidate; must not be confused with Runtime removal | known issues |
| Runtime uninstall behavior, if offered separately | preserve data by default; permanent deletion requires interactive `DELETE` | uninstall-runtime.sh |
| Support hours and incident owner | TBD | TBD |
| Rollout stop authority | TBD | TBD |
| Pilot observation window | TBD | TBD |
| Expansion observation window | TBD | TBD |
| General-wave observation window | TBD | TBD |
| Minimum successful install rate per wave | TBD | TBD |
| Minimum golden-path success rate per wave | TBD | TBD |
| Maximum total and repeated failure rate per wave | TBD | TBD |
| Threshold denominator, measurement source and missing-response policy | TBD | TBD |
| Threshold approver and emergency stop owner | TBD | TBD |

The beta is distributed as an unsigned, unnotarized self-contained macOS
package that installs an ad-hoc-signed application; it must not be described
as Developer ID signed or notarized. The embedded Personal Model source and
all required notices must be verified as release inputs. Signing, notarization
and clean-machine Gatekeeper behavior remain explicit release decisions and
evidence gates.

## Intake exit gate

Intake is complete only when:

- the golden path and every `must` workflow have observable acceptance
  scenarios;
- every candidate library is pinned and classified for the workflow that uses
  it;
- data and external side effects have explicit trust-boundary decisions;
- beta promise and exclusions are approved;
- repository, distribution, release and support owners are named.

Unresolved `should` or `later` work can remain open. Unresolved `must` behavior
cannot be silently replaced by a smaller feature.
