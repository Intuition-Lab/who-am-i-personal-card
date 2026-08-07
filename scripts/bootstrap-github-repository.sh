#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="plan"
MODE_COUNT=0
REPOSITORY=""
REPOSITORY_COUNT=0
VISIBILITY=""
VISIBILITY_COUNT=0
DESCRIPTION=""
DESCRIPTION_COUNT=0
PRIVATE_ENTERPRISE=0
GH_COMMAND=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/bootstrap-github-repository.sh MODE OPTIONS

Modes:
  --plan    Print the exact creation plan without reading GitHub or mutating Git.
  --check   Validate local state, authentication, and remote nonexistence.
  --apply   Create the reviewed root commit, GitHub repository, origin, and push.

Required options:
  --repository OWNER/REPOSITORY
  --public | --private
  --description TEXT

Conditional option:
  --private-enterprise
             Required with --private. Confirms the approved GitHub plan can
             enforce required environment reviewers on a private repository.

The script is only for a brand-new repository. It requires main, HOLD/HOLD,
a reviewed License, a placeholder-free README, configured local Git author
identity, no origin, no existing GitHub repository, and a clean staged tree.
It never creates a tag or Release.
EOF
}

fail() {
  printf 'Repository-bootstrap error: %s\n' "$*" >&2
  exit 1
}

safe_user_executable() {
  local candidate="$1"
  local metadata owner mode
  [[ "${candidate}" == /* && -f "${candidate}" && ! -L "${candidate}" \
    && -x "${candidate}" ]] || return 1
  metadata="$(
    /usr/bin/stat -f '%u %Lp' "${candidate}" 2>/dev/null \
      || /usr/bin/stat -c '%u %a' "${candidate}" 2>/dev/null \
      || true
  )"
  read -r owner mode <<<"${metadata}"
  [[ "${owner}" =~ ^[0-9]+$ && "${owner}" == "$(/usr/bin/id -u)" \
    && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
  mode="${mode: -3}"
  (( (8#${mode} & 0022) == 0 ))
}

validate_repository() {
  if [[ ! "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*/[A-Za-z0-9_.-]+$ \
    || "$1" == *".."* || "$1" == */.* ]]; then
    fail "repository must be an explicit OWNER/REPOSITORY name"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      MODE="plan"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --check)
      MODE="check"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --apply)
      MODE="apply"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --repository)
      [[ $# -ge 2 ]] || fail "--repository requires a value"
      REPOSITORY="$2"
      REPOSITORY_COUNT=$((REPOSITORY_COUNT + 1))
      shift 2
      ;;
    --public)
      VISIBILITY="public"
      VISIBILITY_COUNT=$((VISIBILITY_COUNT + 1))
      shift
      ;;
    --private)
      VISIBILITY="private"
      VISIBILITY_COUNT=$((VISIBILITY_COUNT + 1))
      shift
      ;;
    --description)
      [[ $# -ge 2 ]] || fail "--description requires a value"
      DESCRIPTION="$2"
      DESCRIPTION_COUNT=$((DESCRIPTION_COUNT + 1))
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
[[ "${VISIBILITY_COUNT}" -eq 1 ]] \
  || fail "choose exactly one of --public or --private"
[[ "${DESCRIPTION_COUNT}" -eq 1 ]] \
  || fail "--description must be provided exactly once"
validate_repository "${REPOSITORY}"
if [[ -z "${DESCRIPTION}" || "${DESCRIPTION}" == *[[:cntrl:]]* \
  || "${#DESCRIPTION}" -gt 350 ]]; then
  fail "description must be 1-350 characters without control characters"
fi
if [[ "${VISIBILITY}" == "private" && "${PRIVATE_ENTERPRISE}" -ne 1 ]]; then
  fail "private creation requires explicit --private-enterprise confirmation"
fi
if [[ "${VISIBILITY}" == "public" && "${PRIVATE_ENTERPRISE}" -eq 1 ]]; then
  fail "--private-enterprise is valid only with --private"
fi

print_plan() {
  cat <<EOF
New GitHub repository: ${REPOSITORY}
Visibility:            ${VISIBILITY}
Description:           ${DESCRIPTION}
Private Enterprise:    $([[ "${PRIVATE_ENTERPRISE}" -eq 1 ]] && printf true || printf false)

The explicit --apply mode will:
  1. require main with no existing commit or remote;
  2. require RELEASE_STATUS=HOLD and PILOT_STATUS=HOLD;
  3. require a reviewed License and placeholder-free README;
  4. require configured local Git author name and email;
  5. require all intended files staged with no unstaged or untracked files;
  6. prove ${REPOSITORY} does not already exist for the authenticated identity;
  7. create one reviewed root commit;
  8. create ${REPOSITORY} with Issues enabled and Wiki disabled;
  9. add origin and push main;
 10. read back repository name, visibility, default branch, and Issues state.

No tag, Release, ruleset, environment, secret, or invitation is created.
No Git or GitHub request was made in --plan mode.
EOF
}

if [[ "${MODE}" == "plan" ]]; then
  print_plan
  exit 0
fi

git_top="$(
  /usr/bin/git -C "${PRODUCT_ROOT}" rev-parse --show-toplevel 2>/dev/null \
    || true
)"
[[ "${git_top}" == "${PRODUCT_ROOT}" ]] \
  || fail "script must run from the intended product Git repository"
current_branch="$(
  /usr/bin/git -C "${PRODUCT_ROOT}" symbolic-ref --quiet --short HEAD \
    2>/dev/null || true
)"
[[ "${current_branch}" == "main" ]] \
  || fail "brand-new repository branch must be main"
