#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"
# shellcheck source=scripts/lib/product-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/product-lock.sh"

MODE="install"
INTERACTION_MODE="auto"

usage() {
  cat <<'EOF'
Usage: bash install.sh [option]

Install the reviewed Personal Model Runtime used by this product.

Options:
  --check          Check this Mac's prerequisites without changing anything.
  --print-plan     Print the pinned source and installation plan.
  --interactive    Require an interactive terminal and complete onboarding.
  --non-interactive
                   Install without prompts; onboarding remains pending.
  -h, --help       Show this help.

The interactive install explains and requests macOS Accessibility and Screen
Recording permissions. Runtime data remains under ~/.persome by default.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      MODE="check"
      shift
      ;;
    --print-plan)
      MODE="plan"
      shift
      ;;
    --interactive)
      if [[ "${INTERACTION_MODE}" == "non-interactive" ]]; then
        printf 'Choose only one interaction mode.\n' >&2
        exit 2
      fi
      INTERACTION_MODE="interactive"
      shift
      ;;
    --non-interactive)
      if [[ "${INTERACTION_MODE}" == "interactive" ]]; then
        printf 'Choose only one interaction mode.\n' >&2
        exit 2
      fi
      INTERACTION_MODE="non-interactive"
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

TARGET_RUNTIME_LOCK="${PRODUCT_ROOT}/runtime.lock"
runtime_lock_load "${TARGET_RUNTIME_LOCK}"
product_lock_load "${PRODUCT_ROOT}/product.lock"
runtime_install_home_resolve
BUNDLED_RUNTIME_ROOT="${WHOAMI_BUNDLED_RUNTIME_ROOT:-${PRODUCT_ROOT}/runtime-source}"

resolve_interaction_mode() {
  if [[ "${INTERACTION_MODE}" == "auto" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      INTERACTION_MODE="interactive"
    else
      INTERACTION_MODE="non-interactive"
    fi
  fi
  if [[ "${MODE}" == "install" && "${INTERACTION_MODE}" == "interactive" \
    && ( ! -t 0 || ! -t 1 ) ]]; then
    printf '%s\n' \
      'Interactive installation requires terminal input and output.' \
      'Use --non-interactive in automation.' >&2
    return 1
  fi
}

resolve_interaction_mode

installer_test_failpoint() {
  local phase="$1"
  local requested_phase="${PRODUCT_FOUNDATION_TEST_FAIL_PHASE:-}"

  [[ -n "${requested_phase}" ]] || return 0
  if [[ "${PRODUCT_FOUNDATION_TESTING:-0}" != "1" ]]; then
    printf 'Installer test failpoints are disabled outside foundation testing.\n' \
      >&2
    return 2
  fi
  case "${requested_phase}" in
    after-upstream-before-receipts|after-card-before-verification) ;;
    *)
      printf 'Unknown installer test failpoint: %s\n' "${requested_phase}" >&2
      return 2
      ;;
  esac
  if [[ "${requested_phase}" == "${phase}" ]]; then
    printf 'Foundation test failpoint reached: %s\n' "${phase}" >&2
    return 86
  fi
}

PERSONAL_CARD_TRANSACTION_ACTIVE=0
PERSONAL_CARD_TARGET_ROOT=""
PERSONAL_CARD_PREVIOUS_TARGET_ROOT=""
PERSONAL_CARD_APP_BUNDLE=""
PERSONAL_CARD_PREVIOUS_APP_BUNDLE=""

personal_card_transaction_rollback() {
  [[ "${PERSONAL_CARD_TRANSACTION_ACTIVE:-0}" -eq 1 ]] || return 0
  local failed_target="${temporary_root}/failed-personal-card"
  local failed_app="${temporary_root}/failed-Who-Am-I.app"

  stop_previous_product_card_server || true
  if [[ -e "${PERSONAL_CARD_TARGET_ROOT}" || -L "${PERSONAL_CARD_TARGET_ROOT}" ]]; then
    if [[ ! -d "${PERSONAL_CARD_TARGET_ROOT}" || -L "${PERSONAL_CARD_TARGET_ROOT}" ]]; then
      printf 'Cannot safely roll back the new Personal Card payload.\n' >&2
      return 1
    fi
    /bin/mv "${PERSONAL_CARD_TARGET_ROOT}" "${failed_target}"
  fi
  if [[ -n "${PERSONAL_CARD_PREVIOUS_TARGET_ROOT}" \
    && -d "${PERSONAL_CARD_PREVIOUS_TARGET_ROOT}" \
    && ! -L "${PERSONAL_CARD_PREVIOUS_TARGET_ROOT}" ]]; then
    /bin/mv "${PERSONAL_CARD_PREVIOUS_TARGET_ROOT}" \
      "${PERSONAL_CARD_TARGET_ROOT}"
  fi

  if [[ -e "${PERSONAL_CARD_APP_BUNDLE}" || -L "${PERSONAL_CARD_APP_BUNDLE}" ]]; then
    if [[ ! -d "${PERSONAL_CARD_APP_BUNDLE}" || -L "${PERSONAL_CARD_APP_BUNDLE}" ]]; then
      printf 'Cannot safely roll back the new Who Am I App.\n' >&2
      return 1
    fi
    /bin/mv "${PERSONAL_CARD_APP_BUNDLE}" "${failed_app}"
  fi
  if [[ -n "${PERSONAL_CARD_PREVIOUS_APP_BUNDLE}" \
    && -d "${PERSONAL_CARD_PREVIOUS_APP_BUNDLE}" \
    && ! -L "${PERSONAL_CARD_PREVIOUS_APP_BUNDLE}" ]]; then
    /bin/mv "${PERSONAL_CARD_PREVIOUS_APP_BUNDLE}" \
      "${PERSONAL_CARD_APP_BUNDLE}"
  fi
  PERSONAL_CARD_TRANSACTION_ACTIVE=0
  printf 'Restored the previous verified Who Am I installation.\n' >&2
}

