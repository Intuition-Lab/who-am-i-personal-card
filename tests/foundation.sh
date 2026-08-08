#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_LIBRARY="${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"
RUNTIME_LOCK="${PRODUCT_ROOT}/runtime.lock"
PRODUCT_LOCK_LIBRARY="${PRODUCT_ROOT}/scripts/lib/product-lock.sh"
PRODUCT_LOCK="${PRODUCT_ROOT}/product.lock"
VERSION_LIBRARY="${PRODUCT_ROOT}/scripts/lib/product-version.sh"
CONTEXT_HOOK="${PRODUCT_ROOT}/plugins/personal-model-context/scripts/context_hook.py"
CONTEXT_HOOK_FIXTURE="${PRODUCT_ROOT}/tests/fixtures/fake-persome-mcp.py"

SUITE_TMP_BASE="${TMPDIR:-/tmp}"
SUITE_TMP_BASE="${SUITE_TMP_BASE%/}"
if [[ "${SUITE_TMP_BASE}" != /* || ! -d "${SUITE_TMP_BASE}" \
  || ! -w "${SUITE_TMP_BASE}" ]]; then
  SUITE_TMP_BASE="/tmp"
fi
SUITE_TMP_BASE="$(cd "${SUITE_TMP_BASE}" && pwd -P)"
TEST_ROOT="$(mktemp -d "${SUITE_TMP_BASE}/personal-model-foundation-tests.XXXXXX")"
TEST_ROOT="$(cd "${TEST_ROOT}" && pwd -P)"
TEST_HOME="${TEST_ROOT}/home"
TEST_CASES="${TEST_ROOT}/cases"
TEST_TMPDIR="${TEST_ROOT}/tmp"
mkdir -p "${TEST_HOME}" "${TEST_CASES}" "${TEST_TMPDIR}"

cleanup_suite() {
  local cleanup_status=$?
  local candidate="${TEST_ROOT:-}"
  case "${candidate}" in
    "${SUITE_TMP_BASE}"/personal-model-foundation-tests.??????)
      if [[ -d "${candidate}" && ! -L "${candidate}" && -O "${candidate}" ]]; then
        rm -rf -- "${candidate}"
      fi
      ;;
    *)
      printf 'Refusing unsafe test cleanup path: %s\n' \
        "${candidate:-<empty>}" >&2
      return 1
      ;;
  esac
  return "${cleanup_status}"
}
trap cleanup_suite EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Every command spawned by this suite receives an owner-controlled disposable
# HOME. In particular, no test can resolve the Runtime root to ~/.persome under
# the developer's real account.
export HOME="${TEST_HOME}"
export TMPDIR="${TEST_TMPDIR}"
unset PERSOME_INSTALL_HOME
unset PERSOME_PYTHON
# GitHub Actions injects this globally. Release-decision fixtures must control
# the expected commit explicitly instead of inheriting the workflow commit.
unset GITHUB_SHA

# shellcheck source=scripts/lib/runtime-lock.sh
source "${RUNTIME_LIBRARY}"
# shellcheck source=scripts/lib/product-lock.sh
source "${PRODUCT_LOCK_LIBRARY}"
# shellcheck source=scripts/lib/product-version.sh
source "${VERSION_LIBRARY}"

CASE_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

run_case() {
  local name="$1"
  local output output_file status
  shift
  CASE_COUNT=$((CASE_COUNT + 1))
  output_file="${TEST_CASES}/run-case-${CASE_COUNT}.out"

  # Bash disables errexit inside functions invoked directly by an `if`.
  # Execute every case in its own errexit-enabled subshell so a failed
  # intermediate assertion cannot be hidden by a later successful command.
  set +e
  (
    set -e
    "$@"
  ) > "${output_file}" 2>&1
  status=$?
  set -e
  output="$(command cat "${output_file}")"

  if [[ "${status}" -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok %d - %s\n' "${CASE_COUNT}" "${name}"
    return 0
  fi

  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %d - %s\n' "${CASE_COUNT}" "${name}"
  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" | sed 's/^/  /'
  fi
  return 0
}

assert_rejected() {
  local output
  if output="$("$@" 2>&1)"; then
    printf 'Expected command to be rejected:'
    printf ' %q' "$@"
    printf '\n'
    return 1
  fi
}

assert_rejected_contains() {
  local expected="$1"
  local output
  shift

  if output="$("$@" 2>&1)"; then
    printf 'Expected command to be rejected:'
    printf ' %q' "$@"
    printf '\n'
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "${expected}"; then
    printf 'Rejection did not contain expected text: %s\n' "${expected}"
    printf '%s\n' "${output}"
    return 1
  fi
}

replace_lock_value() {
  local destination="$1"
  local target_key="$2"
  local replacement_value="$3"
  local line key

  : > "${destination}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    key="${line%%=*}"
    if [[ "${key}" == "${target_key}" ]]; then
      printf '%s="%s"\n' "${target_key}" "${replacement_value}" \
        >> "${destination}"
    else
      printf '%s\n' "${line}" >> "${destination}"
    fi
  done < "${RUNTIME_LOCK}"
}

test_valid_lock() {
  runtime_lock_load "${RUNTIME_LOCK}"
  [[ "${RUNTIME_LOCK_SCHEMA}" == "1" ]]
  [[ "${RUNTIME_REPOSITORY}" == \
    "https://github.com/Intuition-Lab/personal-model.git" ]]
  [[ "${RUNTIME_COMMIT}" =~ ^[0-9a-f]{40}$ ]]
  [[ "${RUNTIME_TREE}" =~ ^[0-9a-f]{40}$ ]]
  [[ "${RUNTIME_INSTALLER_SHA256}" =~ ^[0-9a-f]{64}$ ]]
}

test_unknown_lock_key() {
  local candidate="${TEST_CASES}/unknown.lock"
  command cp "${RUNTIME_LOCK}" "${candidate}"
  printf 'RUNTIME_SURPRISE="nope"\n' >> "${candidate}"
  assert_rejected_contains "Unknown Runtime lock key" \
    runtime_lock_load "${candidate}"
}

test_duplicate_lock_key() {
  local candidate="${TEST_CASES}/duplicate.lock"
  command cp "${RUNTIME_LOCK}" "${candidate}"
  printf 'RUNTIME_CLI="persome"\n' >> "${candidate}"
  assert_rejected_contains "Duplicate Runtime lock key" \
    runtime_lock_load "${candidate}"
}

test_malicious_lock_is_data_only() {
  local candidate="${TEST_CASES}/malicious.lock"
  local marker="${TEST_CASES}/malicious-lock-executed"
  local line key

  : > "${candidate}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    key="${line%%=*}"
    if [[ "${key}" == "RUNTIME_COMMIT" ]]; then
      # This command substitution must remain literal malicious test input.
      # shellcheck disable=SC2016
      printf 'RUNTIME_COMMIT="$(touch %s)"\n' "${marker}" >> "${candidate}"
    else
      printf '%s\n' "${line}" >> "${candidate}"
    fi
  done < "${RUNTIME_LOCK}"

  assert_rejected_contains "full lowercase SHA-1" \
    runtime_lock_load "${candidate}"
  if [[ -e "${marker}" ]]; then
    printf 'Malicious Runtime lock content was executed.\n'
    return 1
  fi
}

test_symlink_lock_rejected() {
  local candidate="${TEST_CASES}/runtime-symlink.lock"
  ln -s "${RUNTIME_LOCK}" "${candidate}"
  assert_rejected_contains "Runtime lock is missing or unsafe" \
    runtime_lock_load "${candidate}"
}

test_short_commit_rejected() {
  local candidate="${TEST_CASES}/short-commit.lock"
  replace_lock_value "${candidate}" "RUNTIME_COMMIT" "e1315d03cafb"
  assert_rejected_contains "full lowercase SHA-1" \
    runtime_lock_load "${candidate}"
}

test_wrong_repository_rejected() {
  local candidate="${TEST_CASES}/wrong-repository.lock"
  replace_lock_value \
    "${candidate}" \
    "RUNTIME_REPOSITORY" \
    "https://github.com/example/personal-model.git"
  assert_rejected_contains "not the reviewed Personal Model source" \
    runtime_lock_load "${candidate}"
}

test_invalid_digest_rejected() {
  local candidate="${TEST_CASES}/invalid-digest.lock"
  replace_lock_value "${candidate}" "RUNTIME_INSTALLER_SHA256" "abc123"
  assert_rejected_contains "lowercase SHA-256" \
    runtime_lock_load "${candidate}"
}

test_valid_product_lock() {
  product_lock_load "${PRODUCT_LOCK}"
  [[ "${PRODUCT_NODE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "${PRODUCT_NODE_BASE_URL}" == \
    "https://nodejs.org/dist/v${PRODUCT_NODE_VERSION}" ]]
  [[ "${PRODUCT_NODE_DARWIN_ARM64_SHA256}" =~ ^[0-9a-f]{64}$ ]]
  [[ "${PRODUCT_NODE_DARWIN_X64_SHA256}" =~ ^[0-9a-f]{64}$ ]]
}

test_duplicate_product_lock_key() {
  local candidate="${TEST_CASES}/duplicate-product.lock"
  command cp "${PRODUCT_LOCK}" "${candidate}"
  printf 'PRODUCT_NODE_VERSION="99.99.99"\n' >> "${candidate}"
  assert_rejected_contains "Duplicate product lock key" \
    product_lock_load "${candidate}"
}

test_malicious_product_lock_is_data_only() {
  local candidate="${TEST_CASES}/malicious-product.lock"
  local marker="${TEST_CASES}/malicious-product-lock-executed"

  command cp "${PRODUCT_LOCK}" "${candidate}"
  # This command substitution must remain literal malicious test input.
  # shellcheck disable=SC2016
  printf 'PRODUCT_ATTACK="$(touch %s)"\n' "${marker}" >> "${candidate}"
  assert_rejected_contains "Unknown product lock key" \
    product_lock_load "${candidate}"
  [[ ! -e "${marker}" ]]
}

test_symlink_product_lock_rejected() {
  local candidate="${TEST_CASES}/product-symlink.lock"
  ln -s "${PRODUCT_LOCK}" "${candidate}"
  assert_rejected_contains "Product lock is missing or unsafe" \
    product_lock_load "${candidate}"
}

test_invalid_home_rejected() {
  (
    unset PERSOME_INSTALL_HOME
    unset PERSOME_PYTHON
    HOME="/"
    assert_rejected_contains "HOME must be an owner-controlled" \
      runtime_install_home_resolve
  )
}

test_symlink_home_rejected() {
  local real_home="${TEST_CASES}/real-home"
  local linked_home="${TEST_CASES}/linked-home"
  mkdir "${real_home}"
  ln -s "${real_home}" "${linked_home}"
  (
    unset PERSOME_INSTALL_HOME
    unset PERSOME_PYTHON
    HOME="${linked_home}"
    assert_rejected_contains "HOME must be an owner-controlled" \
      runtime_install_home_resolve
  )
}

test_home_symlink_ancestor_rejected() {
  local real_parent="${TEST_CASES}/real-home-parent"
  local linked_parent="${TEST_CASES}/linked-home-parent"
  mkdir -p "${real_parent}/child"
  ln -s "${real_parent}" "${linked_parent}"
  (
    unset PERSOME_INSTALL_HOME
    unset PERSOME_PYTHON
    HOME="${linked_parent}/child"
    assert_rejected_contains \
      "HOME must not traverse a symlink or non-directory" \
      runtime_install_home_resolve
  )
}

test_install_home_outside_home_rejected() {
  (
    unset PERSOME_PYTHON
    HOME="${TEST_HOME}"
    PERSOME_INSTALL_HOME="${TEST_ROOT}/outside-home"
    assert_rejected_contains "must be a child directory of HOME" \
      runtime_install_home_resolve
  )
}

test_install_home_traversal_rejected() {
  (
    unset PERSOME_PYTHON
    HOME="${TEST_HOME}"
    PERSOME_INSTALL_HOME="${TEST_HOME}/runtime/../escape"
    assert_rejected_contains "contains unsafe path components" \
      runtime_install_home_resolve
  )
}

test_install_home_symlink_traversal_rejected() {
  local real_directory="${TEST_HOME}/real-runtime-parent"
  local linked_directory="${TEST_HOME}/runtime-link"
  mkdir "${real_directory}"
  ln -s "${real_directory}" "${linked_directory}"
  (
    unset PERSOME_PYTHON
    HOME="${TEST_HOME}"
    PERSOME_INSTALL_HOME="${linked_directory}/runtime"
    assert_rejected_contains "must not traverse a symlink" \
      runtime_install_home_resolve
  )
}

test_shared_writable_install_home_rejected() {
  local install_home="${TEST_HOME}/shared-runtime"
  mkdir "${install_home}"
  chmod 0777 "${install_home}"
  (
    unset PERSOME_PYTHON
    HOME="${TEST_HOME}"
    PERSOME_INSTALL_HOME="${install_home}"
    assert_rejected_contains \
      "must not be group- or world-writable" \
      runtime_install_home_resolve
  )
}

test_invalid_python_selector_rejected() {
  (
    unset PERSOME_INSTALL_HOME
    HOME="${TEST_HOME}"
    PERSOME_PYTHON="3.11.9"
    assert_rejected_contains "must select Python 3.12 or 3.13" \
      runtime_install_home_resolve
  )
}

test_supported_python_selector_accepted() {
  (
    unset PERSOME_INSTALL_HOME
    HOME="${TEST_HOME}"
    # Read by runtime_install_home_resolve through Bash dynamic scope.
    # shellcheck disable=SC2034
    PERSOME_PYTHON="3.12.8"
    runtime_install_home_resolve
    [[ "${RUNTIME_INSTALL_HOME}" == "${TEST_HOME}/.persome" ]]
  )
}

test_interaction_flags_conflict() {
  local install_home="${TEST_HOME}/interaction-conflict"
  local output="${TEST_CASES}/interaction-conflict.out"
  local status

  if HOME="${TEST_HOME}" PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/install.sh" \
      --interactive --non-interactive </dev/null > "${output}" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "${status}" -ne 2 ]]; then
    printf 'Expected conflicting interaction flags to exit 2; got %s.\n' \
      "${status}"
    command cat "${output}"
    return 1
  fi
  grep -Fq "Choose only one interaction mode." "${output}"
  [[ ! -e "${install_home}" ]]
}

test_interactive_install_without_tty_rejected() {
  local install_home="${TEST_HOME}/no-tty"
  local output="${TEST_CASES}/no-tty.out"
  local status

  if HOME="${TEST_HOME}" PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/install.sh" \
      --interactive </dev/null > "${output}" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "${status}" -eq 0 ]]; then
    printf 'Expected interactive installation without a TTY to fail.\n'
    command cat "${output}"
    return 1
  fi
  grep -Fq "Interactive installation requires terminal input and output." \
    "${output}"
  [[ ! -e "${install_home}" ]]
}

test_update_wrapper_rejects_non_interactive_mode() {
  local install_home="${TEST_HOME}/update-non-interactive"
  local output="${TEST_CASES}/update-non-interactive.out"
  local status

  if HOME="${TEST_HOME}" PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/update.sh" --non-interactive \
      </dev/null > "${output}" 2>&1; then
    status=0
  else
    status=$?
  fi
  [[ "${status}" -eq 2 ]]
  grep -Fq "Runtime updates cannot run non-interactively." "${output}"
  [[ ! -e "${install_home}" ]]
}

test_temporary_root_round_trip() {
  local temporary_root marker
  temporary_root="$(runtime_temporary_root_create "foundation-test")"
  marker="${temporary_root}/.product-installer-temporary-root"

  [[ -d "${temporary_root}" ]]
  [[ ! -L "${temporary_root}" ]]
  [[ -O "${temporary_root}" ]]
  [[ "${temporary_root%/*}" == "${TEST_TMPDIR}" ]]
  [[ -f "${marker}" && ! -L "${marker}" && -O "${marker}" ]]
  [[ "$(command cat "${marker}")" == "foundation-test" ]]
  printf 'payload\n' > "${temporary_root}/payload"

  runtime_temporary_root_remove "${temporary_root}" "foundation-test"
  [[ ! -e "${temporary_root}" ]]
}

test_temporary_root_tamper_blocks_cleanup() {
  local temporary_root marker
  temporary_root="$(runtime_temporary_root_create "foundation-tamper")"
  marker="${temporary_root}/.product-installer-temporary-root"
  printf 'wrong-prefix\n' > "${marker}"

  assert_rejected_contains "Refusing to remove an unverified temporary path" \
    runtime_temporary_root_remove "${temporary_root}" "foundation-tamper"
  [[ -d "${temporary_root}" ]]

  printf 'foundation-tamper\n' > "${marker}"
  runtime_temporary_root_remove "${temporary_root}" "foundation-tamper"
  [[ ! -e "${temporary_root}" ]]
}

test_unsafe_temporary_prefix_rejected() {
  assert_rejected_contains "Unsafe temporary directory prefix" \
    runtime_temporary_root_create "../foundation"
}

test_runtime_checkout_retries_transient_fetch() {
  local destination="${TEST_CASES}/runtime-fetch-retry"
  local fetch_calls=0

  runtime_lock_load "${RUNTIME_LOCK}"
  runtime_git() {
    if [[ "${1:-}" == "init" ]]; then
      mkdir -p "$3"
      return 0
    fi
    case " $* " in
      *" fetch "*)
        fetch_calls=$((fetch_calls + 1))
        [[ "${fetch_calls}" -ge 2 ]]
        ;;
      *) return 0 ;;
    esac
  }

  runtime_checkout_create "${destination}"
  [[ "${fetch_calls}" -eq 2 ]]
}

test_bundled_runtime_checkout_is_copied_and_verified() {
  local source_checkout="${TEST_CASES}/bundled-runtime-source"
  local destination="${TEST_CASES}/bundled-runtime-copy"
  local verify_calls=0

  mkdir -p "${source_checkout}/.git"
  printf 'runtime payload\n' > "${source_checkout}/payload.txt"
  runtime_checkout_verify() {
    local checkout="$1"
    verify_calls=$((verify_calls + 1))
    [[ "${checkout}" == "${destination}" ]]
    [[ -d "${checkout}/.git" ]]
    grep -Fq 'runtime payload' "${checkout}/payload.txt"
  }

  runtime_checkout_copy_bundled "${source_checkout}" "${destination}"
  [[ "${verify_calls}" -eq 1 ]]
  [[ -f "${destination}/payload.txt" ]]
}

test_bundled_runtime_checkout_rejects_symlinks() {
  local source_checkout="${TEST_CASES}/bundled-runtime-symlink"
  local destination="${TEST_CASES}/bundled-runtime-symlink-copy"

  mkdir -p "${source_checkout}/.git"
  printf 'payload\n' > "${source_checkout}/payload.txt"
  ln -s payload.txt "${source_checkout}/linked-payload.txt"

  assert_rejected_contains "contains a symbolic link" \
    runtime_checkout_copy_bundled "${source_checkout}" "${destination}"
  [[ ! -e "${destination}" ]]
}

test_product_installer_never_fetches_runtime_source() {
  local installer="${PRODUCT_ROOT}/install.sh"
  local uninstaller="${PRODUCT_ROOT}/uninstall-runtime.sh"

  grep -Fq 'prepare_bundled_runtime_checkout' "${installer}"
  grep -Fq 'never access the Personal Model source repository' "${installer}"
  if grep -Eq '^[[:space:]]*runtime_checkout_create([[:space:]]|$)' \
    "${installer}"; then
    printf 'Product installer still creates a network Runtime checkout.\n'
    return 1
  fi
  if grep -Eq '^[[:space:]]*runtime_checkout_create([[:space:]]|$)' \
    "${uninstaller}"; then
    printf 'Product uninstaller still creates a network Runtime checkout.\n'
    return 1
  fi
}

test_personal_card_replacement_is_transactional() {
  local installer="${PRODUCT_ROOT}/install.sh"

  grep -Fq 'personal_card_transaction_rollback()' "${installer}"
  grep -Fq 'personal_card_transaction_commit()' "${installer}"
  grep -Fq 'PERSONAL_CARD_TRANSACTION_ACTIVE=1' "${installer}"
  grep -Fq 'after-card-before-verification' "${installer}"
  [[ "$(grep -Fc 'personal_card_transaction_commit' "${installer}")" -eq 4 ]]
  [[ "$(grep -Fc 'installer_test_failpoint "after-card-before-verification"' \
    "${installer}")" -eq 3 ]]
  awk '
    /install_personal_card$/ { installed++ }
    /verify-product\.sh"$/ { verified++ }
    /personal_card_transaction_commit$/ {
      if (installed < 1 || verified < 1) exit 1
      committed++
      installed=0
      verified=0
    }
    END { if (committed != 3) exit 1 }
  ' "${installer}"
}

test_receipt_round_trip() {
  local install_home="${TEST_HOME}/receipt-round-trip"
  local receipt="${install_home}/product-runtime.lock"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  # Read by runtime_install_home_resolve through Bash dynamic scope.
  # shellcheck disable=SC2034
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write "${receipt}"
  runtime_receipt_verify "${receipt}"

  grep -Fq "RUNTIME_COMMIT=\"${RUNTIME_COMMIT}\"" "${receipt}"
  grep -Fq "RUNTIME_TREE=\"${RUNTIME_TREE}\"" "${receipt}"
}

test_tampered_receipt_rejected() {
  local install_home="${TEST_HOME}/receipt-tampered"
  local receipt="${install_home}/product-runtime.lock"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write "${receipt}"
  printf 'TAMPERED="1"\n' >> "${receipt}"

  assert_rejected_contains "does not match runtime.lock" \
    runtime_receipt_verify "${receipt}"
}

test_changed_lock_rejects_existing_receipt() {
  local install_home="${TEST_HOME}/receipt-lock-changed"
  local receipt="${install_home}/product-runtime.lock"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write "${receipt}"
  RUNTIME_COMMIT="0000000000000000000000000000000000000000"

  assert_rejected_contains "does not match runtime.lock" \
    runtime_receipt_verify "${receipt}"
}

test_previous_lock_verifies_cross_runtime_update() {
  local install_home="${TEST_HOME}/previous-lock-update"
  local management_root="${install_home}/product-management"
  local previous_lock="${management_root}/runtime.lock"
  local previous_commit="0000000000000000000000000000000000000000"

  mkdir -p "${management_root}"
  chmod 0700 "${management_root}"
  replace_lock_value "${previous_lock}" "RUNTIME_COMMIT" "${previous_commit}"
  chmod 0600 "${previous_lock}"

  runtime_lock_load "${previous_lock}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  write_fake_runtime_venv "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/product-runtime.lock"

  runtime_lock_load "${RUNTIME_LOCK}"
  assert_rejected runtime_managed_install_verify
  runtime_managed_install_verify_with_lock \
    "${previous_lock}" "${RUNTIME_LOCK}"
  [[ "${RUNTIME_COMMIT}" != "${previous_commit}" ]]
  [[ "${RUNTIME_COMMIT}" == \
    "$(sed -nE 's/^RUNTIME_COMMIT=\"([0-9a-f]+)\"$/\1/p' "${RUNTIME_LOCK}")" ]]
}

test_malformed_previous_lock_restores_target_identity() {
  local candidate="${TEST_CASES}/malformed-previous.lock"
  local target_commit

  printf 'not-a-lock\n' > "${candidate}"
  chmod 0600 "${candidate}"
  runtime_lock_load "${RUNTIME_LOCK}"
  target_commit="${RUNTIME_COMMIT}"

  assert_rejected \
    runtime_managed_install_verify_with_lock "${candidate}" "${RUNTIME_LOCK}"
  [[ "${RUNTIME_COMMIT}" == "${target_commit}" ]]
}

test_symlink_receipt_rejected() {
  local install_home="${TEST_HOME}/receipt-symlink"
  local target="${install_home}/target"
  local receipt="${install_home}/product-runtime.lock"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  printf 'do not overwrite\n' > "${target}"
  ln -s "${target}" "${receipt}"

  assert_rejected_contains "Runtime receipt path is unsafe" \
    runtime_receipt_write "${receipt}"
  [[ "$(command cat "${target}")" == "do not overwrite" ]]
}

write_fake_runtime_venv() {
  local install_home="$1"
  local bin_directory="${install_home}/venv/bin"
  mkdir -p "${bin_directory}"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "%s"\n' "${RUNTIME_PROJECT_VERSION}"
  } > "${bin_directory}/python"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exit 0\n'
  } > "${bin_directory}/${RUNTIME_CLI}"
  chmod 0700 "${bin_directory}/python" "${bin_directory}/${RUNTIME_CLI}"
}

prepare_fake_runtime_install() {
  local install_home="$1"
  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  write_fake_runtime_venv "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/product-runtime.lock"
}

verify_fake_runtime_install() {
  local install_home="$1"
  HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/scripts/verify.sh" --quick
}

test_dual_receipt_round_trip() {
  local install_home="${TEST_HOME}/dual-receipt-round-trip"
  prepare_fake_runtime_install "${install_home}"

  [[ -f "${install_home}/product-runtime.lock" ]]
  [[ -f "${install_home}/venv/.product-runtime.lock" ]]
  verify_fake_runtime_install "${install_home}" |
    grep -Fq "CLI OK: ${RUNTIME_PROJECT_NAME} ${RUNTIME_PROJECT_VERSION}"
}

test_owner_controlled_standalone_runtime_is_connectable_without_receipts() {
  local install_home="${TEST_HOME}/standalone-runtime"
  runtime_lock_load "${RUNTIME_LOCK}"
  PERSOME_INSTALL_HOME="${install_home}"
  runtime_install_home_resolve
  mkdir -p "${install_home}"
  write_fake_runtime_venv "${install_home}"

  runtime_existing_install_verify
  [[ ! -e "${install_home}/product-runtime.lock" ]]
  [[ ! -e "${install_home}/venv/.product-runtime.lock" ]]
  assert_rejected runtime_managed_install_verify
}

test_standalone_runtime_symlink_cli_is_rejected() {
  local install_home="${TEST_HOME}/standalone-symlink"
  local external_cli="${TEST_CASES}/standalone-external-cli"
  runtime_lock_load "${RUNTIME_LOCK}"
  PERSOME_INSTALL_HOME="${install_home}"
  runtime_install_home_resolve
  mkdir -p "${install_home}"
  write_fake_runtime_venv "${install_home}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${external_cli}"
  chmod 0700 "${external_cli}"
  rm -f -- "${install_home}/venv/bin/${RUNTIME_CLI}"
  ln -s "${external_cli}" "${install_home}/venv/bin/${RUNTIME_CLI}"

  assert_rejected runtime_existing_install_verify
}

test_non_interactive_update_is_rejected_before_mutation() {
  local install_home="${TEST_HOME}/non-interactive-update"
  local output="${TEST_CASES}/non-interactive-update.out"
  local previous_lock="${install_home}/product-management/runtime.lock"
  local previous_commit="0000000000000000000000000000000000000000"
  local before after status

  prepare_fake_runtime_install "${install_home}"
  mkdir -p "${install_home}/product-management"
  chmod 0700 "${install_home}/product-management"
  replace_lock_value "${previous_lock}" "RUNTIME_COMMIT" "${previous_commit}"
  chmod 0600 "${previous_lock}"
  runtime_lock_load "${previous_lock}"
  rm -f -- \
    "${install_home}/venv/.product-runtime.lock" \
    "${install_home}/product-runtime.lock"
  runtime_receipt_write "${install_home}/venv/.product-runtime.lock"
  runtime_receipt_write "${install_home}/product-runtime.lock"
  runtime_lock_load "${RUNTIME_LOCK}"
  mkdir -p "${install_home}/product-cache/uv"
  chmod 0700 "${install_home}/product-cache" \
    "${install_home}/product-cache/uv"
  printf 'preserve\n' > "${install_home}/personal-data"
  before="$(home_tree_snapshot "${install_home}")"

  if HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/install.sh" --non-interactive \
      > "${output}" 2>&1; then
    status=0
  else
    status=$?
  fi

  [[ "${status}" -eq 2 ]]
  grep -Fq \
    "Updating an existing Runtime requires an interactive logged-in terminal." \
    "${output}"
  after="$(home_tree_snapshot "${install_home}")"
  [[ "${after}" == "${before}" ]]
  [[ "$(command cat "${install_home}/personal-data")" == "preserve" ]]
  [[ ! -e "${install_home}/product-runtime.installing" ]]
  runtime_lock_load "${previous_lock}"
  runtime_receipt_verify "${install_home}/product-runtime.lock"
  runtime_receipt_verify "${install_home}/venv/.product-runtime.lock"
  runtime_lock_load "${RUNTIME_LOCK}"
}

test_replaced_venv_without_receipt_rejected() {
  local install_home="${TEST_HOME}/replaced-venv"
  local original_venv="${install_home}/venv.before-update"
  prepare_fake_runtime_install "${install_home}"

  # Model `persome update` replacing the complete environment while retaining
  # the same package version. The external receipt survives, but the newly
  # created venv deliberately has no product marker.
  mv "${install_home}/venv" "${original_venv}"
  write_fake_runtime_venv "${install_home}"
  assert_rejected_contains \
    "Pinned Persome installation identity or executable path is unsafe." \
    verify_fake_runtime_install "${install_home}"
}

test_missing_internal_receipt_rejected() {
  local install_home="${TEST_HOME}/missing-internal-receipt"
  local internal_receipt="${install_home}/venv/.product-runtime.lock"
  prepare_fake_runtime_install "${install_home}"

  rm -f -- "${internal_receipt}"
  [[ -f "${install_home}/product-runtime.lock" ]]
  assert_rejected_contains \
    "Pinned Persome installation identity or executable path is unsafe." \
    verify_fake_runtime_install "${install_home}"
}

test_tampered_internal_receipt_rejected() {
  local install_home="${TEST_HOME}/tampered-internal-receipt"
  local internal_receipt="${install_home}/venv/.product-runtime.lock"
  prepare_fake_runtime_install "${install_home}"

  printf 'TAMPERED="1"\n' >> "${internal_receipt}"
  assert_rejected_contains \
    "Pinned Persome installation identity or executable path is unsafe." \
    verify_fake_runtime_install "${install_home}"
}

test_missing_external_receipt_rejected() {
  local install_home="${TEST_HOME}/missing-external-receipt"
  local external_receipt="${install_home}/product-runtime.lock"
  prepare_fake_runtime_install "${install_home}"

  rm -f -- "${external_receipt}"
  [[ -f "${install_home}/venv/.product-runtime.lock" ]]
  assert_rejected_contains \
    "Pinned Persome installation identity or executable path is unsafe." \
    verify_fake_runtime_install "${install_home}"
}

prepare_sentinel_runtime() {
  local install_home="$1"
  local sentinel="$2"
  local bin_directory="${install_home}/venv/bin"

  mkdir -p "${bin_directory}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'touch "%s"\n' "${sentinel}"
    printf 'printf "%%s\\n" "%s"\n' "${RUNTIME_PROJECT_VERSION}"
  } > "${bin_directory}/python"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'touch "%s"\n' "${sentinel}"
    printf 'exit 0\n'
  } > "${bin_directory}/${RUNTIME_CLI}"
  chmod 0700 "${bin_directory}/python" "${bin_directory}/${RUNTIME_CLI}"
}

run_diagnostic_allow_failure() {
  local install_home="$1"
  local output_path="$2"
  HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/scripts/diagnose.sh" --json \
      > "${output_path}" 2>&1 || true
}

test_diagnostic_does_not_execute_without_receipts() {
  local install_home="${TEST_HOME}/diagnose-no-receipts"
  local sentinel="${TEST_CASES}/diagnose-no-receipts.executed"
  local output="${TEST_CASES}/diagnose-no-receipts.out"
  runtime_lock_load "${RUNTIME_LOCK}"
  prepare_sentinel_runtime "${install_home}" "${sentinel}"

  run_diagnostic_allow_failure "${install_home}" "${output}"
  [[ ! -e "${sentinel}" ]]
  grep -Fq '"status": "identity_mismatch"' "${output}"
}

test_diagnostic_does_not_execute_with_tampered_receipt() {
  local install_home="${TEST_HOME}/diagnose-tampered"
  local sentinel="${TEST_CASES}/diagnose-tampered.executed"
  local output="${TEST_CASES}/diagnose-tampered.out"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  prepare_sentinel_runtime "${install_home}" "${sentinel}"
  runtime_receipt_write "${install_home}/product-runtime.lock"
  runtime_receipt_write "${install_home}/venv/.product-runtime.lock"
  printf 'TAMPERED="1"\n' >> "${install_home}/product-runtime.lock"
  HOME="${TEST_HOME}"
  unset PERSOME_INSTALL_HOME

  run_diagnostic_allow_failure "${install_home}" "${output}"
  [[ ! -e "${sentinel}" ]]
  grep -Fq '"receipt": "mismatch"' "${output}"
}

test_diagnostic_does_not_follow_cli_symlink() {
  local install_home="${TEST_HOME}/diagnose-cli-symlink"
  local sentinel="${TEST_CASES}/diagnose-cli-symlink.executed"
  local output="${TEST_CASES}/diagnose-cli-symlink.out"
  local external_cli="${TEST_CASES}/external-persome"

  prepare_fake_runtime_install "${install_home}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'touch "%s"\n' "${sentinel}"
  } > "${external_cli}"
  chmod 0700 "${external_cli}"
  rm -f -- "${install_home}/venv/bin/${RUNTIME_CLI}"
  ln -s "${external_cli}" "${install_home}/venv/bin/${RUNTIME_CLI}"

  run_diagnostic_allow_failure "${install_home}" "${output}"
  [[ ! -e "${sentinel}" ]]
  grep -Fq '"venv_identity": "unsafe"' "${output}"
}

test_quick_verify_ignores_python_injection_environment() {
  local install_home="${TEST_HOME}/verify-clean-env"
  local sentinel="${TEST_CASES}/verify-env.executed"
  local bin_directory="${install_home}/venv/bin"

  prepare_fake_runtime_install "${install_home}"
  {
    printf '#!/usr/bin/env bash\n'
    # These variables must remain literal input for the generated sentinel.
    # shellcheck disable=SC2016
    printf 'if [[ -n "${PYTHONPATH:-}" || -n "${PYTHONHOME:-}" ]]; then\n'
    printf '  touch "%s"\n' "${sentinel}"
    printf 'fi\n'
    printf 'printf "%%s\\n" "%s"\n' "${RUNTIME_PROJECT_VERSION}"
  } > "${bin_directory}/python"
  {
    printf '#!/usr/bin/env bash\n'
    # These variables must remain literal input for the generated sentinel.
    # shellcheck disable=SC2016
    printf 'if [[ -n "${PYTHONPATH:-}" || -n "${PYTHONHOME:-}" ]]; then\n'
    printf '  touch "%s"\n' "${sentinel}"
    printf 'fi\n'
    printf 'exit 0\n'
  } > "${bin_directory}/${RUNTIME_CLI}"
  chmod 0700 "${bin_directory}/python" "${bin_directory}/${RUNTIME_CLI}"

  HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    PYTHONPATH="${TEST_CASES}/attacker-pythonpath" \
    PYTHONHOME="${TEST_CASES}/attacker-pythonhome" \
    bash "${PRODUCT_ROOT}/scripts/verify.sh" --quick >/dev/null
  [[ ! -e "${sentinel}" ]]
}

prepare_install_intent() {
  local install_home="$1"
  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  chmod 0700 "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/product-runtime.installing"
}

run_uninstaller_with_git_stub() {
  local install_home="$1"
  local output_path="$2"
  local git_log="$3"
  local stub_directory="${TEST_CASES}/git-stub-${install_home##*/}"
  local status
  shift 3

  mkdir -p "${stub_directory}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "git stub called\\n" >> "%s"\n' "${git_log}"
    printf 'exit 97\n'
  } > "${stub_directory}/git"
  chmod 0700 "${stub_directory}/git"

  if HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    PATH="${stub_directory}:${PATH}" \
    bash "${PRODUCT_ROOT}/uninstall-runtime.sh" "$@" \
      </dev/null > "${output_path}" 2>&1; then
    status=0
  else
    status=$?
  fi
  printf '%s\n' "${status}"
}

