#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/product-version.sh
source "${PRODUCT_ROOT}/scripts/lib/product-version.sh"

REQUIRE_GO=0
MODE_COUNT=0

usage() {
  cat <<'EOF'
Usage: bash scripts/release-readiness.sh [option]

Validate the repository's explicit release decision.

Options:
  --check       Validate HOLD or GO and print the current decision. Default.
  --require-go  Fail unless the reviewed decision is exactly GO.
  -h, --help    Show this help.

Changing RELEASE_STATUS to GO is a deliberate release-owner action. It does not
replace the evidence required by docs/release-checklist.md.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      REQUIRE_GO=0
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --require-go)
      REQUIRE_GO=1
      MODE_COUNT=$((MODE_COUNT + 1))
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

if [[ "${MODE_COUNT}" -gt 1 ]]; then
  printf 'Choose only one release-readiness mode.\n' >&2
  exit 2
fi

status_path="${PRODUCT_ROOT}/RELEASE_STATUS"
pilot_status_path="${PRODUCT_ROOT}/PILOT_STATUS"
version_path="${PRODUCT_ROOT}/VERSION"

for required_path in "${status_path}" "${pilot_status_path}" "${version_path}"; do
  if [[ ! -f "${required_path}" || -L "${required_path}" ]]; then
    printf 'Release control file is missing or unsafe: %s\n' \
      "${required_path}" >&2
    exit 1
  fi
done

if [[ "$(wc -l < "${status_path}" | tr -d '[:space:]')" != "1" ]]; then
  printf 'RELEASE_STATUS must contain exactly one newline-terminated line.\n' >&2
  exit 1
fi

IFS= read -r release_status < "${status_path}"
case "${release_status}" in
  HOLD|GO) ;;
  *)
    printf 'RELEASE_STATUS must be exactly HOLD or GO.\n' >&2
    exit 1
    ;;
esac

if [[ "$(wc -l < "${pilot_status_path}" | tr -d '[:space:]')" != "1" ]]; then
  printf 'PILOT_STATUS must contain exactly one newline-terminated line.\n' >&2
  exit 1
fi
IFS= read -r pilot_status < "${pilot_status_path}"
case "${pilot_status}" in
  HOLD|GO) ;;
  *)
    printf 'PILOT_STATUS must be exactly HOLD or GO.\n' >&2
    exit 1
    ;;
esac

if [[ "$(wc -l < "${version_path}" | tr -d '[:space:]')" != "1" ]]; then
  printf 'VERSION must contain exactly one newline-terminated line.\n' >&2
  exit 1
fi
IFS= read -r version < "${version_path}"
if ! product_version_validate "${version}"; then
  printf 'VERSION is not a supported product release version: %s\n' \
    "${version}" >&2
  exit 1
fi

release_notes="${PRODUCT_ROOT}/docs/release-notes/v${version}.md"
if [[ ! -f "${release_notes}" || -L "${release_notes}" ]]; then
  printf 'Version-controlled release notes are missing or unsafe: %s\n' \
    "${release_notes}" >&2
  exit 1
fi

printf 'Release decision: %s (v%s)\n' "${release_status}" "${version}"

if [[ "${REQUIRE_GO}" -eq 1 && "${release_status}" != "GO" ]]; then
  printf '%s\n' \
    'Release publication is blocked.' \
    'Complete docs/release-checklist.md and obtain the release owner decision' \
    'before changing RELEASE_STATUS to GO in a reviewed commit.' >&2
  exit 3
fi
if [[ "${REQUIRE_GO}" -eq 1 && "${pilot_status}" != "HOLD" ]]; then
  printf '%s\n' \
    'Release publication requires PILOT_STATUS=HOLD.' \
    'Tester invitations are a separate post-publication decision.' >&2
  exit 3
fi

