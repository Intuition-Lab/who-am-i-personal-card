#!/usr/bin/env bash
set -euo pipefail
umask 077
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_build_tool() {
  local name="$1"
  local resolved candidate
  resolved="$(command -v "${name}" 2>/dev/null || true)"
  if [[ -n "${resolved}" && -x "${resolved}" ]]; then
    printf '%s\n' "${resolved}"
    return
  fi
  for candidate in \
    "/opt/homebrew/bin/${name}" \
    "/usr/local/bin/${name}" \
    "/usr/bin/${name}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
}

NODE_BIN="$(find_build_tool node)"
NPM_BIN="$(find_build_tool npm)"
PYTHON_BIN="$(find_build_tool python3)"

usage() {
  cat <<'EOF'
Usage: bash scripts/beta-release-gate.sh

Run the merge-blocking Personal Model beta gate on macOS. The gate checks
JavaScript, Python and Swift; deterministic content evals; Connector isolation;
browser/no-demo flows; the universal native launcher; website; and package
source/foundation checks. Any failed stage exits non-zero with its stage name.
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown beta release gate option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  printf '%s\n' \
    '[beta gate] BLOCKED: macOS is required for Swift and native App checks.' >&2
  exit 1
fi
for requirement in \
  "node:${NODE_BIN}" \
  "npm:${NPM_BIN}" \
  "python3:${PYTHON_BIN}"; do
  if [[ -z "${requirement#*:}" ]]; then
    printf '[beta gate] BLOCKED: required tool is missing: %s\n' \
      "${requirement%%:*}" >&2
    exit 1
  fi
done
PATH="$(dirname "${NODE_BIN}"):$(dirname "${NPM_BIN}"):/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  printf '%s\n' \
    '[beta gate] BLOCKED: Xcode Command Line Tools with swiftc are required.' >&2
  exit 1
fi

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
if [[ "${TMP_BASE}" != /* || ! -d "${TMP_BASE}" || ! -w "${TMP_BASE}" ]]; then
  TMP_BASE="/tmp"
fi
TEMPORARY_ROOT="$(/usr/bin/mktemp -d "${TMP_BASE}/whoami-beta-gate.XXXXXX")"
cleanup() {
  local status=$?
  case "${TEMPORARY_ROOT}" in
    "${TMP_BASE}"/whoami-beta-gate.??????)
      /bin/rm -rf -- "${TEMPORARY_ROOT}"
      ;;
    *)
      printf '[beta gate] Refusing unsafe cleanup path: %s\n' \
        "${TEMPORARY_ROOT}" >&2
      status=1
      ;;
  esac
  return "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

run_gate() {
  local label="$1"
  shift
  printf '[beta gate] START: %s\n' "${label}"
  if "$@"; then
    printf '[beta gate] PASS:  %s\n' "${label}"
  else
    local status=$?
    printf '[beta gate] FAIL:  %s (exit %s)\n' \
      "${label}" "${status}" >&2
    exit "${status}"
  fi
}

javascript_typecheck() {
  local source
  while IFS= read -r source; do
    "${NODE_BIN}" --check "${PRODUCT_ROOT}/${source}" >/dev/null
  done < <(
    cd "${PRODUCT_ROOT}"
    /usr/bin/find apps plugins tests website \
      -type d \( -name node_modules -o -name dist -o -name .next \) -prune \
      -o -type f \( -name '*.js' -o -name '*.mjs' \) -print \
      | LC_ALL=C /usr/bin/sort
  )
}

python_typecheck() {
  PYTHONPYCACHEPREFIX="${TEMPORARY_ROOT}/pycache" \
    "${PYTHON_BIN}" -m py_compile \
      "${PRODUCT_ROOT}/plugins/personal-model-context/scripts/context_hook.py" \
      "${PRODUCT_ROOT}/tests/fixtures/fake-persome-mcp.py"
}

install_card_dependencies() {
  cd "${PRODUCT_ROOT}/apps/personal-card"
  npm_config_cache="${TEMPORARY_ROOT}/npm-cache" \
    "${NPM_BIN}" ci --ignore-scripts --no-audit --no-fund
}

content_and_isolation_tests() {
  cd "${PRODUCT_ROOT}/apps/personal-card"
  "${NODE_BIN}" --test \
    tests/evals/*.test.mjs \
    tests/connectors/*.test.mjs \
    tests/isolation/*.test.mjs
}

card_tests() {
  cd "${PRODUCT_ROOT}/apps/personal-card"
  "${NPM_BIN}" test
}

browser_tests() {
  cd "${PRODUCT_ROOT}/apps/personal-card"
  "${NPM_BIN}" run test:browser
  "${NPM_BIN}" run test:production-browser
  "${NPM_BIN}" run test:production-no-demo
}

swift_typecheck() {
  local sdk_path swiftc architecture
  sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
  swiftc="$(/usr/bin/xcrun --sdk macosx --find swiftc)"
  architecture="$(/usr/bin/uname -m)"
  "${swiftc}" \
    -typecheck \
    -sdk "${sdk_path}" \
    -target "${architecture}-apple-macos13.0" \
    -framework Cocoa \
    -framework SwiftUI \
    "${PRODUCT_ROOT}/apps/personal-card/macos/WhoAmIApp.swift" \
    "${PRODUCT_ROOT}/apps/personal-card/macos/WhoAmINativeUI.swift" \
    "${PRODUCT_ROOT}/apps/personal-card/macos/NativeLifecycle.swift"
}

native_launcher() {
  local version output app
  version="$(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")"
  output="${TEMPORARY_ROOT}/native-launcher"
  /bin/bash \
    "${PRODUCT_ROOT}/apps/personal-card/macos/build-native-launcher.sh" \
    --bootstrap \
    --product-version "${version}" \
    --output-directory "${output}"
  app="${output}/Who Am I.app"
  /usr/bin/codesign --verify --strict "${app}"
  /usr/bin/lipo "${app}/Contents/MacOS/WhoAmI" \
    -verify_arch arm64 x86_64
  [[ "$(/usr/bin/plutil -extract WhoAmIBootstrapInstall raw -o - \
    "${app}/Contents/Info.plist")" == "true" ]]
}

website_checks() {
  cd "${PRODUCT_ROOT}/website"
  npm_config_cache="${TEMPORARY_ROOT}/npm-cache" \
    "${NPM_BIN}" ci --ignore-scripts --no-audit --no-fund
  "${NPM_BIN}" run typecheck
  "${NPM_BIN}" test
  "${NPM_BIN}" run lint
}

package_checks() {
  cd "${PRODUCT_ROOT}"
  /bin/bash tests/foundation.sh
  "${NODE_BIN}" --test apps/personal-card/tests/release/*.test.mjs
  /bin/bash scripts/release-readiness.sh --check
  /bin/bash scripts/validate-runtime-lock.sh
  /bin/bash scripts/build-self-contained-package.sh --help >/dev/null
}

run_gate "JavaScript syntax" javascript_typecheck
run_gate "Python syntax" python_typecheck
run_gate "Personal Card locked dependencies" install_card_dependencies
run_gate "28 content evals and Connector isolation" content_and_isolation_tests
run_gate "Personal Card full test suite" card_tests
run_gate "browser and production no-demo flows" browser_tests
run_gate "Swift typecheck" swift_typecheck
run_gate "universal native launcher" native_launcher
run_gate "website typecheck, build, rendered HTML, and lint" website_checks
run_gate "package source, foundation, and Runtime lock" package_checks

printf '%s\n' '[beta gate] COMPLETE: all release-blocking checks passed.'
