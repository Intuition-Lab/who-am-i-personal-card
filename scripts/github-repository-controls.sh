#!/usr/bin/env bash
set -euo pipefail
umask 077

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_VERSION="2026-03-10"
BRANCH_RULESET_NAME="Protect product main"
TAG_RULESET_NAME="Protect product release tags"
RELEASE_ENVIRONMENT="github-release"

MODE="plan"
MODE_COUNT=0
REPOSITORY=""
REPOSITORY_COUNT=0
RELEASE_ACTOR=""
RELEASE_ACTOR_COUNT=0
RELEASE_REVIEWER=""
RELEASE_REVIEWER_COUNT=0
PRIVATE_ENTERPRISE=0
GH_COMMAND=""
LIVE_VISIBILITY=""
GITHUB_ACTIONS_APP_ID=""
RESOLVED_ACTOR_TYPE=""
RESOLVED_ACTOR_ID=""
RESOLVED_REVIEWER_TYPE=""
RESOLVED_REVIEWER_ID=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/github-repository-controls.sh MODE OPTIONS

Modes:
  --plan    Print the exact controls without contacting or changing GitHub.
  --apply   Create or update the reviewed controls on a new, untagged repo.
  --check   Verify the live repo without changing it.

Required options:
  --repository OWNER/REPOSITORY
  --release-actor user:LOGIN|team:SLUG
  --release-reviewer user:LOGIN|team:SLUG

Conditional option:
  --private-enterprise  Confirm a private repository has a GitHub plan that
                        supports required environment reviewers.

The release actor and reviewer must be different. Team slugs are resolved
inside the repository owner organization.

--apply is deliberately limited to initial setup: RELEASE_STATUS must be HOLD,
the default branch must be main, and the repository must have no v* tag or
GitHub Release. It enables immutable releases, protects main and v* tags, and
creates the github-release environment with a distinct required reviewer.
EOF
}

fail() {
  printf 'Repository-control error: %s\n' "$*" >&2
  exit 1
}