require_complete_file() {
  local label="$1"
  local path="$2"
  local unresolved_pattern="$3"

  if [[ ! -f "${path}" || -L "${path}" || ! -s "${path}" ]]; then
    printf '%s is missing, empty, or unsafe: %s\n' "${label}" "${path}" >&2
    exit 1
  fi
  if LC_ALL=C grep -Eiq "${unresolved_pattern}" "${path}"; then
    printf '%s still contains an unresolved release marker: %s\n' \
      "${label}" "${path}" >&2
    exit 1
  fi
}

validate_release_checklist_shape() {
  local checklist_path="$1"
  local expected_items="77"
  local schema_marker
  local schema_count item_count evidence_count item_index checklist_id id_count

  schema_marker="<!-- release-checklist-schema:1 required-items:${expected_items} -->"
  schema_count="$(
    LC_ALL=C grep -Fxc "${schema_marker}" "${checklist_path}" || true
  )"
  item_count="$(
    LC_ALL=C grep -Ec '^- \[[ xX]\]' "${checklist_path}" || true
  )"
  evidence_count="$(
    LC_ALL=C grep -Eic 'evidence[^:]*:' "${checklist_path}" || true
  )"
  if [[ "${schema_count}" != "1" || "${item_count}" != "${expected_items}" \
    || "${evidence_count}" != "${expected_items}" ]]; then
    printf '%s\n' \
      "Release checklist schema is incomplete or changed without review." \
      "Expected schema 1 with ${expected_items} items and evidence fields;" \
      "found schema markers=${schema_count}, items=${item_count}," \
      "evidence fields=${evidence_count}." >&2
    exit 1
  fi

  item_index=1
  while [[ "${item_index}" -le "${expected_items}" ]]; do
    checklist_id="$(printf 'RC-%03d' "${item_index}")"
    id_count="$(
      LC_ALL=C grep -Ec \
        "^- \\[[ xX]\\] \\[${checklist_id}\\] " "${checklist_path}" || true
    )"
    if [[ "${id_count}" != "1" ]]; then
      printf 'Release checklist ID must appear exactly once: %s\n' \
        "${checklist_id}" >&2
      exit 1
    fi
    item_index=$((item_index + 1))
  done
}

release_checklist_item_block() {
  local checklist_path="$1"
  local checklist_id="$2"

  /usr/bin/awk -v target="[${checklist_id}]" '
    /^- \[[ xX]\] \[RC-[0-9][0-9][0-9]\] / {
      if (capture) {
        exit
      }
      capture = index($0, target) > 0
    }
    capture {
      print
    }
  ' "${checklist_path}"
}

validate_prepublish_checklist() {
  local checklist_path="$1"
  local item_index checklist_id item_block

  item_index=1
  while [[ "${item_index}" -le 77 ]]; do
    case "${item_index}" in
      8|28|29|30|31|62|63)
        item_index=$((item_index + 1))
        continue
        ;;
    esac

    checklist_id="$(printf 'RC-%03d' "${item_index}")"
    item_block="$(
      release_checklist_item_block "${checklist_path}" "${checklist_id}"
    )"
    if [[ ! "${item_block}" =~ ^-\ \[[xX]\]\ \[${checklist_id}\]\  ]]; then
      printf 'Pre-publication checklist item is not checked: %s\n' \
        "${checklist_id}" >&2
      exit 1
    fi
    if LC_ALL=C grep -Eiq 'TBD|TODO|TBC|___' <<<"${item_block}" \
      || ! LC_ALL=C grep -Eiq \
        'evidence[^:]*:[[:space:]]*[^_[:space:]]' <<<"${item_block}"; then
      printf 'Pre-publication checklist evidence is incomplete: %s\n' \
        "${checklist_id}" >&2
      exit 1
    fi
    item_index=$((item_index + 1))
  done
}