personal_card_transaction_commit() {
  PERSONAL_CARD_TRANSACTION_ACTIVE=0
  PERSONAL_CARD_TARGET_ROOT=""
  PERSONAL_CARD_PREVIOUS_TARGET_ROOT=""
  PERSONAL_CARD_APP_BUNDLE=""
  PERSONAL_CARD_PREVIOUS_APP_BUNDLE=""
}

print_plan() {
  cat <<EOF
Product version:     $(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")
Runtime source:      bundled in this product package
Runtime commit:      ${RUNTIME_COMMIT}
Runtime tree:        ${RUNTIME_TREE}
Runtime project:     ${RUNTIME_PROJECT_NAME} ${RUNTIME_PROJECT_VERSION}
Installed command:   ${RUNTIME_CLI}
Runtime data root:   ${RUNTIME_INSTALL_HOME}
Card Node runtime:   ${PRODUCT_NODE_VERSION}
Interaction mode:    ${INTERACTION_MODE}

The installer will:
  1. verify this is a supported Mac;
  2. securely detect an existing owner-local Personal Model, if present;
  3. otherwise copy and verify the Runtime embedded in this package;
  4. install or update only the product-managed Runtime path;
  5. never claim, replace, or re-onboard a standalone existing Runtime;
  6. never access the Personal Model source repository during installation;
  7. install the native Who Am I app and its pinned private Node runtime.
EOF
  if [[ "${INTERACTION_MODE}" == "interactive" ]]; then
    printf '%s\n' \
      '  8. guide the signed-in user through permissions and Runtime onboarding.'
  else
    printf '%s\n' \
      '  8. defer permission prompts and print the pinned onboarding command.'
  fi
}

prepare_bundled_runtime_checkout() {
  local destination="$1"

  if [[ ! -d "${BUNDLED_RUNTIME_ROOT}" \
    || -L "${BUNDLED_RUNTIME_ROOT}" \
    || ! -d "${BUNDLED_RUNTIME_ROOT}/.git" ]]; then
    printf '%s\n' \
      'This source checkout is not a self-contained Who Am I package.' \
      'Download the self-contained package from this product repository release.' \
      'No Personal Model repository was contacted.' >&2
    return 1
  fi
  runtime_checkout_copy_bundled "${BUNDLED_RUNTIME_ROOT}" "${destination}"
}

stop_previous_product_card_server() {
  local current_uid pid process_uid process_command attempt

  [[ -x /usr/sbin/lsof ]] || return 0
  current_uid="$(/usr/bin/id -u)"
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    process_uid="$(
      /bin/ps -p "${pid}" -o uid= 2>/dev/null \
        | /usr/bin/tr -d '[:space:]'
    )"
    process_command="$(
      /bin/ps -p "${pid}" -o command= 2>/dev/null || true
    )"
    if [[ "${process_uid}" != "${current_uid}" \
      || "${process_command}" != *"${RUNTIME_INSTALL_HOME}/product-app/"* \
      || "${process_command}" != *"persome-card-server.mjs"* ]]; then
      continue
    fi
    /bin/kill -TERM "${pid}"
    for attempt in {1..30}; do
      if ! /bin/kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      /bin/sleep 0.1
    done
    if /bin/kill -0 "${pid}" 2>/dev/null; then
      printf 'Previous Who Am I service did not stop safely.\n' >&2
      return 1
    fi
  done < <(
    /usr/sbin/lsof -nP -t -iTCP:8772 -sTCP:LISTEN 2>/dev/null \
      | /usr/bin/sort -u
  )
}

