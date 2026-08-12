# Pinned Runtime CI evidence

Runtime commit:
`59b2d2e154e8d16fb9bb7dfe404a44169a27a9b5`

Upstream run:
[Intuition-Lab/personal-model CI 31279641181](https://github.com/Intuition-Lab/personal-model/actions/runs/31279641181)

## Observed results

- Ubuntu test
  [93158773625](https://github.com/Intuition-Lab/personal-model/actions/runs/31279641181/job/93158773625):
  passed.
- Apple Silicon test
  [93158773654](https://github.com/Intuition-Lab/personal-model/actions/runs/31279641181/job/93158773654):
  passed.
- Intel macOS test
  [93158773635](https://github.com/Intuition-Lab/personal-model/actions/runs/31279641181/job/93158773635):
  passed.
- Package smoke
  [93158773594](https://github.com/Intuition-Lab/personal-model/actions/runs/31279641181/job/93158773594):
  passed.

## Decision boundary

The pinned Runtime commit is green on Ubuntu, Apple Silicon macOS, Intel macOS,
and the package smoke job. The upstream CI release-checklist item is complete
for this Runtime identity.

Separately, this product foundation completed its own isolated Apple Silicon
install, privacy-safe diagnosis, preserve-data uninstall, offline repeated
preserve, separately confirmed later permanent deletion, and late-failure
intent-recovery smoke on macOS 15.6. The completed-install run reported a
healthy pinned Runtime and proved an existing non-interactive update was
rejected before updater execution without changing data or identity receipts.
The separate intent run forced failure after the upstream venv commit but
before either product receipt, then removed that real partial install using
only the stable offline management bundle while preserving product data.

The same full lifecycle also passed after building the exact five
self-contained release assets with `scripts/build-release-assets.sh`,
verifying `SHA256SUMS`, extracting the generated package into a path containing
spaces, and running its installer. This is local Apple-Silicon evidence for
the release artifact and package-path boundary. It validates the product
installer path but does not substitute for the upstream Apple Silicon test
suite or a clean-machine permission test.