home_tree_snapshot() {
  local home_directory="$1"
  (
    cd "${home_directory}"
    find . -print | LC_ALL=C sort
  )
}

test_install_intent_round_trip() {
  local install_home="${TEST_HOME}/intent-round-trip"
  local intent="${install_home}/product-runtime.installing"
  prepare_install_intent "${install_home}"

  [[ -f "${intent}" && ! -L "${intent}" && -O "${intent}" ]]
  runtime_receipt_verify "${intent}"
  grep -Fq "RUNTIME_COMMIT=\"${RUNTIME_COMMIT}\"" "${intent}"
  grep -Fq "RUNTIME_TREE=\"${RUNTIME_TREE}\"" "${intent}"
}

test_matching_intent_recognized_by_uninstaller() {
  local install_home="${TEST_HOME}/intent-recovery"
  local intent="${install_home}/product-runtime.installing"
  local output="${TEST_CASES}/intent-recovery.out"
  prepare_install_intent "${install_home}"

  HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/uninstall-runtime.sh" --check-ownership \
      </dev/null > "${output}" 2>&1
  grep -Fq \
    "Recovering a product-managed installation that did not finish." \
    "${output}"
  grep -Fq "Runtime ownership state: recovery" "${output}"
  [[ -f "${intent}" ]]
  [[ ! -e "${install_home}/product-runtime.lock" ]]
}

