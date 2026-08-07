#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/product-version.sh
source "${PRODUCT_ROOT}/scripts/lib/product-version.sh"
# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

REQUIRE_GO=0
MODE_COUNT=0
REPOSITORY=""
REPOSITORY_COUNT=0
TEMPORARY_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/pilot-readiness.sh --check
  bash scripts/pilot-readiness.sh --require-pilot-go --repository OWNER/REPO

--check validates the explicit local pilot decision without contacting GitHub.
--require-pilot-go additionally requires complete post-publication evidence and
verifies the immutable GitHub Release, its exact four assets, checksums,
metadata, and GitHub release attestations. Passing this gate authorizes only
the first five-user pilot, never the later 20- or 75-user waves.
EOF
}

fail() {
  printf 'Pilot-readiness error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local cleanup_status=$?
  if [[ -n "${TEMPORARY_ROOT:-}" ]]; then
    runtime_temporary_root_remove \
      "${TEMPORARY_ROOT}" "product-pilot-gate" || true
  fi
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      REQUIRE_GO=0
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --require-pilot-go)
      REQUIRE_GO=1
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --repository)
      [[ $# -ge 2 ]] || fail "--repository requires a value"
      REPOSITORY="$2"
      REPOSITORY_COUNT=$((REPOSITORY_COUNT + 1))
      shift 2
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

[[ "${MODE_COUNT}" -le 1 ]] || fail "choose only one pilot-readiness mode"
[[ "${REPOSITORY_COUNT}" -le 1 ]] || fail "repository may be supplied only once"
if [[ -n "${REPOSITORY}" ]] \
  && [[ ! "${REPOSITORY}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*/[A-Za-z0-9_.-]+$ \
    || "${REPOSITORY}" == *".."* ]]; then
  fail "repository must be an explicit OWNER/REPOSITORY name"
fi
if [[ "${REQUIRE_GO}" -eq 1 && -z "${REPOSITORY}" ]]; then
  fail "--require-pilot-go requires --repository"
fi

read_control_line() {
  local label="$1"
  local path="$2"
  local value

  if [[ ! -f "${path}" || -L "${path}" \
    || "$(wc -l < "${path}" | tr -d '[:space:]')" != "1" ]]; then
    fail "${label} must be one safe newline-terminated line"
  fi
  IFS= read -r value < "${path}"
  printf '%s\n' "${value}"
}

release_status="$(read_control_line RELEASE_STATUS "${PRODUCT_ROOT}/RELEASE_STATUS")"
pilot_status="$(read_control_line PILOT_STATUS "${PRODUCT_ROOT}/PILOT_STATUS")"
version="$(read_control_line VERSION "${PRODUCT_ROOT}/VERSION")"
case "${release_status}" in HOLD|GO) ;; *) fail "RELEASE_STATUS must be HOLD or GO" ;; esac
case "${pilot_status}" in HOLD|GO) ;; *) fail "PILOT_STATUS must be HOLD or GO" ;; esac
product_version_validate "${version}" \
  || fail "VERSION is not a supported product release version"
tag="v${version}"

runbook="${PRODUCT_ROOT}/docs/beta-runbook.md"
checklist="${PRODUCT_ROOT}/docs/release-checklist.md"
[[ -f "${runbook}" && ! -L "${runbook}" ]] || fail "beta runbook is missing or unsafe"
[[ -f "${checklist}" && ! -L "${checklist}" ]] \
  || fail "release checklist is missing or unsafe"
[[ "$(LC_ALL=C grep -Fxc '<!-- beta-runbook-schema:1 -->' "${runbook}" || true)" == "1" ]] \
  || fail "beta runbook schema marker is missing or duplicated"
[[ "$(LC_ALL=C grep -Ec '^<!-- pilot-decision:v1 ' "${runbook}" || true)" == "1" ]] \
  || fail "pilot decision marker is missing or duplicated"

printf 'Pilot invitation decision: %s (%s)\n' "${pilot_status}" "${tag}"
if [[ "${REQUIRE_GO}" -eq 0 ]]; then
  exit 0
fi
[[ "${release_status}" == "GO" ]] || fail "release publication decision is not GO"
[[ "${pilot_status}" == "GO" ]] || fail "pilot invitations are blocked"

schema_marker='<!-- release-checklist-schema:1 required-items:77 -->'
[[ "$(LC_ALL=C grep -Fxc "${schema_marker}" "${checklist}" || true)" == "1" ]] \
  || fail "release checklist schema marker is missing or duplicated"
[[ "$(LC_ALL=C grep -Ec '^- \[[ xX]\]' "${checklist}" || true)" == "77" ]] \
  || fail "release checklist must contain exactly 77 items"