validate_release_decision() {
  local checklist_path="$1"
  local expected_version="$2"
  local marker_count marker_line decision_pattern
  local decision_version decision_commit decision_owner decision_time
  local expected_commit="${RELEASE_COMMIT:-${GITHUB_SHA:-}}"
  local git_top=""

  marker_count="$(
    LC_ALL=C grep -Ec '^<!-- release-decision:v1 ' "${checklist_path}" || true
  )"
  [[ "${marker_count}" == "1" ]] \
    || {
      printf 'Release decision marker is missing or duplicated.\n' >&2
      exit 1
    }
  marker_line="$(
    LC_ALL=C grep -E '^<!-- release-decision:v1 ' "${checklist_path}"
  )"
  decision_pattern='^<!-- release-decision:v1 status=GO version=([^ ]+) commit=([0-9a-f]{40}) owner=([^ ]+) approved-at=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) -->$'
  if [[ ! "${marker_line}" =~ ${decision_pattern} ]]; then
    printf 'Release decision marker must record GO, commit, owner, and UTC time.\n' \
      >&2
    exit 1
  fi
  decision_version="${BASH_REMATCH[1]}"
  decision_commit="${BASH_REMATCH[2]}"
  decision_owner="${BASH_REMATCH[3]}"
  decision_time="${BASH_REMATCH[4]}"
  [[ "${decision_version}" == "${expected_version}" ]] \
    || {
      printf 'Release decision version does not match VERSION.\n' >&2
      exit 1
    }
  if [[ ! "${decision_owner}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:@/-]*$ ]]; then
    printf 'Release decision owner is unsafe.\n' >&2
    exit 1
  fi
  [[ -n "${decision_time}" ]] || exit 1

  if [[ -z "${expected_commit}" ]]; then
    git_top="$(
      /usr/bin/git -C "${PRODUCT_ROOT}" rev-parse --show-toplevel 2>/dev/null \
        || true
    )"
    if [[ "${git_top}" == "${PRODUCT_ROOT}" ]]; then
      expected_commit="$(
        /usr/bin/git -C "${PRODUCT_ROOT}" rev-parse --verify HEAD 2>/dev/null \
          || true
      )"
    fi
  fi
  if [[ -n "${expected_commit}" && "${decision_commit}" != "${expected_commit}" ]]; then
    printf 'Release decision commit does not match the release commit.\n' >&2
    exit 1
  fi
}

validate_product_intake_shape() {
  local intake_path="$1"
  local schema_count workflow_ids workflow_count
  local anchor
  local anchors

  schema_count="$(
    LC_ALL=C grep -Fxc \
      '<!-- product-intake-schema:1 -->' "${intake_path}" || true
  )"
  [[ "${schema_count}" == "1" ]] \
    || {
      printf 'Product intake schema marker is missing or duplicated.\n' >&2
      exit 1
    }

  anchors=(
    '## 1. Product definition'
    '## 2. Workflow inventory'
    '## 3. Existing-library inventory'
    '## 4. Classification decision'
    '## 5. Data, permissions and external systems'
    '## 6. Distribution decisions'
    '## Intake exit gate'
    'Product name and one-sentence promise'
    'Primary beta user'
    'Single golden path: trigger → steps → visible result'
    'Definition of a successful first session'
    'Explicit beta exclusions'
    'Product source repository name and GitHub organization'
    'Product source license and redistribution policy'
    'Beta owner and release approver'
    'Support and feedback route'
    'Public or private GitHub repository'
    'How the 100 testers receive access'
    'Code signing/notarization requirement for this beta'
    'Support hours and incident owner'
    'Rollout stop authority'
    'Pilot observation window'
    'Expansion observation window'
    'General-wave observation window'
    'Minimum successful install rate per wave'
    'Minimum golden-path success rate per wave'
    'Maximum total and repeated failure rate per wave'
    'Threshold denominator, measurement source and missing-response policy'
    'Threshold approver and emergency stop owner'
  )
  for anchor in "${anchors[@]}"; do
    if ! LC_ALL=C grep -Fq "${anchor}" "${intake_path}"; then
      printf 'Product intake is missing required field or section: %s\n' \
        "${anchor}" >&2
      exit 1
    fi
  done

  workflow_ids="$(
    LC_ALL=C grep -Eo 'WF-[0-9]{3}' "${intake_path}" || true
  )"
  workflow_count="$(
    printf '%s\n' "${workflow_ids}" | sed '/^$/d' | sort -u | wc -l \
      | tr -d ' '
  )"
  if [[ "${workflow_count}" -lt 1 ]]; then
    printf 'Product intake must retain at least one stable WF-NNN workflow ID.\n' \
      >&2
    exit 1
  fi
}