test_tampered_intent_rejected_by_uninstaller() {
  local install_home="${TEST_HOME}/intent-tampered"
  local intent="${install_home}/product-runtime.installing"
  local output="${TEST_CASES}/intent-tampered.out"
  local git_log="${TEST_CASES}/intent-tampered.git-log"
  local status
  prepare_install_intent "${install_home}"
  printf 'TAMPERED="1"\n' >> "${intent}"

  status="$(
    run_uninstaller_with_git_stub \
      "${install_home}" "${output}" "${git_log}" --preserve-data
  )"
  if [[ "${status}" -eq 0 ]]; then
    printf 'Expected a tampered install intent to be rejected.\n'
    command cat "${output}"
    return 1
  fi
  grep -Fq \
    "No matching product receipt, install intent, or uninstall tombstone was found." \
    "${output}"
  [[ ! -e "${git_log}" ]]
  [[ -f "${intent}" ]]
}

test_wrong_lock_intent_rejected_by_uninstaller() {
  local install_home="${TEST_HOME}/intent-wrong-lock"
  local intent="${install_home}/product-runtime.installing"
  local output="${TEST_CASES}/intent-wrong-lock.out"
  local git_log="${TEST_CASES}/intent-wrong-lock.git-log"
  local status
  prepare_install_intent "${install_home}"

  RUNTIME_COMMIT="0000000000000000000000000000000000000000"
  runtime_receipt_write "${intent}"
  status="$(
    run_uninstaller_with_git_stub \
      "${install_home}" "${output}" "${git_log}" --preserve-data
  )"
  if [[ "${status}" -eq 0 ]]; then
    printf 'Expected an intent from a different lock to be rejected.\n'
    command cat "${output}"
    return 1
  fi
  grep -Fq \
    "No matching product receipt, install intent, or uninstall tombstone was found." \
    "${output}"
  [[ ! -e "${git_log}" ]]
  [[ -f "${intent}" ]]
}

