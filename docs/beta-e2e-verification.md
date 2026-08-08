# Personal Model beta end-to-end verification

This is the repeatable release qualification for the two-day Personal Model
beta. It uses synthetic fixtures only. Passing the automated gate does not
change `RELEASE_STATUS`; the release owner still makes that reviewed decision.

## Merge-blocking gate

Run on macOS 13 or newer with Xcode Command Line Tools, Node, npm and Python 3:

```bash
bash scripts/beta-release-gate.sh
```

The command stops at the first failure and prints the failed stage. It covers:

- JavaScript syntax, website TypeScript, and Python syntax;
- 28 deterministic content-quality scenarios and Connector isolation;
- the complete Personal Card unit/server suite;
- development and production browser flows, including the no-demo payload;
- Swift type checking and a universal `arm64`/`x86_64` native launcher;
- website build, rendered HTML assertions and lint;
- package/foundation tests, release controls, and the pinned Runtime lock.

`scripts/build-release-assets.sh` invokes this gate before constructing a DMG,
so a failed stage prevents release asset creation and publication.

## DMG verification without a development checkout

The following inspection needs only macOS built-in tools. Keep the DMG and the
release `SHA256SUMS` file in the same new directory, then set `PACKAGE` to the
downloaded filename without the `.dmg` suffix:

```bash
set -euo pipefail
PACKAGE="who-am-i-0.1.0-beta.5-self-contained-macos"
shasum -a 256 --check SHA256SUMS
hdiutil verify "${PACKAGE}.dmg"

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/whoami-dmg-check.XXXXXX")"
hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_POINT}" \
  "${PACKAGE}.dmg"
cleanup() {
  hdiutil detach "${MOUNT_POINT}" >/dev/null || true
  rmdir "${MOUNT_POINT}" >/dev/null || true
}
trap cleanup EXIT

APP="${MOUNT_POINT}/Who Am I.app"
PRODUCT="${APP}/Contents/Resources/product"
test -x "${APP}/Contents/MacOS/WhoAmI"
test "$(plutil -extract WhoAmIBootstrapInstall raw -o - \
  "${APP}/Contents/Info.plist")" = "true"
test "$(plutil -extract LSMinimumSystemVersion raw -o - \
  "${APP}/Contents/Info.plist")" = "13.0"
codesign --verify --deep --strict "${APP}"
lipo "${APP}/Contents/MacOS/WhoAmI" -verify_arch arm64 x86_64

test -f "${PRODUCT}/apps/personal-card/persome-card-server.mjs"
test -f "${PRODUCT}/apps/personal-card/whoami-mcp-proxy.mjs"
test -f "${PRODUCT}/runtime-source/pyproject.toml"
test -x "${PRODUCT}/runtime-source/install.sh"
test -x "${PRODUCT}/Install Who Am I.command"
test -f "${PRODUCT}/SELF-CONTAINED-SHA256SUMS"
(
  cd "${PRODUCT}"
  shasum -a 256 --check SELF-CONTAINED-SHA256SUMS
)
test -z "$(find "${APP}" -type l -print -quit)"
test -z "$(find "${APP}" -perm -002 -print -quit)"
```

The App embeds the reviewed JavaScript backend and the pinned Python Runtime
source. The managed Node and Python executables are installed and verified by
the first-run installer; they are not represented as already-installed
executables inside the mounted DMG.

## First-launch path on a qualification Mac

Use a disposable macOS account with no product installation. Double-click
`Who Am I.app` in the mounted DMG. The expected path is:

1. the bootstrap App reads its embedded product directory;
2. it opens the embedded `Install Who Am I.command`;
3. the installer verifies the embedded manifest and pinned Runtime, installs
   managed Node/Python under the signed-in account, and builds the installed
   native App;
4. the installed App opens from `~/Applications/Who Am I.app` and talks only to
   its loopback backend.

After the first launch completes, verify the installed runtimes and App:

```bash
bash "$HOME/.persome/product-management/scripts/verify.sh" --quick
bash "$HOME/.persome/product-management/scripts/verify-product.sh"
```

Local ad-hoc signing is structurally verified by `codesign`, but it is not
Developer ID signing or Apple notarization. Gatekeeper assessment and initial
screen/accessibility permission prompts must therefore be recorded on the
qualification Mac; they must not be reported as passed from source inspection.
