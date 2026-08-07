# Beta task breakdown

This is the execution map from the implemented Who Am I beta candidate to a
qualified product that 100 invited users can install from GitHub. The Personal
Card, local owner flow and packaging are implemented; release operations and
remaining clean-Mac evidence are still gated by
[`product-intake.md`](product-intake.md).

## Delivery definition

“Ready for 100-user GitHub beta” means:

- the release commit can be installed on a supported clean Mac using the exact
  published command;
- the pinned Runtime is installed and verified without a floating dependency;
- every workflow promised in the beta has acceptance evidence;
- personal data and external actions follow the approved trust boundaries;
- upgrade, rollback and support procedures have been rehearsed;
- the release starts with a controlled pilot and can be stopped before all 100
  invitations are used.

Publishing a repository alone does not satisfy this definition.

## Dependency flow

```text
F0 Runtime foundation ───────────────────────────────┐
                                                    ├─> F4 packaging and CI
F1 product intake ─> F2 workflow/library triage ─> F3 product slices
                                                    ├─> F5 clean-Mac proof
                                                    └─> F6 release ─> pilot ─> 100 users
```

`F0` and `F1` can run in parallel. `F2` is a decision gate for each workflow,
so independent product slices can proceed as soon as their own inputs are
complete.

## Implemented slices

`WF-001` is now implemented as the `personal-model-context` Codex plugin:

- `SessionStart` restores behavior and recent durable context, including after
  conversation compaction;
- `UserPromptSubmit` retrieves semantically relevant durable memory every turn;
- the automatic path is read-only, bounded, fail-open, and rejects an
  unverified Runtime installation;
- the plugin and its repo marketplace are included in the release allowlist;
- foundation contract tests cover injection, unavailable Runtime, tampered
  receipts, symlinked executables, oversized input, and absence of automatic
  write/raw-capture calls.

Release qualification still needs a clean installed-plugin test, exact Codex
data-control review, and the normal product acceptance owner/evidence.

`WF-002` is the Personal Card owner slice:

- first launch creates a stable random owner model ID and local Profile;
- production verifies the product-managed Runtime identity and probes
  `get_model_snapshot` over stdio MCP;
- production registers only that owner model and never falls back to a fixture;
- sparse Root/Rewind/Faces remain truthful empty/forming states;
- browser tests prove first-run creation and restart persistence;
- two isolated owner environments prove Profile/Root/Rewind/Identity separation.

`WF-003` is the atomic model switch and permission slice:

- Cecilia and Lin remain explicit development fixtures;
- one active-model Store commits a complete Snapshot per revision;
- owner/public/authorized projections are scope-bound;
- Card, Rewind, Identity, Connector, Report and Evidence isolation is covered
  by contract and browser tests.

## Workstreams

| ID | Workstream | Inputs | Output | Acceptance evidence | Depends on |
| --- | --- | --- | --- | --- | --- |
| F0 | Runtime foundation | reviewed Runtime commit | `runtime.lock`, installer, quick/full verifier, architecture boundary | required repository checks pass; printed install plan shows exact commit | none |
| F1 | Product intake | product artifact, decision owners | completed intake and `must` workflow list | intake exit gate signed off | none |
| F2 | Library and contract triage | workflow list, library repositories | existing/adapt/build/defer decision per workflow; adapter surface selected | pinned source and classification evidence for every candidate | F1 |
| F3 | Product vertical slices | accepted workflow, classified dependency | end-to-end UI/flow plus adapter and failure states | workflow acceptance test, adapter contract test, privacy/log review | F0, relevant F2 row |
| F4 | Product packaging and CI | selected product surface, build instructions | repeatable product install/update/uninstall and release artifact | build from clean checkout; checksum; CI on both architectures where required | F0, distribution decision |
| F5 | Release qualification | release candidate | clean-Mac results, permission retry, upgrade and rollback evidence | all applicable release checklist items linked to direct evidence | F3, F4 |
| F6 | Beta operations | qualified release, tester access, support owner | GitHub release, known issues, wave ledger, incident route | pilot exit gate, then each rollout-wave gate | F5 |