test_completed_install_removes_intent() {
  local install_home="${TEST_HOME}/intent-completed"
  local intent="${install_home}/product-runtime.installing"
  prepare_install_intent "${install_home}"

  # This is the installer's success epilogue with a local fake Runtime: write
  # both durable identity markers, pass quick verification, validate the intent
  # path one final time, then remove only that intent.
  write_fake_runtime_venv "${install_home}"
  runtime_receipt_write \
    "${install_home}/venv/.product-runtime.lock"
  runtime_receipt_write \
    "${install_home}/product-runtime.lock"
  verify_fake_runtime_install "${install_home}" >/dev/null
  runtime_receipt_path_validate "${intent}"
  rm -f -- "${intent}"

  [[ ! -e "${intent}" && ! -L "${intent}" ]]
  runtime_receipt_verify "${install_home}/product-runtime.lock"
  runtime_receipt_verify \
    "${install_home}/venv/.product-runtime.lock"
}

test_uninstaller_print_plan_is_read_only() {
  local isolated_home="${TEST_CASES}/uninstall-plan-home"
  local install_home="${isolated_home}/runtime"
  local output="${TEST_CASES}/uninstall-plan.out"
  local before after
  runtime_lock_load "${RUNTIME_LOCK}"
  mkdir -p "${isolated_home}"
  printf 'keep\n' > "${isolated_home}/sentinel"
  before="$(home_tree_snapshot "${isolated_home}")"

  HOME="${isolated_home}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/uninstall-runtime.sh" --print-plan \
      </dev/null > "${output}" 2>&1

  after="$(home_tree_snapshot "${isolated_home}")"
  [[ "${after}" == "${before}" ]]
  [[ "$(command cat "${isolated_home}/sentinel")" == "keep" ]]
  [[ ! -e "${install_home}" ]]
  grep -Fq "Runtime data:      preserve" "${output}"
  grep -Fq "Runtime commit:    ${RUNTIME_COMMIT}" "${output}"
}

test_uninstaller_delete_data_without_tty_is_read_only() {
  local isolated_home="${TEST_CASES}/uninstall-delete-home"
  local install_home="${isolated_home}/runtime"
  local output="${TEST_CASES}/uninstall-delete.out"
  local before after status
  mkdir -p "${isolated_home}"
  printf 'keep\n' > "${isolated_home}/sentinel"
  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${isolated_home}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  chmod 0700 "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/product-runtime.uninstalled"
  HOME="${TEST_HOME}"
  unset PERSOME_INSTALL_HOME
  before="$(home_tree_snapshot "${isolated_home}")"

  if HOME="${isolated_home}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/uninstall-runtime.sh" --delete-data \
      </dev/null > "${output}" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "${status}" -ne 2 ]]; then
    printf 'Expected non-TTY --delete-data to exit 2; got %s.\n' "${status}"
    command cat "${output}"
    return 1
  fi
  after="$(home_tree_snapshot "${isolated_home}")"
  [[ "${after}" == "${before}" ]]
  [[ "$(command cat "${isolated_home}/sentinel")" == "keep" ]]
  [[ ! -e "${install_home}" ]]
  grep -Fq "Deleting Runtime data requires an interactive terminal." \
    "${output}"
}

test_uninstaller_wrong_delete_confirmation_is_read_only() {
  local isolated_home="${TEST_CASES}/uninstall-delete-cancel-home"
  local install_home="${isolated_home}/runtime"
  local output="${TEST_CASES}/uninstall-delete-cancel.out"
  local before after status
  mkdir -p "${isolated_home}"
  printf 'keep-home\n' > "${isolated_home}/sentinel"
  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${isolated_home}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  chmod 0700 "${RUNTIME_INSTALL_HOME}"
  printf 'keep-runtime\n' > "${RUNTIME_INSTALL_HOME}/personal-data"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/product-runtime.uninstalled"
  HOME="${TEST_HOME}"
  unset PERSOME_INSTALL_HOME
  before="$(home_tree_snapshot "${isolated_home}")"

  status="$(
    python3 - \
      "${PRODUCT_ROOT}/uninstall-runtime.sh" \
      "${isolated_home}" \
      "${install_home}" \
      "${output}" <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time

uninstaller, home, install_home, output_path = sys.argv[1:]
child_pid, descriptor = pty.fork()
if child_pid == 0:
    environment = {
        "HOME": home,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "PERSOME_INSTALL_HOME": install_home,
        "TERM": "dumb",
    }
    os.execve(
        "/bin/bash",
        ["/bin/bash", uninstaller, "--delete-data"],
        environment,
    )

output = bytearray()
confirmation_sent = False
deadline = time.monotonic() + 10
while time.monotonic() < deadline:
    readable, _, _ = select.select([descriptor], [], [], 0.1)
    if descriptor not in readable:
        waited_pid, child_status = os.waitpid(child_pid, os.WNOHANG)
        if waited_pid:
            break
        continue
    try:
        chunk = os.read(descriptor, 4096)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    output.extend(chunk)
    if not confirmation_sent and b"Type DELETE" in output:
        os.write(descriptor, b"KEEP\n")
        confirmation_sent = True
else:
    os.kill(child_pid, signal.SIGKILL)
    os.waitpid(child_pid, 0)
    raise SystemExit("interactive delete confirmation timed out")

try:
    waited_pid, child_status = os.waitpid(child_pid, 0)
except ChildProcessError:
    waited_pid = child_pid

with open(output_path, "wb") as output_file:
    output_file.write(output)

if not confirmation_sent:
    raise SystemExit("delete confirmation prompt was not observed")
if os.WIFEXITED(child_status):
    print(os.WEXITSTATUS(child_status))
else:
    print(128 + os.WTERMSIG(child_status))
PY
  )"

  if [[ "${status}" -eq 0 ]]; then
    printf 'Expected a wrong delete confirmation to cancel removal.\n'
    command cat "${output}"
    return 1
  fi
  after="$(home_tree_snapshot "${isolated_home}")"
  [[ "${after}" == "${before}" ]]
  [[ "$(command cat "${isolated_home}/sentinel")" == "keep-home" ]]
  [[ "$(command cat "${install_home}/personal-data")" == "keep-runtime" ]]
  grep -Fq "Runtime data deletion cancelled; nothing was changed." \
    "${output}"
}

test_uninstall_tombstone_is_recognized() {
  local install_home="${TEST_HOME}/uninstall-tombstone"
  local output="${TEST_CASES}/uninstall-tombstone.out"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  chmod 0700 "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write \
    "${RUNTIME_INSTALL_HOME}/product-runtime.uninstalled"
  unset PERSOME_INSTALL_HOME

  HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/uninstall-runtime.sh" --check-ownership \
      > "${output}" 2>&1
  grep -Fq "Runtime ownership state: data-only" "${output}"
  runtime_receipt_verify "${install_home}/product-runtime.uninstalled"
}