validate_repository() {
  local value="$1"
  if [[ ! "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*/[A-Za-z0-9_.-]+$ \
    || "${value}" == *".."* || "${value}" == */.* ]]; then
    fail "repository must be an explicit OWNER/REPOSITORY name"
  fi
}

validate_actor() {
  local label="$1"
  local value="$2"
  local kind="${value%%:*}"
  local name="${value#*:}"

  if [[ "${value}" != *:* || "${kind}" == "${name}" ]]; then
    fail "${label} must be user:LOGIN or team:SLUG"
  fi
  case "${kind}" in
    user|team) ;;
    *) fail "${label} must use the user or team type" ;;
  esac
  if [[ ! "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ \
    || "${name}" == *"--"* ]]; then
    fail "${label} contains an unsafe GitHub login or team slug"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      MODE="plan"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --apply)
      MODE="apply"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --check)
      MODE="check"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --repository)
      [[ $# -ge 2 ]] || fail "--repository requires a value"
      REPOSITORY="$2"
      REPOSITORY_COUNT=$((REPOSITORY_COUNT + 1))
      shift 2
      ;;
    --release-actor)
      [[ $# -ge 2 ]] || fail "--release-actor requires a value"
      RELEASE_ACTOR="$2"
      RELEASE_ACTOR_COUNT=$((RELEASE_ACTOR_COUNT + 1))
      shift 2
      ;;
    --release-reviewer)
      [[ $# -ge 2 ]] || fail "--release-reviewer requires a value"
      RELEASE_REVIEWER="$2"
      RELEASE_REVIEWER_COUNT=$((RELEASE_REVIEWER_COUNT + 1))
      shift 2
      ;;
    --private-enterprise)
      PRIVATE_ENTERPRISE=1
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

[[ "${MODE_COUNT}" -le 1 ]] || fail "choose only one mode"
[[ "${REPOSITORY_COUNT}" -eq 1 ]] \
  || fail "--repository must be provided exactly once"
[[ "${RELEASE_ACTOR_COUNT}" -eq 1 ]] \
  || fail "--release-actor must be provided exactly once"
[[ "${RELEASE_REVIEWER_COUNT}" -eq 1 ]] \
  || fail "--release-reviewer must be provided exactly once"
[[ -n "${REPOSITORY}" ]] || fail "--repository is required"
[[ -n "${RELEASE_ACTOR}" ]] || fail "--release-actor is required"
[[ -n "${RELEASE_REVIEWER}" ]] || fail "--release-reviewer is required"
validate_repository "${REPOSITORY}"
validate_actor "release actor" "${RELEASE_ACTOR}"
validate_actor "release reviewer" "${RELEASE_REVIEWER}"
if [[ "${RELEASE_ACTOR}" == "${RELEASE_REVIEWER}" ]]; then
  fail "release actor and release reviewer must be different"
fi

print_plan() {
  cat <<EOF
GitHub repository: ${REPOSITORY}
Release actor:      ${RELEASE_ACTOR}
Release reviewer:   ${RELEASE_REVIEWER}

Initial setup will:
  1. require RELEASE_STATUS=HOLD, default branch main, and no v* tag/release;
  2. keep Issues and GitHub Actions enabled;
  3. enable immutable GitHub Releases;
  4. protect main with pull requests, one approval, resolved conversations,
     stale-review dismissal, no deletion/force-push, and these exact checks:
       - repository checks
       - macOS prerequisites (arm64)
       - macOS prerequisites (x86_64)
       - macOS isolated install (arm64)
  5. allow only ${RELEASE_ACTOR} to create, update, or delete v* tags;
  6. gate the github-release environment on ${RELEASE_REVIEWER}, prevent
     self-review, and accept only v* tags;
  7. store the actor/reviewer specs as repository variables for the Release
     workflow's live recheck;
  8. read every API-visible control back and fail closed if it differs.

GitHub does not expose the environment administrator-bypass switch through
this REST setup flow. A repository administrator must disable that switch in
the UI and attach evidence before GO.

Private repository plan confirmed: ${PRIVATE_ENTERPRISE}

No GitHub request was made in --plan mode.
EOF
}

if [[ "${MODE}" == "plan" ]]; then
  print_plan
  exit 0
fi

if ! GH_COMMAND="$(command -v gh)"; then
  fail "GitHub CLI (gh) is required for --${MODE}"
fi

gh_api() {
  "${GH_COMMAND}" api \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: ${API_VERSION}" \
    "$@"
}

resolve_actor() {
  local specification="$1"
  local kind="${specification%%:*}"
  local name="${specification#*:}"
  local owner="${REPOSITORY%%/*}"
  local actor_type actor_id

  case "${kind}" in
    user)
      actor_type="User"
      actor_id="$(gh_api "/users/${name}" --jq '.id')"
      ;;
    team)
      actor_type="Team"
      actor_id="$(gh_api "/orgs/${owner}/teams/${name}" --jq '.id')"
      ;;
    *)
      fail "internal actor type error"
      ;;
  esac
  [[ "${actor_id}" =~ ^[1-9][0-9]*$ ]] \
    || fail "GitHub did not return a numeric ID for ${specification}"
  printf '%s %s\n' "${actor_type}" "${actor_id}"
}

require_live_repository() {
  local repository_state
  if ! repository_state="$(
    gh_api "/repos/${REPOSITORY}" \
      --jq '[.full_name, .default_branch, .archived, .disabled, .has_issues,
             .visibility] | @tsv'
  )"; then
    fail "cannot read ${REPOSITORY} with the current GitHub identity"
  fi

  IFS=$'\t' read -r \
    live_name live_default live_archived live_disabled live_issues LIVE_VISIBILITY \
    <<<"${repository_state}"
  [[ "${live_name}" == "${REPOSITORY}" ]] \
    || fail "GitHub resolved the repository as ${live_name}"
  [[ "${live_default}" == "main" ]] \
    || fail "default branch must be main, found ${live_default}"
  [[ "${live_archived}" == "false" ]] || fail "repository is archived"
  [[ "${live_disabled}" == "false" ]] || fail "repository is disabled"

  if [[ "${MODE}" == "check" && "${live_issues}" != "true" ]]; then
    fail "Issues are not enabled"
  fi

  if [[ "${LIVE_VISIBILITY}" == "private" && "${PRIVATE_ENTERPRISE}" -ne 1 ]]; then
    fail "private repositories require explicit --private-enterprise confirmation"
  fi

  if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
    if [[ "$(gh_api "/repos/${REPOSITORY}/actions/permissions" --jq '.enabled')" \
      != "true" ]]; then
      fail "GitHub Actions are not enabled"
    fi
  fi
}