install_personal_card() {
  local source_root="${PRODUCT_ROOT}/apps/personal-card"
  local product_version app_root target_root staging_root
  local architecture node_architecture node_archive node_sha node_directory
  local applications_root app_bundle executable_path legacy_executable_path
  local plist_path native_build_root staged_app_bundle previous_app_bundle
  local previous_target_root
  local target_exists=0

  product_version="$(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")"
  app_root="${RUNTIME_INSTALL_HOME}/product-app"
  target_root="${app_root}/${product_version}"
  staging_root="${temporary_root}/personal-card-${product_version}"
  applications_root="${HOME}/Applications"
  app_bundle="${applications_root}/Who Am I.app"
  executable_path="${app_bundle}/Contents/MacOS/WhoAmI"
  legacy_executable_path="${app_bundle}/Contents/MacOS/Who Am I"
  plist_path="${app_bundle}/Contents/Info.plist"

  if [[ ! -d "${source_root}" || -L "${source_root}" \
    || ! -f "${source_root}/package-lock.json" \
    || ! -f "${source_root}/persome-card-server.mjs" ]]; then
    printf 'Personal Card source is missing or unsafe.\n' >&2
    return 1
  fi
  if [[ -e "${app_bundle}" || -L "${app_bundle}" ]]; then
    if [[ ! -d "${app_bundle}" || -L "${app_bundle}" \
      || ! -f "${plist_path}" || -L "${plist_path}" ]]; then
      printf 'Who Am I.app exists but is not owned by this product.\n' >&2
      return 1
    fi
    if ! /usr/bin/grep -Fq \
      '<string>ai.intuition.whoami</string>' "${plist_path}" \
      || {
        if [[ -f "${executable_path}" && ! -L "${executable_path}" ]]; then
          ! /usr/bin/grep -Fq \
            '<key>WhoAmIManagedInstall</key>' "${plist_path}"
        elif [[ -f "${legacy_executable_path}" \
          && ! -L "${legacy_executable_path}" ]]; then
          ! /usr/bin/grep -Fq \
            '/product-app/' "${legacy_executable_path}"
        else
          true
        fi
      }; then
      printf 'Who Am I.app exists but is not owned by this product.\n' >&2
      return 1
    fi
  fi
  if [[ -e "${target_root}" || -L "${target_root}" ]]; then
    if [[ -d "${target_root}" && ! -L "${target_root}" \
      && -x "${target_root}/runtime/node/bin/node" \
      && -f "${target_root}/persome-card-server.mjs" \
      && -f "${target_root}/package-lock.json" \
      && -f "${target_root}/product-version" \
      && "$(tr -d '[:space:]' < "${target_root}/product-version")" == \
        "${product_version}" ]]; then
      printf 'Refreshing installed Personal Card %s.\n' "${product_version}"
      target_exists=1
    else
      printf 'An incomplete Personal Card installation already exists.\n' >&2
      return 1
    fi
  fi
  stop_previous_product_card_server

  /bin/mkdir -p "${app_root}" "${staging_root}"
  /bin/chmod 0700 "${app_root}" "${staging_root}"
  /bin/cp -R "${source_root}/assets" "${staging_root}/"
  /bin/mkdir -p "${staging_root}/src/providers"
  /bin/cp -R \
    "${source_root}/src/auth" \
    "${source_root}/src/client" \
    "${source_root}/src/connectors" \
    "${source_root}/src/contracts" \
    "${source_root}/src/evidence" \
    "${source_root}/src/setup" \
    "${staging_root}/src/"
  /bin/cp \
    "${source_root}/src/providers/local-persome-provider.mjs" \
    "${source_root}/src/providers/provider-registry.mjs" \
    "${source_root}/src/providers/remote-personal-model-provider.mjs" \
    "${source_root}/src/providers/snapshot-backed-provider.mjs" \
    "${staging_root}/src/providers/"
  /bin/cp \
    "${source_root}/package.json" \
    "${source_root}/package-lock.json" \
    "${source_root}/persome-card-server.mjs" \
    "${source_root}/whoami-mcp-proxy.mjs" \
    "${source_root}/WhoAmI v5 · Persome Live.html" \
    "${source_root}/设置我的 Personal Model.command" \
    "${staging_root}/"
  /bin/cp "${PRODUCT_ROOT}/VERSION" "${staging_root}/product-version"
  /bin/chmod 0600 "${staging_root}/product-version"

  architecture="$(uname -m)"
  case "${architecture}" in
    arm64)
      node_architecture="arm64"
      node_sha="${PRODUCT_NODE_DARWIN_ARM64_SHA256}"
      ;;
    x86_64)
      node_architecture="x64"
      node_sha="${PRODUCT_NODE_DARWIN_X64_SHA256}"
      ;;
    *)
      printf 'Unsupported Node architecture: %s\n' "${architecture}" >&2
      return 1
      ;;
  esac
  node_archive="node-v${PRODUCT_NODE_VERSION}-darwin-${node_architecture}.tar.xz"
  node_directory="node-v${PRODUCT_NODE_VERSION}-darwin-${node_architecture}"
  /usr/bin/curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location \
    --output "${temporary_root}/${node_archive}" \
    "${PRODUCT_NODE_BASE_URL}/${node_archive}"
  if [[ "$(/usr/bin/shasum -a 256 "${temporary_root}/${node_archive}" | /usr/bin/awk '{print $1}')" \
    != "${node_sha}" ]]; then
    printf 'Pinned Node runtime digest mismatch.\n' >&2
    return 1
  fi
  /bin/mkdir -p "${staging_root}/runtime"
  /usr/bin/tar -xJf "${temporary_root}/${node_archive}" \
    -C "${staging_root}/runtime"
  /bin/mv \
    "${staging_root}/runtime/${node_directory}" \
    "${staging_root}/runtime/node"
  (
    cd "${staging_root}"
    /usr/bin/env -i \
      HOME="${HOME}" \
      PATH="${staging_root}/runtime/node/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
      npm ci --omit=dev --ignore-scripts --no-audit --no-fund
  )
  /bin/chmod 0700 \
    "${staging_root}/设置我的 Personal Model.command"

  if [[ ! -f "${source_root}/macos/WhoAmIApp.swift" \
    || -L "${source_root}/macos/WhoAmIApp.swift" \
    || ! -f "${source_root}/macos/WhoAmINativeUI.swift" \
    || -L "${source_root}/macos/WhoAmINativeUI.swift" \
    || ! -f "${source_root}/macos/build-native-launcher.sh" \
    || -L "${source_root}/macos/build-native-launcher.sh" ]]; then
    printf 'Native Who Am I launcher source is missing or unsafe.\n' >&2
    return 1
  fi
  native_build_root="${temporary_root}/native-launcher"
  /bin/bash "${source_root}/macos/build-native-launcher.sh" \
    --product-root "${target_root}" \
    --persome-root "${RUNTIME_INSTALL_HOME}" \
    --product-version "${product_version}" \
    --output-directory "${native_build_root}"
  staged_app_bundle="${native_build_root}/Who Am I.app"
  if [[ ! -d "${staged_app_bundle}" \
    || ! -f "${staged_app_bundle}/Contents/MacOS/WhoAmI" \
    || ! -f "${staged_app_bundle}/Contents/Info.plist" ]]; then
    printf 'Native Who Am I launcher build is incomplete.\n' >&2
    return 1
  fi

  if [[ -e "${applications_root}" || -L "${applications_root}" ]]; then
    runtime_secure_owned_directory_verify "${applications_root}"
  else
    /bin/mkdir "${applications_root}"
    /bin/chmod 0700 "${applications_root}"
  fi
  if [[ "${target_exists}" -eq 1 ]]; then
    previous_target_root="${temporary_root}/previous-personal-card-${product_version}"
    /bin/mv "${target_root}" "${previous_target_root}"
  fi
  if ! /bin/mv "${staging_root}" "${target_root}"; then
    if [[ -n "${previous_target_root:-}" \
      && -d "${previous_target_root}" \
      && ! -e "${target_root}" ]]; then
      /bin/mv "${previous_target_root}" "${target_root}" || true
    fi
    printf 'Could not install the Personal Card payload.\n' >&2
    return 1
  fi
  if [[ -e "${app_bundle}" || -L "${app_bundle}" ]]; then
    previous_app_bundle="${temporary_root}/previous-Who-Am-I.app"
    /bin/mv "${app_bundle}" "${previous_app_bundle}"
  fi
  if ! /bin/mv "${staged_app_bundle}" "${app_bundle}"; then
    if [[ -n "${previous_app_bundle:-}" \
      && -d "${previous_app_bundle}" \
      && ! -e "${app_bundle}" ]]; then
      /bin/mv "${previous_app_bundle}" "${app_bundle}" || true
    fi
    if [[ -d "${target_root}" && ! -L "${target_root}" ]]; then
      /bin/mv "${target_root}" "${staging_root}" || true
    fi
    if [[ -n "${previous_target_root:-}" \
      && -d "${previous_target_root}" \
      && ! -e "${target_root}" ]]; then
      /bin/mv "${previous_target_root}" "${target_root}" || true
    fi
    printf 'Could not install the native Who Am I app.\n' >&2
    return 1
  fi
  PERSONAL_CARD_TARGET_ROOT="${target_root}"
  PERSONAL_CARD_PREVIOUS_TARGET_ROOT="${previous_target_root:-}"
  PERSONAL_CARD_APP_BUNDLE="${app_bundle}"
  PERSONAL_CARD_PREVIOUS_APP_BUNDLE="${previous_app_bundle:-}"
  PERSONAL_CARD_TRANSACTION_ACTIVE=1
  printf 'Installed Who Am I to %s\n' "${app_bundle}"
}