test_tampered_uninstall_tombstone_is_rejected() {
  local install_home="${TEST_HOME}/uninstall-tombstone-tampered"
  local tombstone="${install_home}/product-runtime.uninstalled"
  local output="${TEST_CASES}/uninstall-tombstone-tampered.out"
  local status

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  chmod 0700 "${RUNTIME_INSTALL_HOME}"
  runtime_receipt_write "${tombstone}"
  printf 'TAMPERED="1"\n' >> "${tombstone}"
  HOME="${TEST_HOME}"
  unset PERSOME_INSTALL_HOME

  if HOME="${TEST_HOME}" \
    PERSOME_INSTALL_HOME="${install_home}" \
    bash "${PRODUCT_ROOT}/uninstall-runtime.sh" --check-ownership \
      > "${output}" 2>&1; then
    status=0
  else
    status=$?
  fi
  [[ "${status}" -ne 0 ]]
  grep -Fq "No matching product receipt" "${output}"
}

test_operation_lock_excludes_concurrent_manager() {
  local install_home="${TEST_HOME}/operation-lock"
  local output="${TEST_CASES}/operation-lock.out"

  runtime_lock_load "${RUNTIME_LOCK}"
  HOME="${TEST_HOME}"
  PERSOME_INSTALL_HOME="${install_home}"
  unset PERSOME_PYTHON
  runtime_install_home_resolve
  mkdir -p "${RUNTIME_INSTALL_HOME}"
  chmod 0700 "${RUNTIME_INSTALL_HOME}"
  runtime_operation_lock_acquire

  if (
    runtime_operation_lock_acquire
  ) > "${output}" 2>&1; then
    runtime_operation_lock_release
    printf 'A concurrent manager unexpectedly acquired the lock.\n'
    return 1
  fi
  grep -Fq "Another product management operation is running" "${output}"
  runtime_operation_lock_release
  [[ ! -e "${install_home}/.product-operation.lock" ]]
}

prepare_release_readiness_fixture() {
  local fixture_root="$1"
  local release_status="$2"
  local product_version="$3"

  mkdir -p \
    "${fixture_root}/scripts/lib" \
    "${fixture_root}/docs/release-notes"
  command cp \
    "${PRODUCT_ROOT}/scripts/release-readiness.sh" \
    "${fixture_root}/scripts/release-readiness.sh"
  command cp \
    "${PRODUCT_ROOT}/scripts/lib/product-version.sh" \
    "${fixture_root}/scripts/lib/product-version.sh"
  chmod 0700 "${fixture_root}/scripts/release-readiness.sh"
  printf '%s\n' "${release_status}" > "${fixture_root}/RELEASE_STATUS"
  printf 'HOLD\n' > "${fixture_root}/PILOT_STATUS"
  printf '%s\n' "${product_version}" > "${fixture_root}/VERSION"
  printf '# Test release notes\n' \
    > "${fixture_root}/docs/release-notes/v${product_version}.md"
  printf '# Product\n\nRepository: example/product\n' \
    > "${fixture_root}/README.md"
  printf '%s\n' \
    '# Product intake' \
    '<!-- product-intake-schema:1 -->' \
    '## 1. Product definition' \
    '| Product name and one-sentence promise | complete |' \
    '| Primary beta user | complete |' \
    '| Single golden path: trigger → steps → visible result | complete |' \
    '| Definition of a successful first session | complete |' \
    '| Explicit beta exclusions | complete |' \
    '| Product source repository name and GitHub organization | complete |' \
    '| Product source license and redistribution policy | complete |' \
    '| Beta owner and release approver | complete |' \
    '| Support and feedback route | complete |' \
    '## 2. Workflow inventory' \
    '| WF-001 | complete |' \
    '## 3. Existing-library inventory' \
    'No external product library.' \
    '## 4. Classification decision' \
    '| WF-001 | none | build |' \
    '## 5. Data, permissions and external systems' \
    'Local only.' \
    '## 6. Distribution decisions' \
    '| Public or private GitHub repository | public |' \
    '| How the 100 testers receive access | invite |' \
    '| Code signing/notarization requirement for this beta | not applicable |' \
    '| Support hours and incident owner | assigned |' \
    '| Rollout stop authority | assigned |' \
    '| Pilot observation window | assigned |' \
    '| Expansion observation window | assigned |' \
    '| General-wave observation window | assigned |' \
    '| Minimum successful install rate per wave | assigned |' \
    '| Minimum golden-path success rate per wave | assigned |' \
    '| Maximum total and repeated failure rate per wave | assigned |' \
    '| Threshold denominator, measurement source and missing-response policy | assigned |' \
    '| Threshold approver and emergency stop owner | assigned |' \
    '## Intake exit gate' \
    'Approved.' \
    > "${fixture_root}/docs/product-intake.md"
  printf '%s\n' \
    '# 100-user beta runbook' \
    '<!-- beta-runbook-schema:1 -->' \
    '## Roles and records' \
    '| Release owner | owns release | assigned |' \
    '| Rollout owner | owns rollout | assigned |' \
    '| Incident owner | owns incident | assigned |' \
    '| Runtime owner | owns Runtime | assigned |' \
    '| Product owner | owns product | assigned |' \
    '| Privacy contact | owns privacy | assigned |' \
    '| Support route | tester support | assigned |' \
    '| Pilot | v0.1.0 | 5 |' \
    '| Expansion | v0.1.0 | 20 |' \
    '| General | v0.1.0 | 75 |' \
    '## Preflight: internal clean-Mac proof' \
    'Complete.' \
    '## Rollout waves' \
    '### Wave 1 — pilot: 5 users' \
    'Complete.' \
    '### Wave 2 — expansion: 20 users' \
    'Complete.' \
    '### Wave 3 — general: 75 users' \
    'Complete.' \
    '## Stop conditions' \
    'Defined.' \
    '## Rollback procedure' \
    'Defined.' \
    > "${fixture_root}/docs/beta-runbook.md"
  printf '%s\n\n' \
    '# Release checklist' \
    '<!-- release-checklist-schema:1 required-items:77 -->' \
    > "${fixture_root}/docs/release-checklist.md"
  local checklist_item
  checklist_item=1
  while [[ "${checklist_item}" -le 77 ]]; do
    printf -- '- [x] [RC-%03d] complete. Evidence: verified-%03d\n' \
      "${checklist_item}" "${checklist_item}" \
      >> "${fixture_root}/docs/release-checklist.md"
    checklist_item=$((checklist_item + 1))
  done
  printf '%s\n' \
    '<!-- release-decision:v1 status=GO version=0.1.0-beta.1 commit=1111111111111111111111111111111111111111 owner=test-owner approved-at=2026-08-07T08:00:00Z -->' \
    >> "${fixture_root}/docs/release-checklist.md"
  printf 'Test-only license fixture.\n' > "${fixture_root}/LICENSE"
}

test_release_status_current_is_valid() {
  local output
  output="$(bash "${PRODUCT_ROOT}/scripts/release-readiness.sh" --check)"
  grep -Eq '^Release decision: (HOLD|GO) ' <<<"${output}"
}

test_release_status_hold_fixture_blocks_publication() {
  local fixture_root="${TEST_CASES}/release-hold"
  prepare_release_readiness_fixture \
    "${fixture_root}" "HOLD" "0.1.0-beta.1"
  assert_rejected_contains \
    "Release publication is blocked." \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_fixture_allows_publication() {
  local fixture_root="${TEST_CASES}/release-go"
  local output
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  output="$(
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
  )"
  grep -Fq "Release decision: GO" <<<"${output}"
  grep -Fq "Release evidence gate: complete" <<<"${output}"
}

