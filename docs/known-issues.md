# Who Am I beta known issues

These limitations apply to the implemented Personal Card beta candidate and
remain release or rollout gates where stated.

## Distribution

- There is no signed or notarized `.app`, `.dmg`, or `.pkg`. The current
  distribution is a GitHub source archive plus a terminal installer.
- The new GitHub organization, repository name, visibility, tester access and
  exact download URL are not decided.
- The product license and redistribution policy are not decided.

## Runtime version

- The reviewed Runtime commit contains substantial work after upstream
  `v0.3.2`, but its project metadata still says `0.3.2`.
- PyPI `personal-model==0.3.2` is not equivalent to the source pinned here.
- Installation therefore uses the commit, tree and file digests in
  `runtime.lock`; it must not be replaced with a floating branch or the current
  PyPI package.
- Users must not run `persome update` directly for product-managed
  installations. Updates are delivered by a new immutable product tag and its
  product update wrapper. That wrapper may use the pinned source tree's
  transactional updater internally.
- Updating an existing Runtime requires a logged-in interactive terminal and
  successful permission/capture health proof. Non-interactive updates are
  rejected before source download or updater execution.
- A completed install caches a digest-verified upstream uninstaller in the
  owner-only management bundle, so preserve-data uninstall and later deletion
  work without GitHub access. If the cache is absent, the safe fallback still
  requires GitHub access; do not manually delete Runtime paths after an
  ownership or integrity failure.

## Platform qualification

- The installer has completed an isolated non-interactive end-to-end run on an
  Apple Silicon Mac.
- The exact generated release archive has completed the same lifecycle after
  checksum verification and extraction into a path containing spaces on Apple
  Silicon.
- A fresh source install downloads a managed Python when needed and a large
  locked dependency set, including the PaddlePaddle and OpenCV archives.
  Dependency preparation took between roughly two and seven minutes across
  observed Apple Silicon runs; tester network conditions can make it longer.
  Long periods without terminal output during these downloads are possible.
- Product-level Intel installation has not yet been executed outside GitHub
  runner prerequisite checks.
- Full interactive verification still requires clean Macs with real
  Accessibility and Screen Recording permission flows.
- The minimum supported macOS 13 path still needs clean-machine evidence.

## Product

- The product name, existing V5 UI and owner-local first-run flow are
  implemented. The supported golden path is install → create local Card
  identity → complete Persome onboarding → reopen the same owner model.
- One macOS account maps to one owner Runtime. Changing the Card display name
  does not create a second isolated memory store; use separate macOS accounts
  or explicitly separate `PERSOME_ROOT` values for different people.
- New models may be sparse or forming. A completed install is not a promise
  that Root/Faces already exist; permissions, activity and optional LLM
  provider setup affect model construction.
- Production verifies the product-managed Runtime receipts and probes
  `get_model_snapshot` over stdio MCP. It does not trust an arbitrary
  `persome` on `PATH` or an unauthenticated local MCP service.
- Cecilia and Lin remain in source as development fixtures and contract-test
  inputs. The installed production app omits fixture and test directories and
  never registers those models.
- Automatic durable-memory recall is implemented for Codex, but the
  GitHub-installed plugin and hook-trust flow still need clean-Mac acceptance
  evidence. It does not cover other agent clients.
- Recalled passages enter the active Codex conversation. The release owner must
  approve the applicable Codex processor/retention controls and beta disclosure
  before invitations.
- Updating to a new immutable product version refreshes the verified app
  launcher and installs a new versioned Card/Node directory while preserving
  Runtime data and the owner profile. Cross-version clean-Mac evidence remains
  a release gate.
- Product-app removal is not automated. Runtime preserve/delete commands do
  not remove `Who Am I.app`, the versioned Card/Node directory or
  `~/Library/Application Support/Who Am I`.
- The final GitHub repository, visibility, source license, support route,
  rollout owners and thresholds are not approved. `RELEASE_STATUS=HOLD` is
  therefore intentional.

These are release gates, not silent assumptions. Track evidence in
`release-checklist.md` and remove an item only when the corresponding supported
configuration has been directly verified.
