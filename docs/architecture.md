# Architecture boundary

The Who Am I Personal Card and Personal Model Runtime are separate release
units. The existing V5 UI is the product surface; this document records its
owner-profile, Provider, session and Runtime boundaries.

```text
Product UI / workflows / Codex context plugin / agent orchestration
                              |
                 product-owned adapter layer
                              |
          CLI lifecycle | stdio MCP | loopback REST | exports
                              |
            pinned Persome Personal Model Runtime
                              |
      captures -> timeline -> sessions -> model -> HUMAN.md
```

## Release units and ownership

| Concern | Product repository | Runtime repository |
| --- | --- | --- |
| User-facing journey | navigation, workflow state, copy, empty/error/degraded states | Runtime onboarding and model viewer only |
| Product behavior | notifications, tasks, collaboration and agent actions | capture, OCR, sessionization, memory and model construction |
| Integration | adapters and capability detection | CLI, MCP, REST and export contracts |
| Storage | owner Profile and partitioned Card/Connector state under `~/Library/Application Support/Who Am I` | owner-local SQLite and Markdown under `~/.persome` |
| Distribution | product version, installer, release notes and support | independently versioned Runtime |
| Diagnostics | product-safe health signals with explicit user consent | Runtime health and provenance |

Product code must not assume ownership of Runtime processes, files or schema
beyond a documented public contract. Runtime code must not absorb a
product-specific workflow simply because the first product needs it.

## Allowed integration surfaces

Choose one primary surface for each feature during intake and record the reason.

| Surface | Use when | Product obligations |
| --- | --- | --- |
| CLI | install, onboarding, health, start/stop, status or a bounded user action | check exit status; set a timeout; redact output before support collection |
| stdio MCP | a trusted local agent needs semantic Personal Model tools | launch locally; allowlist tools; surface user-visible action and failure state |
| loopback REST | a local UI needs request/response or streaming access | bind and connect only to loopback; keep the bearer token out of source, logs and URLs |
| export/snapshot | the user explicitly requests a portable point-in-time artifact | make scope and destination visible; treat output as personal data |

Do not integrate by:

- reading or mutating `~/.persome/index.db`;
- scraping the Runtime viewer;
- importing Runtime-private Python modules;
- exposing the owner-local Runtime server outside loopback;
- copying Runtime source into this repository;
- logging captures, model text, evidence receipts, `HUMAN.md`, exports, bearer
  tokens or model/API credentials.

## Adapter contract

Every product feature that uses Persome goes through a product-owned adapter.
The concrete language and module layout are decided after product intake, but
the interface must preserve these behaviors:

1. `capabilities` reports whether the pinned Runtime supports the exact
   operation. A missing capability becomes a product degraded state, not an
   unhandled exception.
2. `health` distinguishes not installed, not onboarded, permission missing,
   stopped, unhealthy and ready.
3. read operations return a product-owned result type rather than leaking a
   Runtime response throughout the product.
4. write or agent-action operations are explicit, auditable and cancelable
   where the Runtime contract permits.
5. errors are mapped to stable product error codes plus safe user remediation.
6. deadlines, retries and process cleanup are defined; retries never duplicate
   an external side effect.
7. the adapter reports product version and Runtime commit for diagnostics but
   never reports personal content by default.

Each adapter requires contract tests against the exact commit in
`runtime.lock`. An upgrade of that commit is a reviewed dependency change with
adapter tests and rollback evidence, never a floating dependency update.

## Implemented Codex context adapter

`plugins/personal-model-context` is one concrete product-owned adapter.
It uses Codex `SessionStart` and `UserPromptSubmit` hooks and the installed
Runtime's public stdio MCP surface:

```text
session start/resume/compact -> behavior_patterns + recent_activity
each user prompt             -> search(query=prompt, top_k=5)
                                      |
                         bounded untrusted context
                                      |
                         active Codex conversation
```

The adapter verifies owner-only directories, the product Runtime lock and both
installation identity receipts before starting `persome mcp`. It uses a
sanitized process environment, a total deadline, bounded input and output, and
process-group cleanup. Runtime absence, timeout, incompatible output or failed
identity checks produce no hook context and never block the conversation.

The automatic path is deliberately read-only. It never calls `remember`,
`correct_memory`, `search_captures`, or a transcript parser. This plugin does
not register a general-purpose Runtime MCP connection. If one is separately
configured, durable writes remain explicit agent actions after a user request,
and raw capture lookup remains an on-demand action.

## Implemented Personal Card adapter

`apps/personal-card` provides a second concrete product adapter:

```text
owner-profile.json -> stable local model ID
                           |
                    Provider registry
                           |
            verified product-managed persome mcp
                           |
        one immutable Snapshot per model revision
                           |
 Card / Rewind / Identity / Connector / Report / Evidence
```

Production startup registers only the current owner Profile. Cecilia and Lin
are explicit development fixtures and are not registered by a production
launch. The server binds to `127.0.0.1`, verifies the product-managed Runtime
receipts, and uses the managed stdio MCP executable. Production does not select
an arbitrary `persome` from `PATH` and does not trust unauthenticated loopback
MCP as owner identity.

The product stores only display/profile fields and product-owned operational
state. It does not read Runtime database contents. MCP `get_model_snapshot`
proves the Runtime can answer and reports whether the Personal Model is still
forming or has completed a build.

## Data and trust boundaries

Assume all data crossing a Runtime surface is personal. Runtime storage remains
on the user's Mac, but the enabled Codex plugin supplies bounded recalled
passages to the active Codex conversation. That transfer requires explicit
plugin installation and exact hook review, and its processor/retention terms
remain a release qualification item. Any other proposed sync, analytics,
collaboration, remote model, or external action crosses a new trust boundary
and is blocked from implementation until the intake records:

- data fields and purpose;
- destination and processor;
- retention and deletion behavior;
- user consent and revocation path;
- authentication and secret storage;
- offline and failure behavior;
- the acceptance evidence for “nothing personal leaves by default.”

The same decision gate applies to existing libraries. “Already built” does not
make a library safe to distribute in this product.

## Remaining product-definition decisions

The implemented name, surface, owner-local golden path and data locations are
recorded in [`product-intake.md`](product-intake.md). Repository visibility,
licensing, support ownership, rollout thresholds and any new external
integration remain release decisions; they do not authorize expanding the
current local beta promise.

The implementation plan and dependency gates are in
[`task-breakdown.md`](task-breakdown.md).