if /usr/bin/git -C "${PRODUCT_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
  fail "bootstrap is limited to a repository with no existing commit"
fi
if /usr/bin/git -C "${PRODUCT_ROOT}" remote get-url origin >/dev/null 2>&1; then
  fail "origin already exists; bootstrap refuses to replace it"
fi

bash "${PRODUCT_ROOT}/scripts/release-readiness.sh" --check >/dev/null
[[ "$(/bin/cat "${PRODUCT_ROOT}/RELEASE_STATUS")" == "HOLD" ]] \
  || fail "initial repository creation requires RELEASE_STATUS=HOLD"
[[ "$(/bin/cat "${PRODUCT_ROOT}/PILOT_STATUS")" == "HOLD" ]] \
  || fail "initial repository creation requires PILOT_STATUS=HOLD"

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
[[ -n "${license_path}" ]] \
  || fail "a reviewed, non-empty License is required before repository creation"
license_relative="${license_path#"${PRODUCT_ROOT}/"}"
if ! /usr/bin/git -C "${PRODUCT_ROOT}" \
  ls-files --error-unmatch "${license_relative}" >/dev/null 2>&1; then
  fail "the reviewed License must be staged for the initial repository"
fi
if LC_ALL=C /usr/bin/grep -Eiq \
  'TBD|TODO|TBC|___|<owner>|<new-product-repository>' \
  "${PRODUCT_ROOT}/README.md"; then
  fail "README still contains a repository or release placeholder"
fi

git_author_name="$(
  /usr/bin/git -C "${PRODUCT_ROOT}" config --get user.name 2>/dev/null || true
)"
git_author_email="$(
  /usr/bin/git -C "${PRODUCT_ROOT}" config --get user.email 2>/dev/null || true
)"
[[ -n "${git_author_name}" && "${git_author_name}" != *[[:cntrl:]]* ]] \
  || fail "configure a safe local Git user.name before repository creation"
[[ "${git_author_email}" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] \
  || fail "configure a valid local Git user.email before repository creation"

if /usr/bin/git -C "${PRODUCT_ROOT}" diff --quiet -- .; then
  :
else
  fail "unstaged tracked changes exist"
fi
untracked_files="$(
  /usr/bin/git -C "${PRODUCT_ROOT}" \
    ls-files --others --exclude-standard
)"
[[ -z "${untracked_files}" ]] || fail "untracked files exist"
if /usr/bin/git -C "${PRODUCT_ROOT}" diff --cached --quiet --exit-code; then
  fail "no staged initial repository content was found"
fi
/usr/bin/git -C "${PRODUCT_ROOT}" diff --cached --check

if GH_COMMAND="$(command -v gh)" && safe_user_executable "${GH_COMMAND}"; then
  :
elif safe_user_executable "${HOME}/.local/bin/gh"; then
  GH_COMMAND="${HOME}/.local/bin/gh"
else
  fail "GitHub CLI (gh) is required for --${MODE}"
fi
"${GH_COMMAND}" auth status >/dev/null
repository_probe=""
if repository_probe="$(
  "${GH_COMMAND}" api \
    --header "X-GitHub-Api-Version: 2026-03-10" \
    "/repos/${REPOSITORY}" 2>&1
)"; then
  fail "GitHub repository already exists: ${REPOSITORY}"
fi
case "${repository_probe}" in
  *"HTTP 404"*|*'"status":"404"'*|*'"status": "404"'*) ;;
  *)
    printf '%s\n' "${repository_probe}" >&2
    fail "could not prove the GitHub repository name is unused"
    ;;
esac

printf 'Repository bootstrap preflight passed for %s.\n' "${REPOSITORY}"
if [[ "${MODE}" == "check" ]]; then
  exit 0
fi

/usr/bin/git -C "${PRODUCT_ROOT}" \
  -c core.hooksPath=/dev/null \
  -c commit.gpgSign=false \
  commit \
  --message "Initial product beta foundation"

visibility_flag="--public"
if [[ "${VISIBILITY}" == "private" ]]; then
  visibility_flag="--private"
fi
"${GH_COMMAND}" repo create "${REPOSITORY}" \
  "${visibility_flag}" \
  --description "${DESCRIPTION}" \
  --disable-wiki \
  --source "${PRODUCT_ROOT}" \
  --remote origin \
  --push

repository_state="$(
  "${GH_COMMAND}" api \
    --header "X-GitHub-Api-Version: 2026-03-10" \
    "/repos/${REPOSITORY}" \
    --jq '[.full_name, .visibility, .default_branch, .has_issues,
           .archived, .disabled] | @tsv'
)"
IFS=$'\t' read -r \
  live_name live_visibility live_default live_issues live_archived live_disabled \
  <<<"${repository_state}"
[[ "${live_name}" == "${REPOSITORY}" ]] \
  || fail "created repository name did not match the approved name"
[[ "${live_visibility}" == "${VISIBILITY}" ]] \
  || fail "created repository visibility did not match the approved value"
[[ "${live_default}" == "main" ]] \
  || fail "created repository default branch is not main"
[[ "${live_issues}" == "true" ]] || fail "Issues are not enabled"
[[ "${live_archived}" == "false" && "${live_disabled}" == "false" ]] \
  || fail "created repository is archived or disabled"

printf '%s\n' \
  "Created and pushed ${REPOSITORY} with HOLD/HOLD release controls." \
  'Wait for the first CI run, then apply github-repository-controls.sh.'
