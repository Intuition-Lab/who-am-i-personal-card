# Installation and lifecycle

This document covers the complete Who Am I beta installation: the pinned
Persome Runtime, private Node runtime, Personal Card server, local app launcher
and first-run owner profile.

## Requirements

- macOS 13 or newer;
- Apple Silicon or Intel Mac;
- Git and Xcode Command Line Tools;
- an interactive, logged-in desktop session for Accessibility and Screen
  Recording permission onboarding;
- network access while the pinned Runtime and locked dependencies are fetched.

When no Personal Model is present, the first source install is large: it may
fetch a managed Python plus
PaddlePaddle, OpenCV, OCR, and model-client dependencies. Two observed Apple
Silicon dependency preparations took roughly four to seven minutes. Network
conditions can make this longer, including stretches with no new terminal
output. Successful reinstalls and product-managed updates reuse an owner-only,
lock-verified download cache. Preserve-data Runtime uninstall removes that
non-personal cache.

No system Node installation is required. The product downloads the exact
darwin-arm64 or darwin-x64 Node archive and digest in `product.lock`.

Check the host without modifying it:

```bash
bash install.sh --check
bash install.sh --print-plan
```

## Interactive installation

There is no Who Am I GitHub Release while `RELEASE_STATUS=HOLD`. For the
current candidate, use the exact tested source commit in the README. After a
reviewed `GO`, download all assets from one immutable GitHub Release and verify
`SHA256SUMS` before extracting its source bundle.

Use this after entering the verified extracted directory:

```bash
bash install.sh --interactive
```

The installer first checks the fixed local Runtime path. An existing
owner-controlled standalone Personal Model is connected in place: only Who Am
I and its private Node runtime are installed, and the Runtime, model data,
permissions and MCP client configurations are not modified. If no Runtime is
present, the installer fetches only the full commit in `runtime.lock`, verifies
its Git tree, critical file digests and package metadata, then invokes the
upstream source installer.

Before invoking upstream installation it writes an owner-only management intent
for the same immutable source. If permission onboarding or another late step
fails after the Runtime venv is committed, `uninstall-runtime.sh` can still
identify and safely remove that incomplete product-managed install.

The Runtime installer explains system permissions before requesting them. It
also installs an owner-only management bundle that remains usable after the
downloaded release directory is removed. The product additionally installs:

- versioned Card code and private Node under
  `~/.persome/product-app/<product-version>`;
- `~/Applications/Who Am I.app`;
- owner Profile and Card state under
  `~/Library/Application Support/Who Am I` after first use.

When a ready standalone Personal Model already exists, opening Who Am I
connects it automatically. A secure `~/.persome/who-am-i/profile.json` identity
is migrated when present; otherwise the macOS account name becomes the initial
Card identity. The generated stable random `local-*` model ID is persisted
under Application Support and all six product modules use that partition. A
fresh or incomplete Runtime keeps the existing profile and permission flow.
One macOS account maps to one owner Runtime by default.

Immediately after a fresh product-managed Runtime installation:

```bash
MANAGEMENT_ROOT="${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management"
bash "${MANAGEMENT_ROOT}/scripts/diagnose.sh"
bash "${MANAGEMENT_ROOT}/scripts/verify.sh" --quick
bash "${MANAGEMENT_ROOT}/scripts/verify-product.sh"
```

For a connected standalone Runtime, no product management bundle or Runtime
receipt is added. Run its existing `persome doctor` and `persome status`
commands, and verify the Card from the immutable product checkout:

```bash
bash scripts/verify-product.sh
```

After provider setup and onboarding finish:

```bash
bash "${MANAGEMENT_ROOT}/scripts/verify.sh" --full
```

## Optional Codex automatic context

The release archive includes a repo marketplace and the
`personal-model-context` plugin. The Runtime installer intentionally does not
change Codex configuration. Install the plugin separately from the same
immutable Git tag:

```bash
codex plugin marketplace add \
  "Intuition-Lab/who-am-i-personal-card@v0.1.0-beta.3"
codex plugin add personal-model-context@intuition-lab
```