[[ "$(LC_ALL=C grep -Eic 'evidence[^:]*:' "${checklist}" || true)" == "77" ]] \
  || fail "release checklist must contain exactly 77 evidence fields"

item_index=1
while [[ "${item_index}" -le 77 ]]; do
  checklist_id="$(printf 'RC-%03d' "${item_index}")"
  item_block="$(
    /usr/bin/awk -v target="[${checklist_id}]" '
      /^- \[[ xX]\] \[RC-[0-9][0-9][0-9]\] / {
        if (capture) exit
        capture = index($0, target) > 0
      }
      capture { print }
    ' "${checklist}"
  )"
  [[ "$(LC_ALL=C grep -Ec "^- \\[[xX]\\] \\[${checklist_id}\\] " \
    <<<"${item_block}" || true)" == "1" ]] \
    || fail "post-publication checklist item is not checked: ${checklist_id}"
  if LC_ALL=C grep -Eiq 'TBD|TODO|TBC|___|generated by the .*workflow' \
    <<<"${item_block}" \
    || ! LC_ALL=C grep -Eiq \
      'evidence[^:]*:[[:space:]]*[^_[:space:]]' <<<"${item_block}"; then
    fail "post-publication checklist evidence is incomplete: ${checklist_id}"
  fi
  item_index=$((item_index + 1))
done

decision_line="$(LC_ALL=C grep -E '^<!-- pilot-decision:v1 ' "${runbook}")"
decision_pattern='^<!-- pilot-decision:v1 status=GO wave=5 version=([^ ]+) tag=([^ ]+) commit=([0-9a-f]{40}) owner=([^ ]+) approved-at=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) -->$'
[[ "${decision_line}" =~ ${decision_pattern} ]] \
  || fail "pilot decision must record GO, wave 5, version, tag, commit, owner, and UTC time"
decision_version="${BASH_REMATCH[1]}"
decision_tag="${BASH_REMATCH[2]}"
decision_commit="${BASH_REMATCH[3]}"
decision_owner="${BASH_REMATCH[4]}"
[[ "${decision_version}" == "${version}" && "${decision_tag}" == "${tag}" ]] \
  || fail "pilot decision does not match VERSION and tag"
[[ "${decision_owner}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:@/-]*$ ]] \
  || fail "pilot decision owner is unsafe"

command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required for the live pilot gate"
[[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN is required for the live pilot gate"
immutable="$(
  gh api \
    --header "X-GitHub-Api-Version: 2026-03-10" \
    "/repos/${REPOSITORY}/releases/tags/${tag}" \
    --jq '.immutable'
)"
[[ "${immutable}" == "true" ]] || fail "published release is not immutable"

actual_assets="$(
  gh api \
    --header "X-GitHub-Api-Version: 2026-03-10" \
    "/repos/${REPOSITORY}/releases/tags/${tag}" \
    --jq '.assets[].name' \
    | LC_ALL=C sort
)"
repository_name="${REPOSITORY#*/}"
bundle_name="${repository_name}-${version}.tar.gz"
expected_assets="$(
  printf '%s\n' \
    "${bundle_name}" \
    RELEASE-METADATA.txt \
    RELEASE-NOTES.md \
    SHA256SUMS \
    | LC_ALL=C sort
)"
[[ "${actual_assets}" == "${expected_assets}" ]] \
  || fail "published release does not contain the exact four approved assets"

TEMPORARY_ROOT="$(runtime_temporary_root_create "product-pilot-gate")"
(
  cd "${TEMPORARY_ROOT}"
  gh release download "${tag}" \
    --repo "${REPOSITORY}" \
    --pattern "${bundle_name}" \
    --pattern "RELEASE-METADATA.txt" \
    --pattern "RELEASE-NOTES.md" \
    --pattern "SHA256SUMS"
  [[ "$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" == "4" ]]
  gh release verify "${tag}" --repo "${REPOSITORY}"
  for asset_name in \
    "${bundle_name}" RELEASE-METADATA.txt RELEASE-NOTES.md SHA256SUMS; do
    gh release verify-asset "${tag}" "${asset_name}" --repo "${REPOSITORY}"
  done
  /usr/bin/shasum -a 256 --check SHA256SUMS
  /usr/bin/grep -Fxq "repository=${REPOSITORY}" RELEASE-METADATA.txt
  /usr/bin/grep -Fxq "tag=${tag}" RELEASE-METADATA.txt
  /usr/bin/grep -Fxq "commit=${decision_commit}" RELEASE-METADATA.txt
  /usr/bin/grep -Fxq "version=${version}" RELEASE-METADATA.txt
  /usr/bin/grep -Fxq "release_status=GO" RELEASE-METADATA.txt
  /usr/bin/grep -Fxq "pilot_status=HOLD" RELEASE-METADATA.txt
)

printf 'Pilot invitation gate: GO for exactly 5 users\n'