read -r RESOLVED_ACTOR_TYPE RESOLVED_ACTOR_ID \
  <<<"$(resolve_actor "${RELEASE_ACTOR}")"
read -r RESOLVED_REVIEWER_TYPE RESOLVED_REVIEWER_ID \
  <<<"$(resolve_actor "${RELEASE_REVIEWER}")"
if [[ "${RESOLVED_ACTOR_TYPE}:${RESOLVED_ACTOR_ID}" \
  == "${RESOLVED_REVIEWER_TYPE}:${RESOLVED_REVIEWER_ID}" ]]; then
  fail "release actor and reviewer resolve to the same GitHub identity"
fi
require_live_repository

resolve_github_actions_app_id() {
  local check_name app_ids app_id_count expected_app_id=""
  local required_checks=(
    "repository checks"
    "macOS prerequisites (arm64)"
    "macOS prerequisites (x86_64)"
    "macOS isolated install (arm64)"
  )

  for check_name in "${required_checks[@]}"; do
    app_ids="$(
      gh_api --paginate \
        "/repos/${REPOSITORY}/commits/main/check-runs?per_page=100" \
        --jq ".check_runs[]
          | select(.name == \"${check_name}\" and .conclusion == \"success\")
          | .app.id"
    )"
    app_ids="$(
      printf '%s\n' "${app_ids}" | sed '/^$/d' | sort -u
    )"
    app_id_count="$(
      printf '%s\n' "${app_ids}" | sed '/^$/d' | wc -l | tr -d ' '
    )"
    [[ "${app_id_count}" == "1" ]] \
      || fail "could not resolve one successful app identity for check: ${check_name}"
    if [[ -z "${expected_app_id}" ]]; then
      expected_app_id="${app_ids}"
    elif [[ "${app_ids}" != "${expected_app_id}" ]]; then
      fail "required checks do not share one GitHub Actions app identity"
    fi
  done
  [[ "${expected_app_id}" =~ ^[1-9][0-9]*$ ]] \
    || fail "GitHub Actions app identity is not numeric"
  GITHUB_ACTIONS_APP_ID="${expected_app_id}"
}

resolve_github_actions_app_id

branch_ruleset_payload() {
  printf '%s\n' \
    '{' \
    "  \"name\": \"${BRANCH_RULESET_NAME}\"," \
    '  "target": "branch",' \
    '  "enforcement": "active",' \
    '  "bypass_actors": [],' \
    '  "conditions": {' \
    '    "ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}' \
    '  },' \
    '  "rules": [' \
    '    {"type": "deletion"},' \
    '    {"type": "non_fast_forward"},' \
    '    {' \
    '      "type": "pull_request",' \
    '      "parameters": {' \
    '        "allowed_merge_methods": ["merge", "squash", "rebase"],' \
    '        "dismiss_stale_reviews_on_push": true,' \
    '        "require_code_owner_review": false,' \
    '        "require_last_push_approval": false,' \
    '        "required_approving_review_count": 1,' \
    '        "required_review_thread_resolution": true' \
    '      }' \
    '    },' \
    '    {' \
    '      "type": "required_status_checks",' \
    '      "parameters": {' \
    '        "do_not_enforce_on_create": false,' \
    '        "strict_required_status_checks_policy": true,' \
    '        "required_status_checks": [' \
    "          {\"context\": \"repository checks\", \"integration_id\": ${GITHUB_ACTIONS_APP_ID}}," \
    "          {\"context\": \"macOS prerequisites (arm64)\", \"integration_id\": ${GITHUB_ACTIONS_APP_ID}}," \
    "          {\"context\": \"macOS prerequisites (x86_64)\", \"integration_id\": ${GITHUB_ACTIONS_APP_ID}}," \
    "          {\"context\": \"macOS isolated install (arm64)\", \"integration_id\": ${GITHUB_ACTIONS_APP_ID}}" \
    '        ]' \
    '      }' \
    '    }' \
    '  ]' \
    '}'
}