## Product-slice template

Create one slice for each `must` workflow. It should be independently
reviewable and must not mix several unknown user journeys into one task.

```text
Slice ID / workflow ID:
User-visible promise:
Product artifact and acceptance scenario:
Persome surface and exact capability:
Library classification and pinned source:
Data read:
External action/write:
Permissions and secrets:
Empty/loading/degraded/offline/error behavior:
Implementation owner:
Acceptance owner:
Tests and evidence location:
Rollout or rollback concern:
```

A slice is done only when its observable acceptance scenario passes on a
supported Mac and its evidence is linked. Unit tests alone do not prove a
user-visible workflow.

## Immediate parallel tasks before product intake

These tasks are product-agnostic and can be completed without guessing the
feature set:

1. validate shell syntax, the pinned Runtime lock and installer plan;
2. protect `main`, require CI and decide repository visibility/access;
3. define a release evidence location and issue templates for install,
   workflow and privacy incidents;
4. provision the support route and name an incident/rollout owner;
5. reserve Apple Silicon and Intel clean-test Macs;
6. prepare the 100-person invite roster and rollout ledger without collecting
   personal model contents;
7. rehearse restoring the previous product release and `runtime.lock`;
8. prepare known-issues, privacy-boundary and uninstall documentation shells.

These tasks do not authorize publishing a product promise or skipping F1–F5.

## Critical-path decision gates

### Gate A — foundation

Required:

- all commands in `AGENTS.md` that do not need completed onboarding pass;
- the Runtime commit is immutable and resolves to the expected package;
- installer rerun and failure behavior do not delete `~/.persome`;
- notices and supported platform are visible.

### Gate B — scope lock

Required:

- a single golden path;
- a closed list of `must` workflows;
- accepted beta exclusions;
- each workflow has an acceptance owner.

Any new `must` workflow after this gate moves the release date unless the
release approver explicitly removes or replaces other scope.

### Gate C — integration lock

Required per workflow:

- existing/adapt/build/defer classification;
- pinned dependency and license evidence;
- public contract and adapter surface;
- data and side-effect review;
- implementation and test estimate.

### Gate D — release candidate

Required:

- every promised workflow is implemented and has direct evidence;
- product and Runtime identity appear in safe diagnostics;
- no open P0/P1 issue;
- GitHub artifact, checksum, install instructions, known issues and support
  route are final.

### Gate E — expand rollout

Required for each wave:

- previous wave completed its observation window;
- success and incident counts are recorded;
- no unresolved stop condition;
- rollback remains available;
- release owner explicitly records go/hold/rollback.

## Suggested ownership lanes

Names are intentionally blank until the team assigns them.

| Lane | Scope | Owner |
| --- | --- | --- |
| Product | golden path, workflow priority, acceptance and copy | TBD |
| Runtime integration | pin, adapter contracts, health and lifecycle | TBD |
| Product engineering | UI/workflow implementation and product state | TBD |
| Packaging/release | installer, CI, artifacts, update/rollback | TBD |
| Privacy/security | data inventory, logging, secrets and external actions | TBD |
| Beta operations | roster, invitations, support, incidents and wave decisions | TBD |

One person may own multiple lanes, but no release gate may rely on an unnamed
owner.

## Morning handoff sequence

The release owner should review these in order:

1. foundation check results;
2. scope and integration decision tables;
3. promised workflow evidence;
4. clean-Mac, upgrade and rollback records;
5. final tag, checksum and install command;
6. known issues, privacy boundary and support route;
7. pilot roster and explicit go/hold decision.

If product intake arrives too late to qualify its workflows, publish only an
accurately named Runtime foundation/pre-release. Do not present the foundation
as the finished product or invite 100 product testers against unverified
promises.