check_prerequisites() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'This beta currently supports macOS only.\n' >&2
    return 1
  fi

  local product_version major
  product_version="$(sw_vers -productVersion 2>/dev/null || true)"
  if [[ -z "${product_version}" ]]; then
    printf 'Could not determine the macOS version.\n' >&2
    return 1
  fi
  major="${product_version%%.*}"
  if [[ ! "${major}" =~ ^[0-9]+$ ]] || (( major < 13 )); then
    printf 'macOS 13 or newer is required; found %s.\n' "${product_version}" >&2
    return 1
  fi

  local command_name
  for command_name in bash git curl shasum sw_vers xcode-select swiftc; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "${command_name}" >&2
      return 1
    fi
  done

  case "$(uname -m)" in
    arm64|x86_64) ;;
    *)
      printf 'Unsupported Mac architecture: %s\n' "$(uname -m)" >&2
      return 1
      ;;
  esac

  if ! xcode-select -p >/dev/null 2>&1; then
    printf '%s\n' \
      'Xcode Command Line Tools are required.' \
      'Install them with: xcode-select --install' >&2
    return 1
  fi

  printf 'Prerequisites OK: macOS %s with Xcode Command Line Tools.\n' "${product_version}"
}

install_state_preflight() {
  local external_receipt="${RUNTIME_INSTALL_HOME}/product-runtime.lock"
  local internal_receipt="${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock"
  local install_intent="${RUNTIME_INSTALL_HOME}/product-runtime.installing"
  local uninstall_tombstone="${RUNTIME_INSTALL_HOME}/product-runtime.uninstalled"
  local venv_path="${RUNTIME_INSTALL_HOME}/venv"
  local managed_python_path="${RUNTIME_INSTALL_HOME}/managed-python"
  local product_cache_path="${RUNTIME_INSTALL_HOME}/product-cache"
  local uv_cache_path="${product_cache_path}/uv"
  local management_root="${RUNTIME_INSTALL_HOME}/product-management"
  local active_runtime_lock="${management_root}/runtime.lock"

  MANAGED_EXISTING=0
  EXTERNAL_EXISTING=0
  REMOVE_UNINSTALL_TOMBSTONE=0
  ACTIVE_EXISTING_LOCK=""

  runtime_receipt_path_validate "${external_receipt}"
  runtime_receipt_path_validate "${internal_receipt}"
  runtime_receipt_path_validate "${install_intent}"
  runtime_receipt_path_validate "${uninstall_tombstone}"

  if [[ -e "${install_intent}" || -L "${install_intent}" ]]; then
    printf '%s\n' \
      'A previous product-managed installation did not finish.' \
      'Run the stable product-management uninstaller with --preserve-data,' \
      'then retry installation.' >&2
    return 1
  fi

  if [[ -e "${venv_path}" || -L "${venv_path}" ]]; then
    if runtime_managed_install_verify >/dev/null 2>&1; then
      ACTIVE_EXISTING_LOCK="${TARGET_RUNTIME_LOCK}"
    elif [[ -d "${management_root}" && ! -L "${management_root}" ]] \
      && runtime_secure_owned_directory_verify "${management_root}" \
      && runtime_managed_install_verify_with_lock \
        "${active_runtime_lock}" "${TARGET_RUNTIME_LOCK}" >/dev/null 2>&1; then
      # The installed Runtime belongs to an earlier qualified product lock.
      # Keep that stable bundle unchanged until the target venv is complete.
      ACTIVE_EXISTING_LOCK="${active_runtime_lock}"
    elif runtime_existing_install_verify >/dev/null 2>&1; then
      # Standalone Persome remains owned by its existing installation. The
      # product installs only the Card and connects through the fixed local
      # venv path; it never writes Runtime receipts for code it did not install.
      EXTERNAL_EXISTING=1
    else
      printf '%s\n' \
        'An existing Runtime venv is not a verified product-managed install.' \
        'Refusing to execute or replace unverified Runtime code.' >&2
      return 1
    fi
    if [[ "${EXTERNAL_EXISTING}" -eq 0 ]]; then
      MANAGED_EXISTING=1
    fi
  elif [[ -e "${external_receipt}" || -L "${external_receipt}" \
    || -e "${internal_receipt}" || -L "${internal_receipt}" ]]; then
    printf '%s\n' \
      'Runtime identity receipts exist without their verified venv.' \
      'Refusing to claim a partial or replaced installation.' >&2
    return 1
  fi

  if [[ -e "${uninstall_tombstone}" || -L "${uninstall_tombstone}" ]]; then
    runtime_receipt_verify "${uninstall_tombstone}"
    if [[ "${MANAGED_EXISTING}" -eq 1 ]]; then
      printf 'A stale uninstall tombstone exists beside an active Runtime.\n' >&2
      return 1
    fi
    REMOVE_UNINSTALL_TOMBSTONE=1
  fi

  if [[ -e "${managed_python_path}" || -L "${managed_python_path}" ]]; then
    runtime_secure_owned_directory_verify "${managed_python_path}"
  fi
  if [[ -e "${product_cache_path}" || -L "${product_cache_path}" ]]; then
    runtime_secure_owned_directory_verify "${product_cache_path}"
  fi
  if [[ -e "${uv_cache_path}" || -L "${uv_cache_path}" ]]; then
    runtime_secure_owned_directory_verify "${uv_cache_path}"
  fi
}