tag_ruleset_payload() {
  printf '%s\n' \
    '{' \
    "  \"name\": \"${TAG_RULESET_NAME}\"," \
    '  "target": "tag",' \
    '  "enforcement": "active",' \
    '  "bypass_actors": [' \
    '    {' \
    "      \"actor_id\": ${RESOLVED_ACTOR_ID}," \
    "      \"actor_type\": \"${RESOLVED_ACTOR_TYPE}\"," \
    '      "bypass_mode": "always"' \
    '    }' \
    '  ],' \
    '  "conditions": {' \
    '    "ref_name": {"include": ["refs/tags/v*"], "exclude": []}' \
    '  },' \
    '  "rules": [' \
    '    {"type": "creation"},' \
    '    {"type": "update"},' \
    '    {"type": "deletion"}' \
    '  ]' \
    '}'
}

environment_payload() {
  printf '%s\n' \
    '{' \
    '  "wait_timer": 0,' \
    '  "prevent_self_review": true,' \
    '  "reviewers": [' \
    '    {' \
    "      \"type\": \"${RESOLVED_REVIEWER_TYPE}\"," \
    "      \"id\": ${RESOLVED_REVIEWER_ID}" \
    '    }' \
    '  ],' \
    '  "deployment_branch_policy": {' \
    '    "protected_branches": false,' \
    '    "custom_branch_policies": true' \
    '  }' \
    '}'
}

find_ruleset_id() {
  local name="$1"
  local ids id_count
  ids="$(
    gh_api --paginate \
      "/repos/${REPOSITORY}/rulesets?includes_parents=false&per_page=100" \
      --jq ".[] | select(.name == \"${name}\") | .id"
  )"
  id_count="$(printf '%s\n' "${ids}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "${id_count}" -gt 1 ]]; then
    fail "more than one local ruleset is named ${name}"
  fi
  printf '%s\n' "${ids}"
}

upsert_ruleset() {
  local name="$1"
  local payload="$2"
  local ruleset_id
  ruleset_id="$(find_ruleset_id "${name}")"
  if [[ -n "${ruleset_id}" ]]; then
    printf '%s\n' "${payload}" \
      | gh_api --method PUT \
        "/repos/${REPOSITORY}/rulesets/${ruleset_id}" \
        --input - \
        --jq '.id' >/dev/null
    printf 'Updated ruleset: %s\n' "${name}"
  else
    printf '%s\n' "${payload}" \
      | gh_api --method POST \
        "/repos/${REPOSITORY}/rulesets" \
        --input - \
        --jq '.id' >/dev/null
    printf 'Created ruleset: %s\n' "${name}"
  fi
}

expect_true() {
  local description="$1"
  local endpoint="$2"
  local query="$3"
  local result
  if ! result="$(gh_api "${endpoint}" --jq "${query}")"; then
    fail "could not verify ${description}"
  fi
  if [[ "${result}" != "true" ]]; then
    fail "${description} does not match the reviewed configuration"
  fi
  printf 'ok - %s\n' "${description}"
}

