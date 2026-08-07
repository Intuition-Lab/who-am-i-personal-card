# Who Am I · Personal Card

Installable macOS product built on the
[Persome Personal Model Runtime](https://github.com/Intuition-Lab/personal-model).

Each downloader connects the same UI to the Personal Model owned by that macOS
account. A secure existing standalone Runtime is reused automatically; a new
Runtime and stable local Personal Card identity are created only when needed.
Card, Rewind, Identity, Connector, Report, and Evidence data stay bound to that
local model.
Cecilia and Lin exist only as explicit development fixtures and are never
registered by a production launch.

The source candidate includes the Card UI, a pinned private Node.js runtime, the
reproducible Persome Runtime installer, verification and support tooling, and
an optional Codex plugin that recalls relevant Personal Model context on every
turn.

`RELEASE_STATUS` is currently `HOLD`. Tagging this candidate cannot publish a
GitHub Release until a release owner records a reviewed `GO` decision.
There is currently no Who Am I GitHub Release or release tag; the tested source
install below is the only public installation path. The immutable-release
command is documented for the later approved release and will return `404`
until that release exists.

The backend is already public at
[Intuition-Lab/personal-model](https://github.com/Intuition-Lab/personal-model).
It is a local Runtime rather than a hosted cloud API. During a fresh install,
Who Am I anonymously fetches and verifies the exact public commit in
`runtime.lock`, then installs it under the signed-in user's `~/.persome`.
Production communicates with that local Runtime over stdio, so one person's
model database is never bundled into another person's download.

## Current beta boundary

- macOS 13 or newer.
- Apple Silicon and Intel Macs.
- Runtime data stays under `~/.persome` by default.
- Product profile and model-partitioned Card state stay owner-locally under
  `~/Library/Application Support/Who Am I`.
- The installed application is `~/Applications/Who Am I.app`.
- One macOS account maps to one owner Runtime by default. Different people on
  the same Mac should use separate macOS accounts; changing only a display name
  does not create a separate memory store.
- The Runtime source is fixed to the full commit recorded in `runtime.lock`.
- An existing owner-controlled `~/.persome/venv/bin/persome` is connected in
  place. The product does not replace it, claim it as product-managed, repeat
  onboarding, or modify its data.
- Node.js is pinned in `product.lock`; users do not need a preinstalled Node.
- The Runtime installer does not modify Claude, Codex, Cursor, or other MCP
  client configurations. The Codex plugin is a separate, explicit install.

## Install the current tested source candidate

The following command installs the exact public source revision that passed
the repository CI and isolated Apple Silicon installation test:

```bash
(
  set -euo pipefail
  SOURCE_COMMIT="395c15aa40a01f4f141e28d7518beba8fdb50453"
  CHECKOUT_DIRECTORY="$(
    mktemp -d "${TMPDIR:-/tmp}/who-am-i-personal-card.XXXXXX"
  )"
  git clone \
    https://github.com/Intuition-Lab/who-am-i-personal-card.git \
    "${CHECKOUT_DIRECTORY}"
  cd "${CHECKOUT_DIRECTORY}"
  git checkout --detach "${SOURCE_COMMIT}"
  bash install.sh --interactive
)
```

The application is currently unsigned and unnotarized. macOS may ask the user
to confirm opening it, and Accessibility and Screen Recording permissions must
be approved by the signed-in user. On first launch, an existing Personal Model
connects automatically. A prior Who Am I profile is migrated when available;
otherwise the macOS account name becomes the initial local Card identity. A
Mac without an initialized Personal Model keeps the existing profile and
permission flow. Production never registers the Cecilia or Lin development
fixtures.

## Install an immutable release after `RELEASE_STATUS=GO`

```bash
(
  set -euo pipefail
  REPOSITORY="Intuition-Lab/who-am-i-personal-card"
  VERSION="0.1.0-beta.3"
  REPOSITORY_NAME="${REPOSITORY##*/}"
  RELEASE_BASE="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"
  DOWNLOAD_DIRECTORY="$(
    mktemp -d "${TMPDIR:-/tmp}/${REPOSITORY_NAME}-${VERSION}-download.XXXXXX"
  )"

  cd "${DOWNLOAD_DIRECTORY}"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "${RELEASE_BASE}/${REPOSITORY_NAME}-${VERSION}.tar.gz"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "${RELEASE_BASE}/RELEASE-METADATA.txt"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "${RELEASE_BASE}/RELEASE-NOTES.md"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "${RELEASE_BASE}/SHA256SUMS"
  test "$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
  shasum -a 256 --check SHA256SUMS
  tar -xzf "${REPOSITORY_NAME}-${VERSION}.tar.gz"
  cd "${REPOSITORY_NAME}-${VERSION}"
  bash install.sh --interactive
)
```

The subshell exits on the first failed download or verification and uses a new
directory on every attempt, so stale files cannot carry a failed attempt into
installation. Do not install from a floating default branch.

Before changing anything on the Mac, inspect the plan and prerequisites:

```bash
bash install.sh --print-plan
bash install.sh --check
```

Automation may install the pinned Runtime without opening permission dialogs:

```bash
bash install.sh --non-interactive
```

For a fresh Runtime, that mode deliberately leaves onboarding pending. An
already-ready standalone Personal Model stays ready.

The interactive install first checks for an existing owner-controlled Personal
Model. When one is ready, it installs only the Card, opens Who Am I, imports an
existing Card identity when available, and connects without repeating
permissions or onboarding. Otherwise it installs the pinned Runtime and opens
the existing profile/permission flow. A new model may initially be sparse or
“forming”; it never falls back to another person's demo memory.

If the command is run without an interactive terminal, finish Runtime
onboarding and then open Who Am I:

```bash
"${PERSOME_INSTALL_HOME:-$HOME/.persome}/venv/bin/persome" onboard
open "$HOME/Applications/Who Am I.app"
```

For a Runtime installed by this product, the installer leaves a small
owner-only management bundle under the Runtime data root. Its commands keep
working after the downloaded release directory is deleted:

```bash
MANAGEMENT_ROOT="${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management"
bash "${MANAGEMENT_ROOT}/scripts/diagnose.sh"
bash "${MANAGEMENT_ROOT}/scripts/verify.sh" --quick
bash "${MANAGEMENT_ROOT}/scripts/verify-product.sh"
```

When Who Am I connects an existing standalone Personal Model, it deliberately
does not add product Runtime receipts or management commands. Use that
Runtime's existing `persome doctor` / `persome status` commands, and use
`bash scripts/verify-product.sh` from the immutable Who Am I checkout to verify
the Card installation.

Run full verification only after the LLM provider is configured and onboarding
is complete:

```bash
bash "${MANAGEMENT_ROOT}/scripts/verify.sh" --full
```

## Enable automatic Personal Model context in Codex

The release also contains the `personal-model-context` plugin. After installing
the Runtime, add the immutable product repository as a Codex marketplace and
install the plugin:

```bash
codex plugin marketplace add \
  "Intuition-Lab/who-am-i-personal-card@v0.1.0-beta.3"
codex plugin add personal-model-context@intuition-lab
```

Start a new Codex task, open `/hooks`, and review and trust the two plugin hooks.
Codex binds that trust to the exact hook definition and asks again after a hook
change.

When enabled, the plugin:

- loads the behavior model and recent durable activity at startup, resume,
  clear, and post-compaction;
- runs semantic durable-memory search for each user prompt;
- never calls automatic memory-write or raw-capture tools;
- treats recalled text as untrusted data and warns the agent not to follow
  instructions found inside memory;
- fails open, so an unavailable or unverified Runtime never blocks the
  conversation.

The bounded recalled passages are supplied to the active Codex conversation
and may therefore be processed and retained according to that Codex account's
data controls. Installing and trusting the plugin is the explicit consent
boundary; disable or remove it to stop automatic injection.

Update from a newly downloaded immutable product release:

```bash
bash update.sh --interactive
```

Updates are intentionally interactive: the pinned Runtime's transactional
updater must reverify permissions, capture readiness, and health before
committing a replacement. A non-interactive request against an existing
Runtime is rejected before source download or updater execution; the verified
Runtime environment and personal data remain in place. Do not run the floating
`persome update` command directly.

Remove the managed Runtime executables while preserving personal data:

```bash
bash "${MANAGEMENT_ROOT}/uninstall-runtime.sh" --preserve-data
```

Permanent Runtime-data deletion is a distinct interactive operation:

```bash
bash "${MANAGEMENT_ROOT}/uninstall-runtime.sh" --delete-data
```

Preserve-data removal is repeatable and leaves the verified management bundle
available offline. The later delete command requires typing `DELETE` before
anything is changed.

These Runtime commands do not delete the Personal Card launcher, its versioned
private Node runtime, or the owner profile in Application Support. Product-app
uninstall is not automated in this beta; see `docs/known-issues.md` before
removing those paths.

## Why this repository pins source

Upstream `main` currently contains substantial post-v0.3.2 work while its
package metadata still says `0.3.2`. Installing `personal-model==0.3.2` from
PyPI therefore does not install the same code as the reviewed source used here.
`runtime.lock` records the exact commit until a new upstream release is cut and
validated. It also records the Git tree and SHA-256 digests for the upstream
installer and dependency locks. A successful product installation writes an
owner-only receipt under the Runtime data root; `scripts/verify.sh` checks that
receipt, a second identity marker inside the pinned virtual environment, and
the installed package instead of trusting an unrelated `persome` found on
`PATH`.

Do not run `persome update` directly for a product-managed installation. That
command follows the Runtime's configured update source instead of this
product's immutable lock. Runtime updates ship as a new reviewed product tag;
its product wrapper may invoke the transactional updater internally, but only
against the verified source checkout for that tag.

Update the pin only in a dedicated reviewed change:

```bash
bash scripts/validate-runtime-lock.sh
```

## Repository map

| Path | Purpose |
| --- | --- |
| `runtime.lock` | Immutable Runtime repository, commit, version, and CLI contract |
| `product.lock` | Immutable private Node runtime version and official SHA-256 digests |
| `apps/personal-card/` | Existing V5 UI, local server, Provider/auth/store/setup layers and tests |
| `.agents/plugins/marketplace.json` | GitHub-installable Intuition Lab Codex plugin catalog |
| `plugins/personal-model-context/` | Automatic, read-only per-turn Personal Model recall for Codex |
| `release.manifest` | Explicit top-level allowlist for the source Release archive |
| `RELEASE_STATUS` | Machine-enforced `HOLD`/`GO` publication decision |
| `PILOT_STATUS` | Separate `HOLD`/`GO` decision for exactly the first five testers |
| `install.sh` | Supported macOS source installation entry point |
| `update.sh` | Reinstall through the current product tag's immutable Runtime lock |
| `uninstall-runtime.sh` | Explicit Runtime removal with preserve/delete separation |
| `scripts/verify.sh` | Quick and full installed-Runtime checks |
| `scripts/verify-product.sh` | Installed Card, private Node and app-launcher integrity check |
| `scripts/diagnose.sh` | Privacy-safe human/JSON support diagnostic |
| `scripts/build-release-assets.sh` | Deterministic four-asset Release builder |
| `scripts/bootstrap-github-repository.sh` | Fail-closed initial commit, new-repository and first-push bootstrap |
| `scripts/github-repository-controls.sh` | Plan, apply, and verify GitHub release controls |
| `scripts/release-readiness.sh` | Reject publication unless the decision is `GO` |
| `scripts/pilot-readiness.sh` | Reject tester invitations until the immutable release and five-user pilot decision are verified |
| `scripts/scan-secrets.sh` | Scan source, complete Git history, and the exact extracted Release with a pinned verified scanner |
| `scripts/smoke-install.sh` | Isolated real install/diagnose/uninstall gate |
| `scripts/validate-runtime-lock.sh` | Supply-chain and package-contract check |
| `docs/architecture.md` | Product/Runtime boundary and integration rules |
| `docs/diagnostics.md` | Safe diagnostic schema, states, and exit codes |
| `docs/evidence/` | Reviewable upstream and release-qualification evidence |
| `docs/github-repository-setup.md` | Safe new-repository and Release-control order |
| `docs/installation.md` | Interactive/non-interactive install, update, and rollback |
| `docs/known-issues.md` | Explicit unqualified and product-dependent release gates |
| `docs/product-intake.md` | Required product, workflow, library, and distribution inputs |
| `docs/task-breakdown.md` | F0–F6 execution streams and release decision gates |
| `docs/beta-runbook.md` | 100-user rollout and support procedure |
| `docs/release-checklist.md` | Evidence required before a GitHub beta release |
| `docs/release-notes/` | Version-controlled release promises and limitations |

The Personal Card UI and automatic Personal Model recall inside Codex are both
implemented. Release publication remains gated by the reviewable
`RELEASE_STATUS` and `PILOT_STATUS` decisions.