shim_state_preflight() {
  local local_root="${HOME}/.local"
  local bin_directory="${local_root}/bin"
  local shim_path="${bin_directory}/${RUNTIME_CLI}"
  local expected_cli="${RUNTIME_INSTALL_HOME}/venv/bin/${RUNTIME_CLI}"
  local directory_path

  for directory_path in "${local_root}" "${bin_directory}"; do
    if [[ -e "${directory_path}" || -L "${directory_path}" ]]; then
      runtime_secure_owned_directory_verify "${directory_path}"
    fi
  done

  if [[ ! -e "${shim_path}" && ! -L "${shim_path}" ]]; then
    return 0
  fi
  if [[ -L "${shim_path}" || ! -f "${shim_path}" \
    || ! -O "${shim_path}" ]]; then
    printf 'Existing command path is unsafe: %s\n' "${shim_path}" >&2
    return 1
  fi
  runtime_path_reject_shared_write "${shim_path}"
  if [[ "${MANAGED_EXISTING}" -ne 1 ]] \
    || ! /usr/bin/grep -Fq "${expected_cli}" "${shim_path}"; then
    printf '%s\n' \
      "Refusing to overwrite an existing non-product command: ${shim_path}" >&2
    return 1
  fi
}

management_target_validate() {
  local target_path="$1"
  if [[ -L "${target_path}" \
    || ( -e "${target_path}" && ! -f "${target_path}" ) ]]; then
    printf 'Product management target is unsafe: %s\n' "${target_path}" >&2
    return 1
  fi
  if [[ -e "${target_path}" ]]; then
    runtime_secure_owned_file_verify "${target_path}"
  fi
}