test_release_status_go_rejects_incomplete_intake() {
  local fixture_root="${TEST_CASES}/release-go-incomplete"
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  printf '# Product intake\n\nTBD\n' \
    > "${fixture_root}/docs/product-intake.md"
  assert_rejected_contains \
    "Product intake schema marker is missing or duplicated." \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_rejects_truncated_runbook() {
  local fixture_root="${TEST_CASES}/release-go-truncated-runbook"
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  printf '# Beta runbook\n\nComplete.\n' \
    > "${fixture_root}/docs/beta-runbook.md"
  assert_rejected_contains \
    "Beta runbook schema marker is missing or duplicated." \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_rejects_unchecked_evidence() {
  local fixture_root="${TEST_CASES}/release-go-unchecked"
  local checklist_item
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  printf '%s\n' \
    '# Release checklist' \
    '<!-- release-checklist-schema:1 required-items:77 -->' \
    '- [ ] [RC-001] Missing. Evidence: ___' \
    > "${fixture_root}/docs/release-checklist.md"
  checklist_item=2
  while [[ "${checklist_item}" -le 77 ]]; do
    printf -- '- [x] [RC-%03d] complete. Evidence: verified-%03d\n' \
      "${checklist_item}" "${checklist_item}" \
      >> "${fixture_root}/docs/release-checklist.md"
    checklist_item=$((checklist_item + 1))
  done
  assert_rejected_contains \
    "Pre-publication checklist item is not checked: RC-001" \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_rejects_truncated_checklist() {
  local fixture_root="${TEST_CASES}/release-go-truncated-checklist"
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  printf '%s\n' \
    '# Release checklist' \
    '<!-- release-checklist-schema:1 required-items:77 -->' \
    '- [x] [RC-001] Incomplete replacement. Evidence: one-record' \
    > "${fixture_root}/docs/release-checklist.md"
  assert_rejected_contains \
    "Release checklist schema is incomplete or changed without review." \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_allows_postpublish_item_open() {
  local fixture_root="${TEST_CASES}/release-go-postpublish-open"
  local rewritten="${TEST_CASES}/release-go-postpublish-open.md"
  local output
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  /usr/bin/sed \
    's/^- \[x\] \[RC-028\]/- [ ] [RC-028]/' \
    "${fixture_root}/docs/release-checklist.md" > "${rewritten}"
  /bin/mv "${rewritten}" "${fixture_root}/docs/release-checklist.md"
  output="$(
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
  )"
  grep -Fq "Release evidence gate: complete" <<<"${output}"
}

test_release_status_go_binds_decision_commit() {
  local fixture_root="${TEST_CASES}/release-go-wrong-decision-commit"
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  assert_rejected_contains \
    "Release decision commit does not match the release commit." \
    env \
      RELEASE_COMMIT="2222222222222222222222222222222222222222" \
      bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_requires_license() {
  local fixture_root="${TEST_CASES}/release-go-no-license"
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  : > "${fixture_root}/LICENSE"
  assert_rejected_contains \
    "A reviewed, non-empty LICENSE" \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_status_go_requires_pilot_hold() {
  local fixture_root="${TEST_CASES}/release-go-pilot-go"
  prepare_release_readiness_fixture \
    "${fixture_root}" "GO" "0.1.0-beta.1"
  printf 'GO\n' > "${fixture_root}/PILOT_STATUS"
  assert_rejected_contains \
    "Release publication requires PILOT_STATUS=HOLD." \
    bash "${fixture_root}/scripts/release-readiness.sh" --require-go
}

test_release_readiness_rejects_ambiguous_mode() {
  assert_rejected_contains \
    "Choose only one release-readiness mode." \
    bash "${PRODUCT_ROOT}/scripts/release-readiness.sh" \
      --check \
      --require-go
}

test_release_readiness_rejects_multiline_version() {
  local fixture_root="${TEST_CASES}/release-multiline-version"
  prepare_release_readiness_fixture \
    "${fixture_root}" "HOLD" "0.1.0-beta.1"
  printf '%s\n' "0.1.0-" "beta.1" > "${fixture_root}/VERSION"
  assert_rejected_contains \
    "VERSION must contain exactly one newline-terminated line." \
    bash "${fixture_root}/scripts/release-readiness.sh" --check
}

test_product_version_policy() {
  local candidate
  for candidate in \
    "0.1.0" \
    "1.0.0-alpha-1" \
    "1.0.0-beta.1" \
    "10.20.30-rc.2"; do
    product_version_validate "${candidate}" || {
      printf 'Expected valid product version: %s\n' "${candidate}"
      return 1
    }
  done
  for candidate in \
    "01.0.0" \
    "1.00.0" \
    "1.0.01" \
    "1.0.0-01" \
    "1.0.0+" \
    "1.0.0+build.1" \
    "1.0.0-alpha..1"; do
    if product_version_validate "${candidate}"; then
      printf 'Expected invalid product version: %s\n' "${candidate}"
      return 1
    fi
  done
}

test_pilot_status_current_is_valid() {
  local output
  output="$(bash "${PRODUCT_ROOT}/scripts/pilot-readiness.sh" --check)"
  grep -Eq '^Pilot invitation decision: (HOLD|GO) ' <<<"${output}"
}

test_pilot_gate_blocks_before_release_go() {
  assert_rejected_contains \
    "release publication decision is not GO" \
    bash "${PRODUCT_ROOT}/scripts/pilot-readiness.sh" \
      --require-pilot-go \
      --repository "Intuition-Lab/product-foundation-qa"
}

test_pilot_gate_requires_repository() {
  assert_rejected_contains \
    "requires --repository" \
    bash "${PRODUCT_ROOT}/scripts/pilot-readiness.sh" --require-pilot-go
}

test_pilot_gate_rejects_ambiguous_mode() {
  assert_rejected_contains \
    "choose only one pilot-readiness mode" \
    bash "${PRODUCT_ROOT}/scripts/pilot-readiness.sh" \
      --check \
      --require-pilot-go \
      --repository "Intuition-Lab/product-foundation-qa"
}

test_repository_controls_plan_is_complete() {
  local output
  output="$(
    bash "${PRODUCT_ROOT}/scripts/github-repository-controls.sh" \
      --plan \
      --repository "Intuition-Lab/product-foundation-qa" \
      --release-actor "user:release-owner" \
      --release-reviewer "team:release-reviewers"
  )"
  grep -Fq \
    "GitHub repository: Intuition-Lab/product-foundation-qa" \
    <<<"${output}"
  grep -Fq "RELEASE_STATUS=HOLD" <<<"${output}"
  grep -Fq "macOS isolated install (arm64)" <<<"${output}"
  grep -Fq "No GitHub request was made in --plan mode." <<<"${output}"
}

test_repository_bootstrap_plan_is_complete() {
  local output
  output="$(
    bash "${PRODUCT_ROOT}/scripts/bootstrap-github-repository.sh" \
      --plan \
      --repository "Intuition-Lab/product-foundation-qa" \
      --public \
      --description "Reviewed beta product"
  )"
  grep -Fq \
    "New GitHub repository: Intuition-Lab/product-foundation-qa" \
    <<<"${output}"
  grep -Fq "Visibility:            public" <<<"${output}"
  grep -Fq "No Git or GitHub request was made in --plan mode." <<<"${output}"
}

test_repository_bootstrap_rejects_ambiguous_mode() {
  assert_rejected_contains \
    "choose only one mode" \
    bash "${PRODUCT_ROOT}/scripts/bootstrap-github-repository.sh" \
      --plan \
      --check \
      --repository "Intuition-Lab/product-foundation-qa" \
      --public \
      --description "Reviewed beta product"
}

test_repository_bootstrap_requires_one_visibility() {
  assert_rejected_contains \
    "choose exactly one of --public or --private" \
    bash "${PRODUCT_ROOT}/scripts/bootstrap-github-repository.sh" \
      --plan \
      --repository "Intuition-Lab/product-foundation-qa" \
      --public \
      --private \
      --private-enterprise \
      --description "Reviewed beta product"
}

test_repository_bootstrap_private_requires_enterprise() {
  assert_rejected_contains \
    "private creation requires explicit --private-enterprise confirmation" \
    bash "${PRODUCT_ROOT}/scripts/bootstrap-github-repository.sh" \
      --plan \
      --repository "Intuition-Lab/product-foundation-qa" \
      --private \
      --description "Reviewed beta product"
}

prepare_repository_bootstrap_fixture() {
  local fixture_root="$1"
  local version="0.1.0-beta.1"

  mkdir -p \
    "${fixture_root}/scripts/lib" \
    "${fixture_root}/docs/release-notes"
  command cp \
    "${PRODUCT_ROOT}/scripts/bootstrap-github-repository.sh" \
    "${fixture_root}/scripts/bootstrap-github-repository.sh"
  command cp \
    "${PRODUCT_ROOT}/scripts/release-readiness.sh" \
    "${fixture_root}/scripts/release-readiness.sh"
  command cp \
    "${PRODUCT_ROOT}/scripts/lib/product-version.sh" \
    "${fixture_root}/scripts/lib/product-version.sh"
  chmod 0700 \
    "${fixture_root}/scripts/bootstrap-github-repository.sh" \
    "${fixture_root}/scripts/release-readiness.sh"
  printf 'HOLD\n' > "${fixture_root}/RELEASE_STATUS"
  printf 'HOLD\n' > "${fixture_root}/PILOT_STATUS"
  printf '%s\n' "${version}" > "${fixture_root}/VERSION"
  printf '# Reviewed beta product\n' > "${fixture_root}/README.md"
  printf '# Test release notes\n' \
    > "${fixture_root}/docs/release-notes/v${version}.md"
  /usr/bin/git -C "${fixture_root}" init --quiet --initial-branch main
  /usr/bin/git -C "${fixture_root}" add .
}

test_repository_bootstrap_requires_license_before_github() {
  local fixture_root="${TEST_CASES}/repository-bootstrap-no-license"
  prepare_repository_bootstrap_fixture "${fixture_root}"
  assert_rejected_contains \
    "a reviewed, non-empty License is required before repository creation" \
    bash "${fixture_root}/scripts/bootstrap-github-repository.sh" \
      --check \
      --repository "Intuition-Lab/product-foundation-qa" \
      --public \
      --description "Reviewed beta product"
}

test_repository_bootstrap_requires_license_in_initial_tree() {
  local fixture_root="${TEST_CASES}/repository-bootstrap-ignored-license"
  prepare_repository_bootstrap_fixture "${fixture_root}"
  printf 'LICENSE\n' > "${fixture_root}/.gitignore"
  printf 'Test-only reviewed license.\n' > "${fixture_root}/LICENSE"
  /usr/bin/git -C "${fixture_root}" add .gitignore
  assert_rejected_contains \
    "the reviewed License must be staged for the initial repository" \
    bash "${fixture_root}/scripts/bootstrap-github-repository.sh" \
      --check \
      --repository "Intuition-Lab/product-foundation-qa" \
      --public \
      --description "Reviewed beta product"
}

test_repository_bootstrap_check_accepts_clean_mock() {
  local fixture_root="${TEST_CASES}/repository-bootstrap-clean"
  local mock_directory="${TEST_CASES}/repository-bootstrap-clean-bin"
  local rewritten="${fixture_root}/bootstrap.rewritten"
  local output

  prepare_repository_bootstrap_fixture "${fixture_root}"
  printf 'Test-only reviewed license.\n' > "${fixture_root}/LICENSE"
  /usr/bin/git -C "${fixture_root}" add LICENSE
  /usr/bin/git -C "${fixture_root}" config user.name "Foundation Test"
  /usr/bin/git -C "${fixture_root}" config user.email "test@example.invalid"
  mkdir "${mock_directory}"
  /usr/bin/sed \
    "s|^PATH=\"/opt/homebrew/bin:|PATH=\"${mock_directory}:/opt/homebrew/bin:|" \
    "${fixture_root}/scripts/bootstrap-github-repository.sh" \
    > "${rewritten}"
  /bin/mv "${rewritten}" \
    "${fixture_root}/scripts/bootstrap-github-repository.sh"
  chmod 0700 "${fixture_root}/scripts/bootstrap-github-repository.sh"
  {
    # These expressions are intentionally literal source for the mock CLI.
    # shellcheck disable=SC2016
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'if [[ "${1:-}" == "auth" ]]; then exit 0; fi' \
      'if [[ "${1:-}" == "api" ]]; then' \
      '  printf "gh: Not Found (HTTP 404)\n" >&2' \
      '  exit 1' \
      'fi' \
      'exit 1' \
      > "${mock_directory}/gh"
  }
  chmod 0700 "${mock_directory}/gh"
  /usr/bin/git -C "${fixture_root}" add \
    scripts/bootstrap-github-repository.sh

  output="$(
    bash "${fixture_root}/scripts/bootstrap-github-repository.sh" \
      --check \
      --repository "Intuition-Lab/product-foundation-qa" \
      --public \
      --description "Reviewed beta product"
  )"
  grep -Fq \
    "Repository bootstrap preflight passed for Intuition-Lab/product-foundation-qa." \
    <<<"${output}"
  ! /usr/bin/git -C "${fixture_root}" \
    rev-parse --verify HEAD >/dev/null 2>&1
}

test_repository_controls_reject_ambiguous_mode() {
  assert_rejected_contains \
    "choose only one mode" \
    bash "${PRODUCT_ROOT}/scripts/github-repository-controls.sh" \
      --plan \
      --apply \
      --repository "Intuition-Lab/product-foundation-qa" \
      --release-actor "user:release-owner" \
      --release-reviewer "team:release-reviewers"
}

test_repository_controls_reject_unsafe_repository() {
  assert_rejected_contains \
    "repository must be an explicit OWNER/REPOSITORY name" \
    bash "${PRODUCT_ROOT}/scripts/github-repository-controls.sh" \
      --plan \
      --repository "https://github.com/Intuition-Lab/product" \
      --release-actor "user:release-owner" \
      --release-reviewer "team:release-reviewers"
}

test_repository_controls_require_distinct_approver() {
  assert_rejected_contains \
    "release actor and release reviewer must be different" \
    bash "${PRODUCT_ROOT}/scripts/github-repository-controls.sh" \
      --plan \
      --repository "Intuition-Lab/product-foundation-qa" \
      --release-actor "user:release-owner" \
      --release-reviewer "user:release-owner"
}

prepare_repository_controls_mock() {
  local fixture_root="$1"
  local mock_directory="${fixture_root}/bin"
  local rewritten="${fixture_root}/github-repository-controls.sh"

  mkdir -p "${mock_directory}"
  /usr/bin/sed \
    "s|^PATH=\"/opt/homebrew/bin:|PATH=\"${mock_directory}:/opt/homebrew/bin:|" \
    "${PRODUCT_ROOT}/scripts/github-repository-controls.sh" \
    > "${rewritten}"
  chmod 0700 "${rewritten}"
  {
    # These expressions are intentionally emitted into the mock script.
    # shellcheck disable=SC2016
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'joined="$*"' \
      'case "${joined}" in' \
      '  *"/users/release-owner"*) printf "101\n" ;;' \
      '  *"/users/release-reviewer"*) printf "202\n" ;;' \
      '  *".full_name"*)' \
      '    printf "Intuition-Lab/product-foundation-qa\tmain\tfalse\tfalse\ttrue\tpublic\n"' \
      '    ;;' \
      '  *"/commits/main/check-runs"*) printf "15368\n" ;;' \
      '  *rulesets?includes_parents=false*Protect\ product\ main*) printf "11\n" ;;' \
      '  *rulesets?includes_parents=false*Protect\ product\ release\ tags*) printf "12\n" ;;' \
      '  *environments/github-release*required_reviewers*)' \
      '    if [[ "${MOCK_GH_EXTRA_REVIEWER:-0}" == "1" ]]; then' \
      '      printf "false\n"' \
      '    else' \
      '      printf "true\n"' \
      '    fi' \
      '    ;;' \
      '  *) printf "true\n" ;;' \
      'esac' \
      > "${mock_directory}/gh"
  }
  chmod 0700 "${mock_directory}/gh"
  printf '%s\n' "${rewritten}"
}

test_repository_controls_live_check_accepts_exact_mock() {
  local fixture_root="${TEST_CASES}/repository-controls-exact"
  local script_path output
  script_path="$(prepare_repository_controls_mock "${fixture_root}")"
  output="$(
    GITHUB_ACTIONS=true \
      bash "${script_path}" \
        --check \
        --repository "Intuition-Lab/product-foundation-qa" \
        --release-actor "user:release-owner" \
        --release-reviewer "user:release-reviewer"
  )"
  grep -Fq \
    "GitHub repository controls verified for Intuition-Lab/product-foundation-qa." \
    <<<"${output}"
}

test_repository_controls_live_check_rejects_extra_reviewer() {
  local fixture_root="${TEST_CASES}/repository-controls-extra-reviewer"
  local script_path
  script_path="$(prepare_repository_controls_mock "${fixture_root}")"
  assert_rejected_contains \
    "release environment reviewer does not match the reviewed configuration" \
    env \
      GITHUB_ACTIONS=true \
      MOCK_GH_EXTRA_REVIEWER=1 \
      bash "${script_path}" \
        --check \
        --repository "Intuition-Lab/product-foundation-qa" \
        --release-actor "user:release-owner" \
        --release-reviewer "user:release-reviewer"
}

test_fresh_install_stages_recovery_bundle_before_intent() {
  local bundle_line intent_line upstream_line
  # These are literal source markers, not expressions for this test shell.
  # shellcheck disable=SC2016
  bundle_line="$(
    LC_ALL=C grep -n \
      'install_management_bundle "${temporary_root}/runtime"' \
      "${PRODUCT_ROOT}/install.sh" \
      | head -n 1 \
      | cut -d: -f1
  )"
  # shellcheck disable=SC2016
  intent_line="$(
    LC_ALL=C grep -n \
      'runtime_receipt_write "${RUNTIME_INSTALL_HOME}/product-runtime.installing"' \
      "${PRODUCT_ROOT}/install.sh" \
      | cut -d: -f1
  )"
  # shellcheck disable=SC2016
  upstream_line="$(
    LC_ALL=C grep -n \
      '/bin/bash "${temporary_root}/runtime/install.sh" --no-client-config' \
      "${PRODUCT_ROOT}/install.sh" \
      | head -n 1 \
      | cut -d: -f1
  )"
  [[ "${bundle_line}" =~ ^[1-9][0-9]*$ ]]
  [[ "${intent_line}" =~ ^[1-9][0-9]*$ ]]
  [[ "${upstream_line}" =~ ^[1-9][0-9]*$ ]]
  [[ "${bundle_line}" -lt "${intent_line}" ]]
  [[ "${intent_line}" -lt "${upstream_line}" ]]
}