verify_controls() {
  local branch_ruleset_id tag_ruleset_id expected_private_enterprise
  branch_ruleset_id="$(find_ruleset_id "${BRANCH_RULESET_NAME}")"
  tag_ruleset_id="$(find_ruleset_id "${TAG_RULESET_NAME}")"
  [[ "${branch_ruleset_id}" =~ ^[1-9][0-9]*$ ]] \
    || fail "branch ruleset is missing"
  [[ "${tag_ruleset_id}" =~ ^[1-9][0-9]*$ ]] \
    || fail "tag ruleset is missing"

  expect_true \
    "immutable releases" \
    "/repos/${REPOSITORY}/immutable-releases" \
    '.enabled == true'
  expect_true \
    "Issues enabled" \
    "/repos/${REPOSITORY}" \
    '.has_issues == true'
  expect_true \
    "main ruleset target and scope" \
    "/repos/${REPOSITORY}/rulesets/${branch_ruleset_id}" \
    '.target == "branch"
      and .enforcement == "active"
      and .conditions.ref_name.include == ["~DEFAULT_BRANCH"]
      and .conditions.ref_name.exclude == []
      and ((.bypass_actors // []) | length == 0)'
  expect_true \
    "main ruleset rule set" \
    "/repos/${REPOSITORY}/rulesets/${branch_ruleset_id}" \
    '([.rules[].type] | sort)
      == (["deletion", "non_fast_forward", "pull_request",
           "required_status_checks"] | sort)'
  expect_true \
    "pull-request review policy" \
    "/repos/${REPOSITORY}/rulesets/${branch_ruleset_id}" \
    'any(.rules[];
      .type == "pull_request"
      and .parameters.dismiss_stale_reviews_on_push == true
      and .parameters.require_code_owner_review == false
      and .parameters.require_last_push_approval == false
      and .parameters.required_approving_review_count == 1
      and .parameters.required_review_thread_resolution == true)'
  expect_true \
    "required CI checks" \
    "/repos/${REPOSITORY}/rulesets/${branch_ruleset_id}" \
    "([.rules[]
       | select(.type == \"required_status_checks\")
       | .parameters.required_status_checks[]
       | {context, integration_id}] | sort_by(.context))
      == ([{\"context\":\"repository checks\",
            \"integration_id\":${GITHUB_ACTIONS_APP_ID}},
           {\"context\":\"macOS prerequisites (arm64)\",
            \"integration_id\":${GITHUB_ACTIONS_APP_ID}},
           {\"context\":\"macOS prerequisites (x86_64)\",
            \"integration_id\":${GITHUB_ACTIONS_APP_ID}},
           {\"context\":\"macOS isolated install (arm64)\",
            \"integration_id\":${GITHUB_ACTIONS_APP_ID}}] | sort_by(.context))
      and any(.rules[];
        .type == \"required_status_checks\"
        and .parameters.do_not_enforce_on_create == false
        and .parameters.strict_required_status_checks_policy == true)"
  expect_true \
    "release-tag ruleset target and scope" \
    "/repos/${REPOSITORY}/rulesets/${tag_ruleset_id}" \
    '.target == "tag"
      and .enforcement == "active"
      and .conditions.ref_name.include == ["refs/tags/v*"]
      and .conditions.ref_name.exclude == []'
  expect_true \
    "release-tag restricted actor" \
    "/repos/${REPOSITORY}/rulesets/${tag_ruleset_id}" \
    "([.bypass_actors[]?
       | select(.actor_type == \"${RESOLVED_ACTOR_TYPE}\"
         and .actor_id == ${RESOLVED_ACTOR_ID}
         and .bypass_mode == \"always\")] | length) == 1
      and ((.bypass_actors // []) | length == 1)"
  expect_true \
    "release-tag mutation rules" \
    "/repos/${REPOSITORY}/rulesets/${tag_ruleset_id}" \
    '([.rules[].type] | sort) == (["creation", "deletion", "update"] | sort)'
  expect_true \
    "release environment reviewer" \
    "/repos/${REPOSITORY}/environments/${RELEASE_ENVIRONMENT}" \
    "([.protection_rules[]?
       | select(.type == \"required_reviewers\")] | length) == 1
      and any(.protection_rules[]?;
        .type == \"required_reviewers\"
        and .prevent_self_review == true
        and (.reviewers | length) == 1
        and .reviewers[0].type == \"${RESOLVED_REVIEWER_TYPE}\"
        and .reviewers[0].reviewer.id == ${RESOLVED_REVIEWER_ID})
      and .deployment_branch_policy.protected_branches == false
      and .deployment_branch_policy.custom_branch_policies == true"
  expect_true \
    "release environment v* tag policy" \
    "/repos/${REPOSITORY}/environments/${RELEASE_ENVIRONMENT}/deployment-branch-policies" \
    '.total_count == 1
      and (.branch_policies | length) == 1
      and .branch_policies[0].name == "v*"
      and .branch_policies[0].type == "tag"'

  expect_true \
    "release actor repository variable" \
    "/repos/${REPOSITORY}/actions/variables/RELEASE_ACTOR" \
    ".value == \"${RELEASE_ACTOR}\""
  expect_true \
    "release reviewer repository variable" \
    "/repos/${REPOSITORY}/actions/variables/RELEASE_REVIEWER" \
    ".value == \"${RELEASE_REVIEWER}\""
  expected_private_enterprise="false"
  if [[ "${PRIVATE_ENTERPRISE}" -eq 1 ]]; then
    expected_private_enterprise="true"
  fi
  expect_true \
    "private Enterprise repository variable" \
    "/repos/${REPOSITORY}/actions/variables/REPOSITORY_PRIVATE_ENTERPRISE" \
    ".value == \"${expected_private_enterprise}\""
}

preflight_existing_environment_policy() {
  local endpoint
  local policy_state
  endpoint="/repos/${REPOSITORY}/environments/${RELEASE_ENVIRONMENT}/deployment-branch-policies"
  if policy_state="$(
    gh_api "${endpoint}" \
      --jq '[.total_count,
        ([.branch_policies[]?
          | select(.name == "v*" and .type == "tag")] | length)] | @tsv' \
      2>&1
  )"; then
    IFS=$'\t' read -r existing_policy_count matching_policy_count \
      <<<"${policy_state}"
    if [[ "${existing_policy_count}" != "0" \
      && ( "${existing_policy_count}" != "1" \
        || "${matching_policy_count}" != "1" ) ]]; then
      fail "release environment contains an unreviewed deployment policy"
    fi
    return 0
  fi
  case "${policy_state}" in
    *"HTTP 404"*|*'"status":"404"'*|*'"status": "404"'*)
      return 0
      ;;
    *)
      fail "could not preflight the release environment deployment policies"
      ;;
  esac
}

if [[ "${MODE}" == "apply" ]]; then
  bash "${PRODUCT_ROOT}/scripts/release-readiness.sh" --check >/dev/null
  release_status="$(tr -d '[:space:]' < "${PRODUCT_ROOT}/RELEASE_STATUS")"
  [[ "${release_status}" == "HOLD" ]] \
    || fail "--apply requires RELEASE_STATUS=HOLD"

  existing_tags="$(
    gh_api --paginate "/repos/${REPOSITORY}/tags?per_page=100" \
      --jq '.[] | .name | select(startswith("v"))'
  )"
  [[ -z "${existing_tags}" ]] \
    || fail "--apply refuses a repository that already has a v* tag"
  existing_release_count="$(
    gh_api "/repos/${REPOSITORY}/releases?per_page=1" --jq 'length'
  )"
  [[ "${existing_release_count}" == "0" ]] \
    || fail "--apply refuses a repository that already has a GitHub Release"

  preflight_existing_environment_policy

  gh_api --method PATCH "/repos/${REPOSITORY}" \
    -F has_issues=true --silent
  gh_api --method PUT \
    "/repos/${REPOSITORY}/immutable-releases" --silent
  printf 'Enabled Issues and immutable releases.\n'

  upsert_ruleset \
    "${BRANCH_RULESET_NAME}" \
    "$(branch_ruleset_payload)"
  upsert_ruleset \
    "${TAG_RULESET_NAME}" \
    "$(tag_ruleset_payload)"

  environment_payload \
    | gh_api --method PUT \
      "/repos/${REPOSITORY}/environments/${RELEASE_ENVIRONMENT}" \
      --input - \
      --silent
  printf 'Configured environment: %s\n' "${RELEASE_ENVIRONMENT}"

  tag_policy_count="$(
    gh_api \
      "/repos/${REPOSITORY}/environments/${RELEASE_ENVIRONMENT}/deployment-branch-policies" \
      --jq '[.branch_policies[]?
        | select(.name == "v*" and .type == "tag")] | length'
  )"
  if [[ "${tag_policy_count}" == "0" ]]; then
    gh_api --method POST \
      "/repos/${REPOSITORY}/environments/${RELEASE_ENVIRONMENT}/deployment-branch-policies" \
      -f name='v*' \
      -f type='tag' \
      --silent
    printf 'Created environment deployment policy: tag v*\n'
  elif [[ "${tag_policy_count}" != "1" ]]; then
    fail "release environment has duplicate v* tag policies"
  fi

  "${GH_COMMAND}" variable set RELEASE_ACTOR \
    --repo "${REPOSITORY}" \
    --body "${RELEASE_ACTOR}"
  "${GH_COMMAND}" variable set RELEASE_REVIEWER \
    --repo "${REPOSITORY}" \
    --body "${RELEASE_REVIEWER}"
  private_enterprise_value="false"
  if [[ "${PRIVATE_ENTERPRISE}" -eq 1 ]]; then
    private_enterprise_value="true"
  fi
  "${GH_COMMAND}" variable set REPOSITORY_PRIVATE_ENTERPRISE \
    --repo "${REPOSITORY}" \
    --body "${private_enterprise_value}"
  printf 'Stored repository release-control variables.\n'
fi

verify_controls
printf '%s\n' \
  'Manual evidence still required: environment administrator bypass is disabled.'
printf 'GitHub repository controls verified for %s.\n' "${REPOSITORY}"