management_temporary_file_remove() {
  local temporary_file="$1"
  local target_directory="$2"

  case "${temporary_file}" in
    "${target_directory}"/.product-management-file.??????)
      if [[ -f "${temporary_file}" && ! -L "${temporary_file}" \
        && -O "${temporary_file}" ]]; then
        /bin/rm -f -- "${temporary_file}"
      fi
      ;;
    *)
      printf 'Refusing unsafe management temporary file: %s\n' \
        "${temporary_file}" >&2
      return 1
      ;;
  esac
}

management_stream_install_atomic() {
  local target_path="$1"
  local target_mode="$2"
  local target_directory="${target_path%/*}"
  local temporary_file

  case "${target_mode}" in 0600|0700) ;; *)
    printf 'Unsupported product management file mode: %s\n' \
      "${target_mode}" >&2
    return 1
    ;;
  esac
  runtime_secure_owned_directory_verify "${target_directory}"
  management_target_validate "${target_path}"
  temporary_file="$(
    mktemp "${target_directory}/.product-management-file.XXXXXX"
  )"
  if ! /bin/cat > "${temporary_file}" \
    || ! /bin/chmod "${target_mode}" "${temporary_file}" \
    || ! /bin/mv -f -- "${temporary_file}" "${target_path}"; then
    management_temporary_file_remove \
      "${temporary_file}" "${target_directory}" || true
    return 1
  fi
}

management_file_install_atomic() {
  local source_path="$1"
  local target_path="$2"
  local target_mode="$3"

  if [[ ! -f "${source_path}" || -L "${source_path}" ]]; then
    printf 'Product management source is missing or unsafe: %s\n' \
      "${source_path}" >&2
    return 1
  fi
  management_stream_install_atomic \
    "${target_path}" "${target_mode}" < "${source_path}"
}

install_management_bundle() {
  local runtime_checkout="$1"
  local management_root="${RUNTIME_INSTALL_HOME}/product-management"
  local management_scripts="${management_root}/scripts"
  local management_library="${management_scripts}/lib"
  local cached_uninstaller="${management_root}/upstream-uninstall-${RUNTIME_UNINSTALLER_SHA256}.sh"
  local cached_uninstaller_digest
  local target

  if [[ -e "${management_root}" || -L "${management_root}" ]]; then
    runtime_secure_owned_directory_verify "${management_root}"
  else
    /bin/mkdir "${management_root}"
    /bin/chmod 0700 "${management_root}"
  fi
  for target in "${management_scripts}" "${management_library}"; do
    if [[ -e "${target}" || -L "${target}" ]]; then
      runtime_secure_owned_directory_verify "${target}"
    else
      /bin/mkdir "${target}"
      /bin/chmod 0700 "${target}"
    fi
  done

  for target in \
    "${management_root}/VERSION" \
    "${management_root}/product.lock" \
    "${management_root}/runtime.lock" \
    "${management_root}/uninstall-runtime.sh" \
    "${cached_uninstaller}" \
    "${management_root}/MANAGEMENT-README.txt" \
    "${management_scripts}/diagnose.sh" \
    "${management_scripts}/verify-product.sh" \
    "${management_scripts}/verify.sh" \
    "${management_library}/product-lock.sh" \
    "${management_library}/runtime-lock.sh"; do
    management_target_validate "${target}"
  done

  # All files are replaced atomically within their final directory. The lock
  # is deliberately written last. Upstream uninstallers are content-addressed,
  # so both the old and target lock always have a matching offline executable
  # throughout a cross-Runtime update or rollback.
  management_file_install_atomic \
    "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh" \
    "${management_library}/runtime-lock.sh" 0600
  management_file_install_atomic \
    "${PRODUCT_ROOT}/scripts/lib/product-lock.sh" \
    "${management_library}/product-lock.sh" 0600
  management_file_install_atomic \
    "${PRODUCT_ROOT}/uninstall-runtime.sh" \
    "${management_root}/uninstall-runtime.sh" 0700
  management_file_install_atomic \
    "${PRODUCT_ROOT}/scripts/diagnose.sh" \
    "${management_scripts}/diagnose.sh" 0700
  management_file_install_atomic \
    "${PRODUCT_ROOT}/scripts/verify.sh" \
    "${management_scripts}/verify.sh" 0700
  management_file_install_atomic \
    "${PRODUCT_ROOT}/scripts/verify-product.sh" \
    "${management_scripts}/verify-product.sh" 0700
  management_file_install_atomic \
    "${runtime_checkout}/uninstall.sh" \
    "${cached_uninstaller}" 0700
  management_file_install_atomic \
    "${PRODUCT_ROOT}/VERSION" \
    "${management_root}/VERSION" 0600
  management_file_install_atomic \
    "${PRODUCT_ROOT}/product.lock" \
    "${management_root}/product.lock" 0600

  cached_uninstaller_digest="$(
    /usr/bin/shasum -a 256 "${cached_uninstaller}" \
      | /usr/bin/awk '{print $1}'
  )"
  if [[ "${cached_uninstaller_digest}" != "${RUNTIME_UNINSTALLER_SHA256}" ]]; then
    printf 'Cached Runtime uninstaller digest mismatch.\n' >&2
    return 1
  fi

  {
    printf 'Personal Model product management bundle\n'
    printf 'Product version: %s\n\n' \
      "$(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")"
    printf 'Privacy-safe diagnosis:\n  /bin/bash "%s/scripts/diagnose.sh"\n\n' \
      "${management_root}"
    printf 'Quick verification:\n  /bin/bash "%s/scripts/verify.sh" --quick\n\n' \
      "${management_root}"
    printf 'Product application verification:\n'
    printf '  /bin/bash "%s/scripts/verify-product.sh"\n\n' \
      "${management_root}"
    printf 'Preserve-data Runtime uninstall:\n'
    printf '  /bin/bash "%s/uninstall-runtime.sh" --preserve-data\n' \
      "${management_root}"
  } | management_stream_install_atomic \
    "${management_root}/MANAGEMENT-README.txt" 0600

  # Commit the target identity only after every target executable and its
  # content-addressed upstream uninstaller are durable.
  management_file_install_atomic \
    "${PRODUCT_ROOT}/runtime.lock" \
    "${management_root}/runtime.lock" 0600
}