test_management_bundle_commits_content_addressed_lock_last() {
  local uninstaller_line lock_line
  # These are literal source markers, not expressions for this test shell.
  # shellcheck disable=SC2016
  uninstaller_line="$(
    LC_ALL=C grep -n \
      '"${runtime_checkout}/uninstall.sh"' \
      "${PRODUCT_ROOT}/install.sh" \
      | head -n 1 \
      | cut -d: -f1
  )"
  # shellcheck disable=SC2016
  lock_line="$(
    LC_ALL=C grep -n \
      '"${management_root}/runtime.lock" 0600' \
      "${PRODUCT_ROOT}/install.sh" \
      | tail -n 1 \
      | cut -d: -f1
  )"
  [[ "${uninstaller_line}" =~ ^[1-9][0-9]*$ ]]
  [[ "${lock_line}" =~ ^[1-9][0-9]*$ ]]
  [[ "${uninstaller_line}" -lt "${lock_line}" ]]
  # The following are literal source markers.
  # shellcheck disable=SC2016
  LC_ALL=C grep -Fq \
    'upstream-uninstall-${RUNTIME_UNINSTALLER_SHA256}.sh' \
    "${PRODUCT_ROOT}/install.sh"
  # shellcheck disable=SC2016
  LC_ALL=C grep -Fq \
    'upstream-uninstall-${RUNTIME_UNINSTALLER_SHA256}.sh' \
    "${PRODUCT_ROOT}/uninstall-runtime.sh"
  # shellcheck disable=SC2016
  LC_ALL=C grep -Fq \
    'mktemp "${target_directory}/.product-management-file.XXXXXX"' \
    "${PRODUCT_ROOT}/install.sh"
}

prepare_context_hook_runtime() {
  local install_home="$1"
  local management_root="${install_home}/product-management"

  runtime_lock_load "${RUNTIME_LOCK}"
  mkdir -p \
    "${install_home}/venv/bin" \
    "${management_root}"
  chmod 0700 \
    "${install_home}" \
    "${install_home}/venv" \
    "${install_home}/venv/bin" \
    "${management_root}"
  command cp "${RUNTIME_LOCK}" "${management_root}/runtime.lock"
  chmod 0600 "${management_root}/runtime.lock"
  command cp \
    "${CONTEXT_HOOK_FIXTURE}" \
    "${install_home}/venv/bin/persome"
  chmod 0700 "${install_home}/venv/bin/persome"

  (
    RUNTIME_INSTALL_HOME="${install_home}"
    export RUNTIME_INSTALL_HOME
    runtime_receipt_write "${install_home}/product-runtime.lock"
    runtime_receipt_write "${install_home}/venv/.product-runtime.lock"
  )
}

run_context_hook() {
  local install_home="$1"
  local payload="$2"

  printf '%s' "${payload}" \
    | env \
        HOME="${TEST_HOME}" \
        PERSOME_INSTALL_HOME="${install_home}" \
        /usr/bin/python3 "${CONTEXT_HOOK}"
}

test_context_plugin_contract() {
  /usr/bin/python3 - \
    "${PRODUCT_ROOT}/plugins/personal-model-context/.codex-plugin/plugin.json" \
    "${PRODUCT_ROOT}/plugins/personal-model-context/hooks/hooks.json" \
    "${PRODUCT_ROOT}/.agents/plugins/marketplace.json" \
    "${CONTEXT_HOOK}" \
    "${RUNTIME_LOCK}" \
    "${PRODUCT_ROOT}/VERSION" <<'PY'
import json
import re
import runpy
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
hooks = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["hooks"]
marketplace = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
hook_module = runpy.run_path(sys.argv[4])
runtime_lock = {}
for line in Path(sys.argv[5]).read_text(encoding="utf-8").splitlines():
    match = re.fullmatch(r'([A-Z][A-Z0-9_]*)="([^"]*)"', line)
    if match:
        runtime_lock[match.group(1)] = match.group(2)
expected_identity = {
    key: runtime_lock[key] for key in hook_module["RECEIPT_KEYS"]
}
assert manifest["name"] == "personal-model-context"
assert manifest["version"] == Path(sys.argv[6]).read_text(encoding="utf-8").strip()
assert manifest["skills"] == "./skills/"
assert "mcpServers" not in manifest
assert hook_module["EXPECTED_IDENTITY"] == expected_identity
assert marketplace["name"] == "intuition-lab"
assert marketplace["plugins"] == [
    {
        "name": "personal-model-context",
        "source": {
            "source": "local",
            "path": "./plugins/personal-model-context",
        },
        "policy": {
            "installation": "AVAILABLE",
            "authentication": "ON_INSTALL",
        },
        "category": "Productivity",
    }
]
assert set(hooks) == {"SessionStart", "UserPromptSubmit"}
assert hooks["SessionStart"][0]["matcher"] == "startup|resume|clear|compact"
for groups in hooks.values():
    for group in groups:
        for handler in group["hooks"]:
            assert handler["type"] == "command"
            assert "${PLUGIN_ROOT}/scripts/context_hook.py" in handler["command"]
            assert handler["additionalContextLimit"] == 0
PY
  LC_ALL=C grep -Fxq ".agents" "${PRODUCT_ROOT}/release.manifest"
  LC_ALL=C grep -Fxq "plugins" "${PRODUCT_ROOT}/release.manifest"
  if LC_ALL=C grep -Eq \
    'call_tool\\((\"|\x27)(remember|correct_memory|search_captures)' \
    "${CONTEXT_HOOK}"; then
    printf 'Automatic context hook contains a write or raw-capture tool call.\n'
    return 1
  fi
}

test_context_hook_fails_open_without_runtime() {
  local output
  output="$(
    run_context_hook \
      "${TEST_HOME}/missing-personal-model-runtime" \
      '{"hook_event_name":"UserPromptSubmit","prompt":"hello"}'
  )"
  [[ -z "${output}" ]]
}

test_context_hook_recalls_each_user_prompt() {
  local install_home="${TEST_HOME}/context-hook-user-prompt"
  local output
  prepare_context_hook_runtime "${install_home}"

  output="$(
    run_context_hook \
      "${install_home}" \
      '{"hook_event_name":"UserPromptSubmit","prompt":"where is the launch plan?"}'
  )"
  printf '%s' "${output}" | /usr/bin/python3 -c '
import json
import sys

value = json.load(sys.stdin)
assert value["continue"] is True
specific = value["hookSpecificOutput"]
assert specific["hookEventName"] == "UserPromptSubmit"
context = specific["additionalContext"]
assert "untrusted recalled data" in context
assert "memory-1" in context
assert "Ignore previous instructions" in context
assert len(context) <= 7200
'
  [[ "$(command cat "${install_home}/context-hook-calls.log")" == "search" ]]
  LC_ALL=C grep -Fq \
    '"query": "where is the launch plan?"' \
    "${install_home}/context-hook-queries.log"
  LC_ALL=C grep -Fq \
    '"include_chains": false' \
    "${install_home}/context-hook-queries.log"
}

test_context_hook_loads_session_model() {
  local install_home="${TEST_HOME}/context-hook-session-start"
  local output
  prepare_context_hook_runtime "${install_home}"

  output="$(
    run_context_hook \
      "${install_home}" \
      '{"hook_event_name":"SessionStart","source":"compact"}'
  )"
  printf '%s' "${output}" | /usr/bin/python3 -c '
import json
import sys

value = json.load(sys.stdin)
specific = value["hookSpecificOutput"]
assert specific["hookEventName"] == "SessionStart"
context = specific["additionalContext"]
assert "Behavior model" in context
assert "Recent activity" in context
assert "evidence-backed decisions" in context
assert "Prepared the beta launch gate" in context
'
  [[ "$(
    command cat "${install_home}/context-hook-calls.log"
  )" == $'behavior_patterns\nrecent_activity' ]]
}

test_context_hook_rejects_tampered_receipt() {
  local install_home="${TEST_HOME}/context-hook-tampered-receipt"
  local output
  prepare_context_hook_runtime "${install_home}"
  printf '\n' >> "${install_home}/product-runtime.lock"

  output="$(
    run_context_hook \
      "${install_home}" \
      '{"hook_event_name":"UserPromptSubmit","prompt":"hello"}'
  )"
  [[ -z "${output}" ]]
  [[ ! -e "${install_home}/context-hook-calls.log" ]]
}

