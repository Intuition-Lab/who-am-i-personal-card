# Product repository guidance

This repository is the product layer built on top of the Persome Personal Model
Runtime.

## Boundaries

- Keep the Runtime pinned in `runtime.lock`. Never depend on a floating branch.
- Users must not run the floating `persome update` command directly. A Runtime
  update is a new reviewed product tag; its wrapper may invoke the pinned
  source tree's transactional updater internally.
- Do not copy Runtime source into this repository. Install the pinned source and
  integrate through the public CLI, MCP, REST, or snapshot contracts.
- Do not read or mutate `~/.persome/index.db` directly.
- Do not expose the owner-local Persome HTTP server outside loopback.
- Treat MCP access, Runtime exports, captures, and `HUMAN.md` as personal data.
- Product-specific UI, notifications, tasks, and agent orchestration belong
  here, not in the Runtime repository.
- Preserve the notices in `THIRD_PARTY_NOTICES.md` when distributing the
  product.

## Supported beta platform

- macOS 13 or newer.
- Apple Silicon and Intel Macs.
- Xcode Command Line Tools are required for the native capture helpers.

## Required checks

```bash
bash -n ./*.sh scripts/*.sh scripts/lib/*.sh tests/*.sh
shellcheck -x ./*.sh scripts/*.sh scripts/lib/*.sh tests/*.sh
# Run on supported macOS, where uninstall TTY and permission semantics apply.
bash tests/foundation.sh
bash scripts/release-readiness.sh --check
bash scripts/validate-runtime-lock.sh
bash scripts/github-repository-controls.sh --plan \
  --repository OWNER/REPOSITORY \
  --release-actor user:RELEASE_ACTOR \
  --release-reviewer user:RELEASE_REVIEWER
bash install.sh --print-plan
bash update.sh --print-plan
bash uninstall-runtime.sh --print-plan
```

Validate `.github/workflows/*.yml` with the pinned actionlint version in CI.
On macOS, run `bash scripts/smoke-install.sh --uninstall-via-receipt` before a
release candidate is approved.

`RELEASE_STATUS` remains `HOLD` until the release checklist has direct evidence
and the named release owner changes it to `GO` in a reviewed commit. Release
automation must use `scripts/release-readiness.sh --require-go`.

Run `bash scripts/verify.sh --full` on a clean, interactive Mac after installation.