if [[ "${MODE}" == "plan" ]]; then
  print_plan
  exit 0
fi

check_prerequisites
if [[ "${MODE}" == "check" ]]; then
  exit 0
fi

if [[ -e "${RUNTIME_INSTALL_HOME}" ]]; then
  runtime_secure_owned_directory_verify "${RUNTIME_INSTALL_HOME}"
else
  /bin/mkdir -p "${RUNTIME_INSTALL_HOME}"
  /bin/chmod 0700 "${RUNTIME_INSTALL_HOME}"
fi
runtime_install_home_resolve
runtime_operation_lock_acquire

temporary_root=""
INSTALL_INTENT_WRITTEN=0
cleanup() {
  local cleanup_status=$?
  local intent_path="${RUNTIME_INSTALL_HOME}/product-runtime.installing"

  if [[ "${cleanup_status}" -ne 0 ]]; then
    personal_card_transaction_rollback || cleanup_status=1
  fi
  # If an existing Runtime update failed and the upstream transaction restored
  # its previously verified venv, remove only the target-lock intent. A fresh
  # failed install deliberately keeps its intent for offline uninstall.
  if [[ "${cleanup_status}" -ne 0 \
    && "${MANAGED_EXISTING:-0}" -eq 1 \
    && "${INSTALL_INTENT_WRITTEN:-0}" -eq 1 \
    && -n "${ACTIVE_EXISTING_LOCK:-}" ]] \
    && runtime_managed_install_verify_with_lock \
      "${ACTIVE_EXISTING_LOCK}" "${TARGET_RUNTIME_LOCK}" >/dev/null 2>&1 \
    && runtime_receipt_verify "${intent_path}" >/dev/null 2>&1; then
    runtime_receipt_path_validate "${intent_path}" >/dev/null 2>&1 \
      && /bin/rm -f -- "${intent_path}"
  fi
  if [[ -n "${temporary_root:-}" ]]; then
    runtime_temporary_root_remove \
      "${temporary_root}" "personal-model-product" || true
  fi
  runtime_operation_lock_release || true
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

install_state_preflight
if [[ "${EXTERNAL_EXISTING}" -eq 1 ]]; then
  temporary_root="$(runtime_temporary_root_create "personal-model-product")"
  install_personal_card
  installer_test_failpoint "after-card-before-verification"
  /bin/bash "${PRODUCT_ROOT}/scripts/verify-product.sh"
  personal_card_transaction_commit
  cat <<EOF

Existing Personal Model detected and preserved.
Who Am I connected to:

  ${RUNTIME_INSTALL_HOME}

No Runtime files, model data, permissions, or MCP client settings were changed.
Who Am I is installed in:

  ${HOME}/Applications/Who Am I.app
EOF
  if [[ "${INTERACTION_MODE}" == "interactive" ]]; then
    /usr/bin/open "${HOME}/Applications/Who Am I.app" || true
  fi
  exit 0
fi
if [[ "${MANAGED_EXISTING}" -eq 1 \
  && "${ACTIVE_EXISTING_LOCK}" == "${TARGET_RUNTIME_LOCK}" ]]; then
  temporary_root="$(runtime_temporary_root_create "personal-model-product")"
  prepare_bundled_runtime_checkout "${temporary_root}/runtime"
  runtime_checkout_verify "${temporary_root}/runtime"
  install_management_bundle "${temporary_root}/runtime"
  install_personal_card
  installer_test_failpoint "after-card-before-verification"
  /bin/bash "${PRODUCT_ROOT}/scripts/verify.sh" --quick
  /bin/bash "${PRODUCT_ROOT}/scripts/verify-product.sh"
  personal_card_transaction_commit
  cat <<EOF

The installed Personal Model already matches this product's pinned Runtime.
Its executables, permissions, and model data were preserved.

Who Am I is installed in:

  ${HOME}/Applications/Who Am I.app
EOF
  if [[ "${INTERACTION_MODE}" == "interactive" ]]; then
    /usr/bin/open "${HOME}/Applications/Who Am I.app" || true
  fi
  exit 0
fi
if [[ "${MANAGED_EXISTING}" -eq 1 \
  && "${INTERACTION_MODE}" != "interactive" ]]; then
  printf '%s\n' \
    'Updating an existing Runtime requires an interactive logged-in terminal.' \
    'The pinned transactional updater must reverify permissions and Runtime health.' \
    'Run again with --interactive; no updater or Runtime executable was started.' >&2
  exit 2
fi
shim_state_preflight

temporary_root="$(runtime_temporary_root_create "personal-model-product")"
prepare_bundled_runtime_checkout "${temporary_root}/runtime"
runtime_checkout_verify "${temporary_root}/runtime"

if [[ "${MANAGED_EXISTING}" -eq 0 ]]; then
  # A fresh install must have an offline recovery path before the upstream
  # installer can commit a venv or request permissions. If any later step
  # fails, the target-lock intent and this bundle are enough to uninstall
  # without the downloaded Release directory or GitHub.
  install_management_bundle "${temporary_root}/runtime"
fi

if [[ "${REMOVE_UNINSTALL_TOMBSTONE}" -eq 1 ]]; then
  /bin/rm -f -- "${RUNTIME_INSTALL_HOME}/product-runtime.uninstalled"
fi

/bin/mkdir "${temporary_root}/uv"
/bin/chmod 0700 "${temporary_root}/uv"
verified_uv_directory="$(runtime_uv_prepare "${temporary_root}/uv")"
/bin/mkdir "${temporary_root}/upstream-tmp"
/bin/chmod 0700 "${temporary_root}/upstream-tmp"
product_cache_path="${RUNTIME_INSTALL_HOME}/product-cache"
uv_cache_path="${product_cache_path}/uv"
for cache_directory in "${product_cache_path}" "${uv_cache_path}"; do
  if [[ -e "${cache_directory}" || -L "${cache_directory}" ]]; then
    runtime_secure_owned_directory_verify "${cache_directory}"
  else
    /bin/mkdir "${cache_directory}"
    /bin/chmod 0700 "${cache_directory}"
  fi
  runtime_secure_owned_directory_verify "${cache_directory}"
done

runtime_receipt_write "${RUNTIME_INSTALL_HOME}/product-runtime.installing"
INSTALL_INTENT_WRITTEN=1

printf 'Installing reviewed Runtime commit %s...\n' "${RUNTIME_COMMIT:0:12}"
upstream_environment=(
  /usr/bin/env -i
  "HOME=${HOME}"
  "PATH=${verified_uv_directory}:${RUNTIME_SYSTEM_PATH}"
  "TMPDIR=${temporary_root}/upstream-tmp"
  "PERSOME_INSTALL_HOME=${RUNTIME_INSTALL_HOME}"
  "UV_CACHE_DIR=${uv_cache_path}"
  "UV_PYTHON_INSTALL_DIR=${RUNTIME_INSTALL_HOME}/managed-python"
  "TERM=${TERM:-dumb}"
)
if [[ -n "${PERSOME_PYTHON:-}" ]]; then
  upstream_environment+=("PERSOME_PYTHON=${PERSOME_PYTHON}")
fi
if [[ "${INTERACTION_MODE}" == "interactive" ]]; then
  "${upstream_environment[@]}" \
    /bin/bash "${temporary_root}/runtime/install.sh" --no-client-config
else
  "${upstream_environment[@]}" \
    /bin/bash "${temporary_root}/runtime/install.sh" --no-client-config </dev/null
fi

installer_test_failpoint "after-upstream-before-receipts"
runtime_install_home_resolve
runtime_managed_venv_artifacts_verify
# Switch the stable recovery commands to the target lock before committing
# either target receipt. If a later receipt or quick-verification step fails,
# the target intent remains and this offline bundle can remove the target venv.
install_management_bundle "${temporary_root}/runtime"
runtime_receipt_write "${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock"
runtime_receipt_write "${RUNTIME_INSTALL_HOME}/product-runtime.lock"
install_personal_card
installer_test_failpoint "after-card-before-verification"
/bin/bash "${PRODUCT_ROOT}/scripts/verify.sh" --quick
/bin/bash "${PRODUCT_ROOT}/scripts/verify-product.sh"
personal_card_transaction_commit
intent_path="${RUNTIME_INSTALL_HOME}/product-runtime.installing"
runtime_receipt_path_validate "${intent_path}"
/bin/rm -f -- "${intent_path}"
INSTALL_INTENT_WRITTEN=0

if [[ "${INTERACTION_MODE}" == "interactive" ]]; then
  cat <<EOF

Base Runtime installation is ready.
Run the privacy-safe diagnostic and quick identity check:

  /bin/bash "${RUNTIME_INSTALL_HOME}/product-management/scripts/diagnose.sh"
  /bin/bash "${RUNTIME_INSTALL_HOME}/product-management/scripts/verify.sh" --quick

After provider setup and onboarding are complete, run:

  /bin/bash "${RUNTIME_INSTALL_HOME}/product-management/scripts/verify.sh" --full

Who Am I is installed in:

  ${HOME}/Applications/Who Am I.app
EOF
  /usr/bin/open "${HOME}/Applications/Who Am I.app" || true
else
  cat <<EOF

Base Runtime installation is ready; permission onboarding is pending.
From a logged-in terminal, run:

  "${RUNTIME_INSTALL_HOME}/venv/bin/persome" onboard

Then run:

  /bin/bash "${RUNTIME_INSTALL_HOME}/product-management/scripts/diagnose.sh"
  /bin/bash "${RUNTIME_INSTALL_HOME}/product-management/scripts/verify.sh" --quick

After provider setup and onboarding are complete, run:

  /bin/bash "${RUNTIME_INSTALL_HOME}/product-management/scripts/verify.sh" --full

Who Am I is installed in:

  ${HOME}/Applications/Who Am I.app
EOF
fi