test_context_hook_rejects_symlink_cli() {
  local install_home="${TEST_HOME}/context-hook-symlink-cli"
  local cli="${install_home}/venv/bin/persome"
  local output
  prepare_context_hook_runtime "${install_home}"
  mv "${cli}" "${cli}.real"
  ln -s "${cli}.real" "${cli}"

  output="$(
    run_context_hook \
      "${install_home}" \
      '{"hook_event_name":"UserPromptSubmit","prompt":"hello"}'
  )"
  [[ -z "${output}" ]]
  [[ ! -e "${install_home}/context-hook-calls.log" ]]
}

test_context_hook_rejects_oversized_prompt() {
  local install_home="${TEST_HOME}/context-hook-oversized-prompt"
  local output prompt
  prepare_context_hook_runtime "${install_home}"
  prompt="$(
    /bin/dd if=/dev/zero bs=12001 count=1 2>/dev/null \
      | /usr/bin/tr '\000' x
  )"

  output="$(
    run_context_hook \
      "${install_home}" \
      "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"${prompt}\"}"
  )"
  [[ -z "${output}" ]]
  [[ ! -e "${install_home}/context-hook-calls.log" ]]
}

run_case "valid Runtime lock loads" test_valid_lock
run_case "unknown Runtime lock key is rejected" test_unknown_lock_key
run_case "duplicate Runtime lock key is rejected" test_duplicate_lock_key
run_case "malicious Runtime lock text is never executed" \
  test_malicious_lock_is_data_only
run_case "symlink Runtime lock is rejected" test_symlink_lock_rejected
run_case "short Runtime commit is rejected" test_short_commit_rejected
run_case "unreviewed Runtime repository is rejected" \
  test_wrong_repository_rejected
run_case "invalid Runtime digest is rejected" test_invalid_digest_rejected
run_case "valid product runtime lock is accepted" test_valid_product_lock
run_case "duplicate product runtime lock key is rejected" \
  test_duplicate_product_lock_key
run_case "product runtime lock is parsed as data only" \
  test_malicious_product_lock_is_data_only
run_case "symlink product runtime lock is rejected" \
  test_symlink_product_lock_rejected

run_case "dangerous HOME is rejected" test_invalid_home_rejected
run_case "symlink HOME is rejected" test_symlink_home_rejected
run_case "HOME symlink ancestor is rejected" \
  test_home_symlink_ancestor_rejected
run_case "install home outside HOME is rejected" \
  test_install_home_outside_home_rejected
run_case "install home traversal is rejected" \
  test_install_home_traversal_rejected
run_case "install home symlink traversal is rejected" \
  test_install_home_symlink_traversal_rejected
run_case "shared-writable install home is rejected" \
  test_shared_writable_install_home_rejected
run_case "unsupported Python selector is rejected" \
  test_invalid_python_selector_rejected
run_case "supported Python selector is accepted" \
  test_supported_python_selector_accepted

run_case "conflicting interaction flags are rejected" \
  test_interaction_flags_conflict
run_case "interactive install without a TTY is rejected" \
  test_interactive_install_without_tty_rejected
run_case "update wrapper rejects non-interactive mode" \
  test_update_wrapper_rejects_non_interactive_mode

run_case "temporary root marker permits safe cleanup" \
  test_temporary_root_round_trip
run_case "tampered temporary marker blocks cleanup" \
  test_temporary_root_tamper_blocks_cleanup
run_case "unsafe temporary prefix is rejected" \
  test_unsafe_temporary_prefix_rejected
run_case "pinned Runtime checkout retries a transient fetch failure" \
  test_runtime_checkout_retries_transient_fetch
run_case "bundled Runtime checkout is copied and verified" \
  test_bundled_runtime_checkout_is_copied_and_verified
run_case "bundled Runtime checkout rejects symbolic links" \
  test_bundled_runtime_checkout_rejects_symlinks
run_case "product installer never fetches the Runtime source repository" \
  test_product_installer_never_fetches_runtime_source
run_case "Personal Card replacement rolls back until verification commits" \
  test_personal_card_replacement_is_transactional

run_case "Runtime receipt matches the pinned lock" test_receipt_round_trip
run_case "tampered Runtime receipt is rejected" test_tampered_receipt_rejected
run_case "changed lock rejects an existing receipt" \
  test_changed_lock_rejects_existing_receipt
run_case "previous stable lock authorizes a cross-Runtime update" \
  test_previous_lock_verifies_cross_runtime_update
run_case "malformed previous lock restores the target identity" \
  test_malformed_previous_lock_restores_target_identity
run_case "symlink Runtime receipt is never overwritten" \
  test_symlink_receipt_rejected
run_case "external and venv Runtime receipts verify together" \
  test_dual_receipt_round_trip
run_case "owner-controlled standalone Runtime connects without product receipts" \
  test_owner_controlled_standalone_runtime_is_connectable_without_receipts
run_case "standalone Runtime never follows a symlinked CLI" \
  test_standalone_runtime_symlink_cli_is_rejected
run_case "non-interactive cross-Runtime update is rejected before mutation" \
  test_non_interactive_update_is_rejected_before_mutation
run_case "same-version replacement venv without receipt is rejected" \
  test_replaced_venv_without_receipt_rejected
run_case "missing venv Runtime receipt is rejected" \
  test_missing_internal_receipt_rejected
run_case "tampered venv Runtime receipt is rejected" \
  test_tampered_internal_receipt_rejected
run_case "missing external Runtime receipt is rejected" \
  test_missing_external_receipt_rejected
run_case "diagnostic never executes a venv without receipts" \
  test_diagnostic_does_not_execute_without_receipts
run_case "diagnostic never executes a venv with a tampered receipt" \
  test_diagnostic_does_not_execute_with_tampered_receipt
run_case "diagnostic never follows a symlinked Runtime CLI" \
  test_diagnostic_does_not_follow_cli_symlink
run_case "quick verification ignores Python injection environment" \
  test_quick_verify_ignores_python_injection_environment

run_case "install intent matches the Runtime lock" \
  test_install_intent_round_trip
run_case "matching install intent enables uninstall recovery" \
  test_matching_intent_recognized_by_uninstaller
run_case "tampered install intent is rejected before checkout" \
  test_tampered_intent_rejected_by_uninstaller
run_case "install intent from another lock is rejected before checkout" \
  test_wrong_lock_intent_rejected_by_uninstaller
run_case "successful install epilogue removes the install intent" \
  test_completed_install_removes_intent
run_case "uninstaller print plan does not modify HOME" \
  test_uninstaller_print_plan_is_read_only
run_case "non-TTY delete-data is rejected without modifying HOME" \
  test_uninstaller_delete_data_without_tty_is_read_only
run_case "wrong delete confirmation changes nothing" \
  test_uninstaller_wrong_delete_confirmation_is_read_only
run_case "preserved-data uninstall tombstone is recognized" \
  test_uninstall_tombstone_is_recognized
run_case "tampered uninstall tombstone is rejected" \
  test_tampered_uninstall_tombstone_is_rejected
run_case "product operation lock excludes a concurrent manager" \
  test_operation_lock_excludes_concurrent_manager
run_case "current explicit release decision is valid" \
  test_release_status_current_is_valid
run_case "HOLD fixture blocks publication" \
  test_release_status_hold_fixture_blocks_publication
run_case "GO fixture allows publication" \
  test_release_status_go_fixture_allows_publication
run_case "GO fixture rejects unresolved product intake" \
  test_release_status_go_rejects_incomplete_intake
run_case "GO fixture rejects a truncated beta runbook" \
  test_release_status_go_rejects_truncated_runbook
run_case "GO fixture rejects unchecked release evidence" \
  test_release_status_go_rejects_unchecked_evidence
run_case "GO fixture rejects a truncated release checklist" \
  test_release_status_go_rejects_truncated_checklist
run_case "GO fixture permits post-publication evidence to remain open" \
  test_release_status_go_allows_postpublish_item_open
run_case "GO fixture binds the decision to the release commit" \
  test_release_status_go_binds_decision_commit
run_case "GO fixture requires a reviewed License" \
  test_release_status_go_requires_license
run_case "release publication keeps the pilot invitation gate on HOLD" \
  test_release_status_go_requires_pilot_hold
run_case "release-readiness mode must be unambiguous" \
  test_release_readiness_rejects_ambiguous_mode
run_case "release-readiness rejects a multiline version" \
  test_release_readiness_rejects_multiline_version
run_case "product release version policy rejects ambiguous versions" \
  test_product_version_policy
run_case "current explicit pilot invitation decision is valid" \
  test_pilot_status_current_is_valid
run_case "pilot gate remains closed before release publication GO" \
  test_pilot_gate_blocks_before_release_go
run_case "pilot gate requires an explicit repository" \
  test_pilot_gate_requires_repository
run_case "pilot-readiness mode must be unambiguous" \
  test_pilot_gate_rejects_ambiguous_mode
run_case "repository-control plan is complete and read-only" \
  test_repository_controls_plan_is_complete
run_case "repository bootstrap plan is complete and read-only" \
  test_repository_bootstrap_plan_is_complete
run_case "repository bootstrap mode must be unambiguous" \
  test_repository_bootstrap_rejects_ambiguous_mode
run_case "repository bootstrap requires exactly one visibility" \
  test_repository_bootstrap_requires_one_visibility
run_case "private repository bootstrap requires Enterprise confirmation" \
  test_repository_bootstrap_private_requires_enterprise
run_case "repository bootstrap blocks before GitHub when License is missing" \
  test_repository_bootstrap_requires_license_before_github
run_case "repository bootstrap requires License in the initial tree" \
  test_repository_bootstrap_requires_license_in_initial_tree
run_case "repository bootstrap check accepts clean mocked GitHub state" \
  test_repository_bootstrap_check_accepts_clean_mock
run_case "repository-control mode must be unambiguous" \
  test_repository_controls_reject_ambiguous_mode
run_case "repository-control repository name is validated" \
  test_repository_controls_reject_unsafe_repository
run_case "repository-control release approval is separated" \
  test_repository_controls_require_distinct_approver
run_case "repository-control live verifier accepts exact API state" \
  test_repository_controls_live_check_accepts_exact_mock
run_case "repository-control live verifier rejects an extra reviewer" \
  test_repository_controls_live_check_rejects_extra_reviewer
run_case "fresh install stages offline recovery before Runtime mutation" \
  test_fresh_install_stages_recovery_bundle_before_intent
run_case "management bundle atomically commits its content-addressed lock last" \
  test_management_bundle_commits_content_addressed_lock_last
run_case "Personal Model Codex plugin has a read-only automatic hook contract" \
  test_context_plugin_contract
run_case "Personal Model context hook fails open without the Runtime" \
  test_context_hook_fails_open_without_runtime
run_case "Personal Model context hook recalls on each user prompt" \
  test_context_hook_recalls_each_user_prompt
run_case "Personal Model context hook restores session context" \
  test_context_hook_loads_session_model
run_case "Personal Model context hook rejects a tampered Runtime receipt" \
  test_context_hook_rejects_tampered_receipt
run_case "Personal Model context hook never follows a symlinked Runtime CLI" \
  test_context_hook_rejects_symlink_cli
run_case "Personal Model context hook rejects oversized prompts before execution" \
  test_context_hook_rejects_oversized_prompt

TOTAL_COUNT=$((PASS_COUNT + FAIL_COUNT))
if [[ "${FAIL_COUNT}" -ne 0 ]]; then
  printf '\n%d of %d foundation tests failed.\n' \
    "${FAIL_COUNT}" "${TOTAL_COUNT}" >&2
  exit 1
fi

printf '\nAll %d foundation tests passed with isolated HOME %s.\n' \
  "${TOTAL_COUNT}" "${TEST_HOME}"