validate_beta_runbook_shape() {
  local runbook_path="$1"
  local schema_count anchor
  local anchors

  schema_count="$(
    LC_ALL=C grep -Fxc \
      '<!-- beta-runbook-schema:1 -->' "${runbook_path}" || true
  )"
  [[ "${schema_count}" == "1" ]] \
    || {
      printf 'Beta runbook schema marker is missing or duplicated.\n' >&2
      exit 1
    }

  anchors=(
    '## Roles and records'
    '## Preflight: internal clean-Mac proof'
    '## Rollout waves'
    '### Wave 1 — pilot: 5 users'
    '### Wave 2 — expansion: 20 users'
    '### Wave 3 — general: 75 users'
    '## Stop conditions'
    '## Rollback procedure'
    '| Release owner |'
    '| Rollout owner |'
    '| Incident owner |'
    '| Runtime owner |'
    '| Product owner |'
    '| Privacy contact |'
    '| Support route |'
  )
  for anchor in "${anchors[@]}"; do
    if ! LC_ALL=C grep -Fq "${anchor}" "${runbook_path}"; then
      printf 'Beta runbook is missing required role or section: %s\n' \
        "${anchor}" >&2
      exit 1
    fi
  done

  if ! LC_ALL=C grep -Eq '^\| Pilot \|[^|]*\| 5 \|' "${runbook_path}" \
    || ! LC_ALL=C grep -Eq '^\| Expansion \|[^|]*\| 20 \|' "${runbook_path}" \
    || ! LC_ALL=C grep -Eq '^\| General \|[^|]*\| 75 \|' "${runbook_path}"; then
    printf 'Beta runbook must retain the 5/20/75 invitation ledger.\n' >&2
    exit 1
  fi
}

if [[ "${REQUIRE_GO}" -eq 1 ]]; then
  require_complete_file \
    "README" \
    "${PRODUCT_ROOT}/README.md" \
    'TBD|TODO|TBC|___|<owner>|<new-product-repository>'
  product_intake="${PRODUCT_ROOT}/docs/product-intake.md"
  validate_product_intake_shape "${product_intake}"
  require_complete_file \
    "Product intake" \
    "${product_intake}" \
    'TBD|TODO|TBC|___'
  beta_runbook="${PRODUCT_ROOT}/docs/beta-runbook.md"
  validate_beta_runbook_shape "${beta_runbook}"
  require_complete_file \
    "Beta runbook" \
    "${beta_runbook}" \
    'TBD|TODO|TBC|___'
  release_checklist="${PRODUCT_ROOT}/docs/release-checklist.md"
  validate_release_checklist_shape "${release_checklist}"
  validate_prepublish_checklist "${release_checklist}"
  validate_release_decision "${release_checklist}" "${version}"
  require_complete_file \
    "Release notes" \
    "${release_notes}" \
    'TBD|TODO|TBC|___|foundation candidate|not approved for the 100-user beta|No product workflow is promised|still pending product intake|are not yet decided'

  license_path=""
  for license_candidate in \
    "${PRODUCT_ROOT}/LICENSE" \
    "${PRODUCT_ROOT}/LICENSE.md" \
    "${PRODUCT_ROOT}/LICENSE.txt"; do
    if [[ -f "${license_candidate}" && ! -L "${license_candidate}" \
      && -s "${license_candidate}" ]]; then
      license_path="${license_candidate}"
      break
    fi
  done
  if [[ -z "${license_path}" ]]; then
    printf '%s\n' \
      'A reviewed, non-empty LICENSE, LICENSE.md, or LICENSE.txt is required.' \
      >&2
    exit 1
  fi

  printf 'Release evidence gate: complete\n'
fi
