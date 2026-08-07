# Pinned Runtime CI evidence

Runtime commit:
`e1315d03cafb62418503e6d92b9e73400720fcd4`

Upstream run:
[Intuition-Lab/personal-model CI 31116661384](https://github.com/Intuition-Lab/personal-model/actions/runs/31116661384)

## Observed results

Attempt 1 on 2026-08-06:

- Ubuntu test: passed.
- Package smoke: passed.
- Apple Silicon and Intel jobs: failed while GitHub Actions returned
  `Service Unavailable` downloading actions. The failures occurred in runner
  infrastructure, before they could establish useful macOS test evidence.

Attempt 2:

- Intel job
  [92690580988](https://github.com/Intuition-Lab/personal-model/actions/runs/31116661384/job/92690580988):
  passed all steps, including the offline test suite, Apple Health Swift
  package, real Intel Vision OCR smoke, privacy/secret gates, documentation
  checks, and synthetic MCP transport smoke.
- Ubuntu and package smoke remained successful.
- Apple Silicon job
  [92690580983](https://github.com/Intuition-Lab/personal-model/actions/runs/31116661384/job/92690580983):
  GitHub reported no runner name and zero steps, then cancelled it after
  15 minutes. No upstream code or test step executed.

A targeted retry of the Apple Silicon job was requested after attempt 2.
GitHub created attempt 3 job
[92695112413](https://github.com/Intuition-Lab/personal-model/actions/runs/31116661384/job/92695112413),
then cancelled it at 2026-08-06 20:32:34 UTC after more than two hours with an
empty runner name and zero steps. GitHub never allocated a runner; no checkout,
upstream code, or test step executed. The overall run therefore concluded
`failure` even though Intel, Ubuntu, and package jobs passed.

## Decision boundary

The Intel, Ubuntu, and package evidence is green. The Apple Silicon upstream
suite is still unexecuted because of runner infrastructure, so the upstream CI
release-checklist item remains open.

Separately, this product foundation completed its own isolated Apple Silicon
install, privacy-safe diagnosis, preserve-data uninstall, offline repeated
preserve, separately confirmed later permanent deletion, and late-failure
intent-recovery smoke on macOS 15.6. The completed-install run reported a
healthy pinned Runtime and proved an existing non-interactive update was
rejected before updater execution without changing data or identity receipts.
The separate intent run forced failure after the upstream venv commit but
before either product receipt, then removed that real partial install using
only the stable offline management bundle while preserving product data.

The same full lifecycle also passed after building the exact four release
assets with `scripts/build-release-assets.sh`, verifying `SHA256SUMS`,
extracting the generated source archive into a path containing spaces, and
running the installer from that extracted archive. This is local
Apple-Silicon evidence for the release artifact and checkout-path boundary. It
validates the product installer path but does not substitute for the upstream
Apple Silicon test suite or a clean-machine permission test.