Start a new task, use `/hooks` to inspect and trust the exact `SessionStart`
and `UserPromptSubmit` definitions, then test a prompt that depends on known
durable memory. The plugin fails open when the Runtime is absent or cannot
prove its product-managed identity.

The plugin sends bounded recalled Personal Model passages into the active
Codex conversation. It does not automatically write memory or retrieve raw
screen captures. Disable or remove the plugin to stop automatic recall.

## Non-interactive fresh installation

Automation may perform a fresh dependency installation without showing
permission dialogs:

```bash
bash install.sh --non-interactive
```

This mode is rejected when a product-managed Runtime already exists, because
an update must reverify real permissions and Runtime health before replacing
the working environment. A fresh non-interactive install does not claim that
capture is ready. A logged-in user must later run:

```bash
"${PERSOME_INSTALL_HOME:-$HOME/.persome}/venv/bin/persome" onboard
bash "${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management/scripts/verify.sh" --full
open "$HOME/Applications/Who Am I.app"
```

The final command opens the same first-run flow used by an interactive install.
After Runtime onboarding, Who Am I creates the Personal Card name, handle and
stable product model ID; an already-ready standalone Runtime is connected
without running this path.

## Reinstall and update

Re-running the installer uses the same immutable Runtime source and preserves
the Runtime data root and existing owner secrets through the upstream
transactional installer. A standalone existing Runtime remains standalone:
re-running this product installer updates only the versioned Card and private
Node runtime.

Do not run `persome update` directly for an installation managed by this
product. The standalone updater follows its configured source and can move
beyond the commit reviewed in `runtime.lock`. The product update wrapper may
invoke the Runtime's transactional updater internally, but supplies only the
verified source checkout from the immutable product release. The product
installer writes matching identity receipts outside and inside the installed
virtual environment; replacing the venv through another updater makes
verification fail instead of treating the same package version as proof of
source identity.

To move to a newer product release:

1. download or check out the new immutable product tag;
2. verify its release checksum;
3. inspect its `runtime.lock` and release notes;
4. run `bash update.sh --interactive`;
5. restart editors that host a Persome stdio MCP process;
6. run the installed management bundle's `scripts/verify-product.sh`;
7. run `scripts/verify.sh --full` after Runtime onboarding is complete.

Never update a beta by changing a prior tag or replacing an asset in place.
An update requires a logged-in interactive terminal so permission and capture
health can be proven before commit. Non-interactive update requests fail before
source download or updater execution, leaving the verified Runtime environment
and personal data in place.

## Rollback

Check out the previous qualified product release and run its installer. The
previous release carries its own reviewed `runtime.lock`.

A product rollback must preserve `~/.persome`. Do not delete the Runtime data
root to work around a product or dependency regression.

## Uninstall boundary

Runtime removal and product-app removal are separate. This beta automates only
the Runtime operation. It does not remove `Who Am I.app`, the versioned private
Node/Card directory, or the owner profile in Application Support.

Runtime removal already has two distinct choices. The default preserves
personal data:

```bash
MANAGEMENT_ROOT="${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management"
bash "${MANAGEMENT_ROOT}/uninstall-runtime.sh" --preserve-data
```

The preserve operation removes the managed venv, managed Python and command
shim, writes a verified data-only marker, and retains the management bundle.
It is idempotent and does not need GitHub access after a completed install.

Permanent deletion remains possible from that stable bundle. It requires a
separate interactive command and the product's `DELETE` confirmation before
any Runtime artifact is changed:

```bash
bash "${MANAGEMENT_ROOT}/uninstall-runtime.sh" --delete-data
```

Neither command is a product-app uninstaller. Do not describe it as deleting
Who Am I or the Card profile. Product-app uninstall automation remains a
documented beta limitation.

The bundle contains a digest-verified copy of the pinned upstream uninstaller.
GitHub is used only as a verified fallback if that cached copy is missing.
Never manually delete Runtime paths to work around an ownership or integrity
error.
