#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

GITLEAKS_VERSION="8.30.1"
SCAN_REPOSITORY=0
RUN_SELF_TEST=0
SCAN_DIRECTORIES=()
TEMPORARY_ROOT=""

usage() {
  cat <<'EOF'
Usage: bash scripts/scan-secrets.sh option [option ...]

Options:
  --repository      Scan the current source tree and its complete Git history.
  --directory PATH  Scan an extracted release directory. May be repeated.
  --self-test       Prove the scanner rejects a generated high-confidence canary.
  -h, --help        Show this help.

The script downloads a pinned official Gitleaks binary and verifies its
SHA-256 before use. Findings are fully redacted.
EOF
}

fail() {
  printf 'Secret-scan error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local cleanup_status=$?
  if [[ -n "${TEMPORARY_ROOT:-}" ]]; then
    runtime_temporary_root_remove \
      "${TEMPORARY_ROOT}" "product-secret-scan" || true
  fi
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository)
      SCAN_REPOSITORY=1
      shift
      ;;
    --directory)
      [[ $# -ge 2 ]] || fail "--directory requires a path"
      SCAN_DIRECTORIES+=("$2")
      shift 2
      ;;
    --self-test)
      RUN_SELF_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${SCAN_REPOSITORY}" -eq 0 \
  && "${RUN_SELF_TEST}" -eq 0 \
  && "${#SCAN_DIRECTORIES[@]}" -eq 0 ]]; then
  fail "select at least one scan target or --self-test"
fi

TEMPORARY_ROOT="$(runtime_temporary_root_create "product-secret-scan")"
platform=""
expected_digest=""
case "$(/usr/bin/uname -s):$(/usr/bin/uname -m)" in
  Darwin:arm64)
    platform="darwin_arm64"
    expected_digest="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
    ;;
  Darwin:x86_64)
    platform="darwin_x64"
    expected_digest="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
    ;;
  Linux:x86_64)
    platform="linux_x64"
    expected_digest="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
    ;;
  *)
    fail "unsupported scanner platform: $(/usr/bin/uname -s) $(/usr/bin/uname -m)"
    ;;
esac

archive_name="gitleaks_${GITLEAKS_VERSION}_${platform}.tar.gz"
archive_path="${TEMPORARY_ROOT}/${archive_name}"
/usr/bin/curl \
  --proto '=https' \
  --tlsv1.2 \
  --fail \
  --retry 3 \
  --retry-delay 2 \
  --retry-all-errors \
  --silent \
  --show-error \
  --location \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${archive_name}" \
  --output "${archive_path}"
actual_digest="$(
  /usr/bin/shasum -a 256 "${archive_path}" | /usr/bin/awk '{print $1}'
)"
[[ "${actual_digest}" == "${expected_digest}" ]] \
  || fail "Gitleaks archive digest mismatch"
/usr/bin/tar -xzf "${archive_path}" -C "${TEMPORARY_ROOT}"
gitleaks="${TEMPORARY_ROOT}/gitleaks"
if [[ ! -x "${gitleaks}" || ! -f "${gitleaks}" \
  || -L "${gitleaks}" || ! -O "${gitleaks}" ]]; then
  fail "verified Gitleaks archive had an unsafe layout"
fi
runtime_path_reject_shared_write "${gitleaks}"
[[ "$("${gitleaks}" version)" == "${GITLEAKS_VERSION}" ]] \
  || fail "Gitleaks binary reported an unexpected version"

gitleaks_flags=(
  --config "${PRODUCT_ROOT}/.gitleaks.toml"
  --no-banner
  --no-color
  --redact=100
  --log-level error
  --timeout 300
)

if [[ "${RUN_SELF_TEST}" -eq 1 ]]; then
  canary_directory="${TEMPORARY_ROOT}/canary"
  /bin/mkdir "${canary_directory}"
  /bin/chmod 0700 "${canary_directory}"
  # Assemble the fake value at runtime so the scanner source never contains a
  # complete token-shaped string.
  printf 'github_token = "%s%s"\n' \
    'ghp_' \
    '7VjK9mQ2xR8cN4pL6sT1wY3zA5bD0eF2gH8jK' \
    > "${canary_directory}/synthetic.txt"
  if "${gitleaks}" dir "${gitleaks_flags[@]}" \
    "${canary_directory}" >/dev/null 2>&1; then
    fail "Gitleaks self-test did not reject the generated canary"
  fi
  printf 'Secret scanner self-test: detected generated canary\n'
fi

if [[ "${SCAN_REPOSITORY}" -eq 1 ]]; then
  (
    cd "${PRODUCT_ROOT}"
    "${gitleaks}" dir "${gitleaks_flags[@]}" .
  )
  if /usr/bin/git -C "${PRODUCT_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
    (
      cd "${PRODUCT_ROOT}"
      "${gitleaks}" git "${gitleaks_flags[@]}" .
    )
  else
    printf 'Secret-scan note: repository has no commit history yet.\n'
  fi
  printf 'Secret scan: source tree and available history clean\n'
fi

if [[ "${#SCAN_DIRECTORIES[@]}" -gt 0 ]]; then
  for scan_directory in "${SCAN_DIRECTORIES[@]}"; do
    if [[ ! -d "${scan_directory}" || -L "${scan_directory}" ]]; then
      fail "scan directory is missing or unsafe: ${scan_directory}"
    fi
    scan_directory="$(cd "${scan_directory}" && pwd -P)"
    (
      cd "${scan_directory}"
      "${gitleaks}" dir "${gitleaks_flags[@]}" .
    )
    printf 'Secret scan: extracted directory clean: %s\n' "${scan_directory}"
  done
fi
