#!/usr/bin/env bash

RUNTIME_SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

runtime_lock_load() {
  local lock_file="$1"
  local line line_number=0 key value seen_keys=""
  local assignment_pattern='^([A-Z][A-Z0-9_]*)="([^"]*)"$'

  if [[ ! -f "${lock_file}" || -L "${lock_file}" ]]; then
    printf 'Runtime lock is missing or unsafe: %s\n' "${lock_file}" >&2
    return 1
  fi

  unset RUNTIME_LOCK_SCHEMA
  unset RUNTIME_REPOSITORY
  unset RUNTIME_COMMIT
  unset RUNTIME_TREE
  unset RUNTIME_PROJECT_NAME
  unset RUNTIME_PROJECT_VERSION
  unset RUNTIME_CLI
  unset RUNTIME_INSTALLER_SHA256
  unset RUNTIME_UNINSTALLER_SHA256
  unset RUNTIME_UV_LOCK_SHA256
  unset RUNTIME_BUILD_CONSTRAINTS_SHA256
  unset RUNTIME_UV_VERSION
  unset RUNTIME_UV_AARCH64_SHA256
  unset RUNTIME_UV_X86_64_SHA256

  # Parse a deliberately small assignment-only format. Never source the lock:
  # a version-controlled data file must not become an arbitrary shell program.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_number=$((line_number + 1))
    case "${line}" in
      ""|\#*)
        continue
        ;;
    esac
    if [[ ! "${line}" =~ ${assignment_pattern} ]]; then
      printf 'Invalid Runtime lock syntax at %s:%s.\n' \
        "${lock_file}" "${line_number}" >&2
      return 1
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "|${seen_keys}|" in
      *"|${key}|"*)
        printf 'Duplicate Runtime lock key at %s:%s: %s\n' \
          "${lock_file}" "${line_number}" "${key}" >&2
        return 1
        ;;
    esac
    seen_keys="${seen_keys}|${key}"
    case "${key}" in
      RUNTIME_LOCK_SCHEMA) RUNTIME_LOCK_SCHEMA="${value}" ;;
      RUNTIME_REPOSITORY) RUNTIME_REPOSITORY="${value}" ;;
      RUNTIME_COMMIT) RUNTIME_COMMIT="${value}" ;;
      RUNTIME_TREE) RUNTIME_TREE="${value}" ;;
      RUNTIME_PROJECT_NAME) RUNTIME_PROJECT_NAME="${value}" ;;
      RUNTIME_PROJECT_VERSION) RUNTIME_PROJECT_VERSION="${value}" ;;
      RUNTIME_CLI) RUNTIME_CLI="${value}" ;;
      RUNTIME_INSTALLER_SHA256) RUNTIME_INSTALLER_SHA256="${value}" ;;
      RUNTIME_UNINSTALLER_SHA256) RUNTIME_UNINSTALLER_SHA256="${value}" ;;
      RUNTIME_UV_LOCK_SHA256) RUNTIME_UV_LOCK_SHA256="${value}" ;;
      RUNTIME_BUILD_CONSTRAINTS_SHA256)
        RUNTIME_BUILD_CONSTRAINTS_SHA256="${value}"
        ;;
      RUNTIME_UV_VERSION) RUNTIME_UV_VERSION="${value}" ;;
      RUNTIME_UV_AARCH64_SHA256) RUNTIME_UV_AARCH64_SHA256="${value}" ;;
      RUNTIME_UV_X86_64_SHA256) RUNTIME_UV_X86_64_SHA256="${value}" ;;
      *)
        printf 'Unknown Runtime lock key at %s:%s: %s\n' \
          "${lock_file}" "${line_number}" "${key}" >&2
        return 1
        ;;
    esac
  done < "${lock_file}"

  if [[ "${RUNTIME_LOCK_SCHEMA:-}" != "1" ]]; then
    printf 'Unsupported or missing Runtime lock schema.\n' >&2
    return 1
  fi
  if [[ "${RUNTIME_REPOSITORY:-}" != \
    "https://github.com/Intuition-Lab/personal-model.git" ]]; then
    printf 'Runtime repository is not the reviewed Personal Model source.\n' >&2
    return 1
  fi
  if [[ ! "${RUNTIME_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Runtime commit must be a full lowercase SHA-1.\n' >&2
    return 1
  fi
  if [[ ! "${RUNTIME_TREE:-}" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Runtime tree must be a full lowercase Git tree ID.\n' >&2
    return 1
  fi
  if [[ ! "${RUNTIME_PROJECT_NAME:-}" =~ ^[a-z0-9-]+$ ]]; then
    printf 'Runtime project name is invalid.\n' >&2
    return 1
  fi
  if [[ ! "${RUNTIME_PROJECT_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Runtime project version is invalid.\n' >&2
    return 1
  fi
  if [[ ! "${RUNTIME_CLI:-}" =~ ^[a-z0-9-]+$ ]]; then
    printf 'Runtime CLI name is invalid.\n' >&2
    return 1
  fi
  for value in \
    "${RUNTIME_INSTALLER_SHA256:-}" \
    "${RUNTIME_UNINSTALLER_SHA256:-}" \
    "${RUNTIME_UV_LOCK_SHA256:-}" \
    "${RUNTIME_BUILD_CONSTRAINTS_SHA256:-}" \
    "${RUNTIME_UV_AARCH64_SHA256:-}" \
    "${RUNTIME_UV_X86_64_SHA256:-}"; do
    if [[ ! "${value}" =~ ^[0-9a-f]{64}$ ]]; then
      printf 'Runtime file digests must be lowercase SHA-256 values.\n' >&2
      return 1
    fi
  done
  if [[ ! "${RUNTIME_UV_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Runtime uv bootstrap version is invalid.\n' >&2
    return 1
  fi
}

runtime_git() {
  /usr/bin/env -i \
    HOME="${HOME:-/tmp}" \
    PATH="${RUNTIME_SYSTEM_PATH}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=0 \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/usr/bin/false \
    SSH_ASKPASS=/usr/bin/false \
    /usr/bin/git \
      -c core.hooksPath=/dev/null \
      -c protocol.file.allow=never \
      -c protocol.ext.allow=never \
      "$@"
}

runtime_temporary_root_create() {
  local prefix="$1"
  local temporary_base="${TMPDIR:-/tmp}"
  local temporary_root marker

  if [[ ! "${prefix}" =~ ^[a-z0-9-]+$ ]]; then
    printf 'Unsafe temporary directory prefix: %s\n' "${prefix}" >&2
    return 1
  fi
  temporary_base="${temporary_base%/}"
  case "${temporary_base}" in
    /*) ;;
    *) temporary_base="/tmp" ;;
  esac
  case "${temporary_base}" in
    *[[:cntrl:]]*|*//*|*/./*|*/../*|*/.|*/..)
      temporary_base="/tmp"
      ;;
  esac
  if [[ ! -d "${temporary_base}" || ! -w "${temporary_base}" ]]; then
    temporary_base="/tmp"
  fi

  temporary_root="$(mktemp -d "${temporary_base}/${prefix}.XXXXXX")"
  temporary_root="$(cd "${temporary_root}" && pwd -P)"
  if [[ ! -d "${temporary_root}" || -L "${temporary_root}" || ! -O "${temporary_root}" ]]; then
    printf 'Could not create an owner-controlled temporary directory.\n' >&2
    return 1
  fi
  marker="${temporary_root}/.product-installer-temporary-root"
  (umask 077; printf '%s\n' "${prefix}" > "${marker}")
  printf '%s\n' "${temporary_root}"
}

runtime_temporary_root_remove() {
  local temporary_root="$1"
  local prefix="$2"
  local marker="${temporary_root}/.product-installer-temporary-root"

  if [[ -z "${temporary_root}" || ! -d "${temporary_root}" \
    || -L "${temporary_root}" || ! -O "${temporary_root}" \
    || "${temporary_root##*/}" != "${prefix}."?????? \
    || ! -f "${marker}" || -L "${marker}" || ! -O "${marker}" \
    || "$(command cat "${marker}")" != "${prefix}" ]]; then
    printf 'Refusing to remove an unverified temporary path: %s\n' \
      "${temporary_root:-<empty>}" >&2
    return 1
  fi
  rm -rf -- "${temporary_root}"
}

runtime_checkout_create() {
  local destination="$1"
  local fetch_attempt fetch_succeeded=0
  if [[ -e "${destination}" ]]; then
    printf 'Checkout destination already exists: %s\n' "${destination}" >&2
    return 1
  fi

  runtime_git init --quiet "${destination}"
  runtime_git -C "${destination}" remote add origin "${RUNTIME_REPOSITORY}"
  fetch_attempt=1
  while [[ "${fetch_attempt}" -le 3 ]]; do
    if runtime_git -C "${destination}" \
      fetch --quiet --force --depth 1 origin "${RUNTIME_COMMIT}"; then
      fetch_succeeded=1
      break
    fi
    if [[ "${fetch_attempt}" -lt 3 ]]; then
      printf 'Pinned Runtime fetch failed; retrying attempt %s of 3.\n' \
        "$((fetch_attempt + 1))" >&2
      /bin/sleep "$((fetch_attempt * 2))"
    fi
    fetch_attempt=$((fetch_attempt + 1))
  done
  if [[ "${fetch_succeeded}" -ne 1 ]]; then
    printf 'Could not fetch the pinned Runtime commit after 3 attempts.\n' >&2
    return 1
  fi
  runtime_git -C "${destination}" \
    -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD
}

runtime_checkout_copy_bundled() {
  local source_checkout="$1"
  local destination="$2"
  local unsafe_link=""

  if [[ ! -d "${source_checkout}" || -L "${source_checkout}" \
    || ! -d "${source_checkout}/.git" || -L "${source_checkout}/.git" ]]; then
    printf 'Bundled Runtime checkout is missing or unsafe: %s\n' \
      "${source_checkout}" >&2
    return 1
  fi
  if [[ -e "${destination}" || -L "${destination}" ]]; then
    printf 'Checkout destination already exists: %s\n' "${destination}" >&2
    return 1
  fi
  unsafe_link="$(
    /usr/bin/find "${source_checkout}" -type l -print -quit 2>/dev/null || true
  )"
  if [[ -n "${unsafe_link}" ]]; then
    printf 'Bundled Runtime checkout contains a symbolic link: %s\n' \
      "${unsafe_link}" >&2
    return 1
  fi

  /bin/cp -R "${source_checkout}" "${destination}"
  runtime_checkout_verify "${destination}"
}

runtime_checkout_verify() {
  local checkout="$1"
  local actual_commit actual_tree actual_digest project_name project_version

  if [[ ! -d "${checkout}" || -L "${checkout}" ]]; then
    printf 'Runtime checkout is missing or unsafe: %s\n' "${checkout}" >&2
    return 1
  fi
  actual_commit="$(runtime_git -C "${checkout}" rev-parse --verify "HEAD^{commit}")"
  if [[ "${actual_commit}" != "${RUNTIME_COMMIT}" ]]; then
    printf 'Runtime checkout mismatch: expected %s, got %s\n' \
      "${RUNTIME_COMMIT}" "${actual_commit}" >&2
    return 1
  fi
  actual_tree="$(runtime_git -C "${checkout}" rev-parse --verify "HEAD^{tree}")"
  if [[ "${actual_tree}" != "${RUNTIME_TREE}" ]]; then
    printf 'Runtime tree mismatch: expected %s, got %s\n' \
      "${RUNTIME_TREE}" "${actual_tree}" >&2
    return 1
  fi
  if ! runtime_git -C "${checkout}" fsck --strict --no-dangling >/dev/null; then
    printf 'Runtime checkout failed strict Git object verification.\n' >&2
    return 1
  fi
  if [[ -n "$(
    runtime_git -C "${checkout}" status --porcelain --untracked-files=all
  )" ]]; then
    printf 'Runtime checkout contains modified or untracked content.\n' >&2
    return 1
  fi

  for required_path in \
    pyproject.toml \
    uv.lock \
    build-constraints.txt \
    install.sh \
    uninstall.sh \
    src/persome/cli.py; do
    if [[ ! -f "${checkout}/${required_path}" || -L "${checkout}/${required_path}" ]]; then
      printf 'Pinned Runtime file is missing or unsafe: %s.\n' "${required_path}" >&2
      return 1
    fi
  done

  if ! command -v shasum >/dev/null 2>&1; then
    printf 'shasum is required to verify pinned Runtime files.\n' >&2
    return 1
  fi
  actual_digest="$(shasum -a 256 "${checkout}/install.sh" | awk '{print $1}')"
  if [[ "${actual_digest}" != "${RUNTIME_INSTALLER_SHA256}" ]]; then
    printf 'Pinned Runtime installer digest mismatch.\n' >&2
    return 1
  fi
  actual_digest="$(shasum -a 256 "${checkout}/uninstall.sh" | awk '{print $1}')"
  if [[ "${actual_digest}" != "${RUNTIME_UNINSTALLER_SHA256}" ]]; then
    printf 'Pinned Runtime uninstaller digest mismatch.\n' >&2
    return 1
  fi
  actual_digest="$(shasum -a 256 "${checkout}/uv.lock" | awk '{print $1}')"
  if [[ "${actual_digest}" != "${RUNTIME_UV_LOCK_SHA256}" ]]; then
    printf 'Pinned Runtime dependency lock digest mismatch.\n' >&2
    return 1
  fi
  actual_digest="$(
    shasum -a 256 "${checkout}/build-constraints.txt" | awk '{print $1}'
  )"
  if [[ "${actual_digest}" != "${RUNTIME_BUILD_CONSTRAINTS_SHA256}" ]]; then
    printf 'Pinned Runtime build constraints digest mismatch.\n' >&2
    return 1
  fi

  project_name="$(
    sed -nE 's/^name = "([^"]+)"$/\1/p' "${checkout}/pyproject.toml" | head -n 1
  )"
  project_version="$(
    sed -nE 's/^version = "([^"]+)"$/\1/p' "${checkout}/pyproject.toml" | head -n 1
  )"
  if [[ "${project_name}" != "${RUNTIME_PROJECT_NAME}" ]]; then
    printf 'Runtime project mismatch: expected %s, got %s\n' \
      "${RUNTIME_PROJECT_NAME}" "${project_name}" >&2
    return 1
  fi
  if [[ "${project_version}" != "${RUNTIME_PROJECT_VERSION}" ]]; then
    printf 'Runtime version mismatch: expected %s, got %s\n' \
      "${RUNTIME_PROJECT_VERSION}" "${project_version}" >&2
    return 1
  fi

  if ! grep -Fq "${RUNTIME_CLI} = \"persome.cli:app\"" "${checkout}/pyproject.toml"; then
    printf 'Pinned Runtime no longer exposes the expected %s CLI.\n' "${RUNTIME_CLI}" >&2
    return 1
  fi
  if ! grep -Fq "UV_BOOTSTRAP_VERSION=\"${RUNTIME_UV_VERSION}\"" \
    "${checkout}/install.sh" \
    || ! grep -Fq "UV_SHA256_AARCH64_DARWIN=\"${RUNTIME_UV_AARCH64_SHA256}\"" \
      "${checkout}/install.sh" \
    || ! grep -Fq "UV_SHA256_X86_64_DARWIN=\"${RUNTIME_UV_X86_64_SHA256}\"" \
      "${checkout}/install.sh"; then
    printf 'Pinned Runtime uv bootstrap contract changed.\n' >&2
    return 1
  fi
}

runtime_path_mode() {
  local target_path="$1"
  local mode

  if mode="$(/usr/bin/stat -f '%Lp' "${target_path}" 2>/dev/null)"; then
    :
  elif mode="$(/usr/bin/stat -c '%a' "${target_path}" 2>/dev/null)"; then
    :
  else
    printf 'Could not inspect path permissions.\n' >&2
    return 1
  fi
  if [[ ! "${mode}" =~ ^[0-7]{3,4}$ ]]; then
    printf 'Path permissions were not a supported octal mode.\n' >&2
    return 1
  fi
  printf '%s\n' "${mode}"
}

runtime_path_reject_shared_write() {
  local target_path="$1"
  local mode

  mode="$(runtime_path_mode "${target_path}")"
  if (( (8#${mode} & 8#022) != 0 )); then
    printf 'Path must not be group- or world-writable: %s\n' \
      "${target_path}" >&2
    return 1
  fi
}

runtime_home_chain_verify() {
  local home_path="$1"
  local component current_path=""
  local -a components

  IFS='/' read -r -a components <<< "${home_path#/}"
  for component in "${components[@]}"; do
    [[ -n "${component}" ]] || continue
    current_path="${current_path}/${component}"
    if [[ -L "${current_path}" || ! -d "${current_path}" ]]; then
      printf 'HOME must not traverse a symlink or non-directory: %s\n' \
        "${current_path}" >&2
      return 1
    fi
  done
  if [[ ! -O "${home_path}" ]]; then
    printf 'HOME must be owned by the current user.\n' >&2
    return 1
  fi
  runtime_path_reject_shared_write "${home_path}"
}

runtime_secure_owned_directory_verify() {
  local directory_path="$1"

  if [[ ! -d "${directory_path}" || -L "${directory_path}" \
    || ! -O "${directory_path}" ]]; then
    printf 'Expected an owner-controlled non-symlink directory: %s\n' \
      "${directory_path}" >&2
    return 1
  fi
  runtime_path_reject_shared_write "${directory_path}"
}

runtime_secure_owned_file_verify() {
  local file_path="$1"

  if [[ ! -f "${file_path}" || -L "${file_path}" || ! -O "${file_path}" ]]; then
    printf 'Expected an owner-controlled non-symlink file: %s\n' \
      "${file_path}" >&2
    return 1
  fi
  runtime_path_reject_shared_write "${file_path}"
}

runtime_install_home_resolve() {
  local home_path="${HOME:-}"
  local install_path component current_path
  local -a components

  home_path="${home_path%/}"
  if [[ -z "${home_path}" || "${home_path}" != /* || "${home_path}" == "/" \
    || ! -d "${home_path}" || -L "${home_path}" || ! -O "${home_path}" ]]; then
    printf 'HOME must be an owner-controlled, non-symlink absolute directory.\n' >&2
    return 1
  fi
  runtime_home_chain_verify "${home_path}" || return 1

  install_path="${PERSOME_INSTALL_HOME:-${home_path}/.persome}"
  install_path="${install_path%/}"
  if [[ -z "${install_path}" || "${install_path}" != /* \
    || "${install_path}" == "${home_path}" || "${install_path}" != "${home_path}/"* ]]; then
    printf 'PERSOME_INSTALL_HOME must be a child directory of HOME.\n' >&2
    return 1
  fi
  case "${install_path}" in
    *[[:cntrl:]]*|*//*|*/./*|*/../*|*/.|*/..)
      printf 'PERSOME_INSTALL_HOME contains unsafe path components.\n' >&2
      return 1
      ;;
  esac

  IFS='/' read -r -a components <<< "${install_path#"${home_path}/"}"
  current_path="${home_path}"
  for component in "${components[@]}"; do
    if [[ -z "${component}" || "${component}" == "." || "${component}" == ".." ]]; then
      printf 'PERSOME_INSTALL_HOME contains unsafe path components.\n' >&2
      return 1
    fi
    current_path="${current_path}/${component}"
    if [[ -L "${current_path}" ]]; then
      printf 'PERSOME_INSTALL_HOME must not traverse a symlink: %s\n' \
        "${current_path}" >&2
      return 1
    fi
    if [[ -e "${current_path}" && ! -d "${current_path}" ]]; then
      printf 'PERSOME_INSTALL_HOME path component is not a directory: %s\n' \
        "${current_path}" >&2
      return 1
    fi
    if [[ -d "${current_path}" ]]; then
      runtime_secure_owned_directory_verify "${current_path}" || return 1
    fi
  done
  if [[ -n "${PERSOME_PYTHON:-}" \
    && ! "${PERSOME_PYTHON}" =~ ^3\.(12|13)(\.[0-9]+)?$ ]]; then
    printf 'PERSOME_PYTHON must select Python 3.12 or 3.13.\n' >&2
    return 1
  fi

  RUNTIME_INSTALL_HOME="${install_path}"
  export RUNTIME_INSTALL_HOME
  export PERSOME_INSTALL_HOME="${install_path}"
}

runtime_managed_venv_artifacts_verify() {
  local venv_path="${RUNTIME_INSTALL_HOME}/venv"
  local bin_path="${venv_path}/bin"
  local runtime_python="${bin_path}/python"
  local runtime_cli="${bin_path}/${RUNTIME_CLI}"

  runtime_secure_owned_directory_verify "${RUNTIME_INSTALL_HOME}" || return 1
  runtime_secure_owned_directory_verify "${venv_path}" || return 1
  runtime_secure_owned_directory_verify "${bin_path}" || return 1

  if [[ ! -x "${runtime_python}" || ! -O "${runtime_python}" \
    || ( ! -f "${runtime_python}" && ! -L "${runtime_python}" ) ]]; then
    printf 'Runtime Python path is missing or unsafe.\n' >&2
    return 1
  fi
  runtime_path_reject_shared_write "${runtime_python}" || return 1

  if [[ ! -x "${runtime_cli}" || ! -f "${runtime_cli}" \
    || -L "${runtime_cli}" || ! -O "${runtime_cli}" ]]; then
    printf 'Runtime CLI path is missing or unsafe.\n' >&2
    return 1
  fi
  runtime_path_reject_shared_write "${runtime_cli}" || return 1
}

runtime_existing_install_verify() {
  # A standalone Persome installation has no product receipts. It can still be
  # connected without being claimed or updated by this product when every
  # executable path is owner-controlled and resolves inside the expected
  # ~/.persome venv.
  runtime_managed_venv_artifacts_verify
}

runtime_managed_install_verify() {
  runtime_receipt_verify \
    "${RUNTIME_INSTALL_HOME}/product-runtime.lock" || return 1
  runtime_receipt_verify \
    "${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock" || return 1
  runtime_managed_venv_artifacts_verify || return 1
}

runtime_managed_install_verify_with_lock() {
  local candidate_lock="$1"
  local restore_lock="$2"
  local verification_status=0

  # A product update has two identities in play: the target lock shipped in
  # the new Release and the active lock retained by the installed management
  # bundle. Parse both as data. Always restore the target identity before
  # returning, including after a malformed or tampered active lock.
  if ! runtime_secure_owned_file_verify "${candidate_lock}" \
    || ! runtime_lock_load "${candidate_lock}" \
    || ! runtime_managed_install_verify; then
    verification_status=1
  fi
  if ! runtime_lock_load "${restore_lock}"; then
    printf 'Could not restore the target Runtime lock after verification.\n' >&2
    return 1
  fi
  return "${verification_status}"
}

runtime_uv_prepare() {
  local destination_root="$1"
  local architecture target expected archive extracted actual

  runtime_secure_owned_directory_verify "${destination_root}" || return 1
  architecture="$(/usr/bin/uname -m)"
  case "${architecture}" in
    arm64)
      target="aarch64-apple-darwin"
      expected="${RUNTIME_UV_AARCH64_SHA256}"
      ;;
    x86_64)
      target="x86_64-apple-darwin"
      expected="${RUNTIME_UV_X86_64_SHA256}"
      ;;
    *)
      printf 'Unsupported architecture for verified uv: %s\n' \
        "${architecture}" >&2
      return 1
      ;;
  esac

  archive="uv-${target}.tar.gz"
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
    "https://github.com/astral-sh/uv/releases/download/${RUNTIME_UV_VERSION}/${archive}" \
    --output "${destination_root}/${archive}"
  actual="$(
    /usr/bin/shasum -a 256 "${destination_root}/${archive}" \
      | /usr/bin/awk '{print $1}'
  )"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'Verified uv archive checksum mismatch.\n' >&2
    return 1
  fi
  /usr/bin/tar -xzf "${destination_root}/${archive}" -C "${destination_root}"
  extracted="${destination_root}/uv-${target}"
  runtime_secure_owned_directory_verify "${extracted}" || return 1
  if [[ ! -x "${extracted}/uv" || ! -f "${extracted}/uv" \
    || -L "${extracted}/uv" || ! -O "${extracted}/uv" ]]; then
    printf 'Verified uv archive had an unsafe layout.\n' >&2
    return 1
  fi
  runtime_path_reject_shared_write "${extracted}/uv" || return 1
  printf '%s\n' "${extracted}"
}

runtime_operation_lock_acquire() {
  local lock_path="${RUNTIME_INSTALL_HOME}/.product-operation.lock"
  local pid_path="${lock_path}/pid"
  local existing_pid=""
  local attempt

  runtime_secure_owned_directory_verify "${RUNTIME_INSTALL_HOME}" || return 1
  for attempt in 1 2; do
    if /bin/mkdir "${lock_path}" 2>/dev/null; then
      /bin/chmod 0700 "${lock_path}"
      (umask 077; printf '%s\n' "$$" > "${pid_path}")
      RUNTIME_OPERATION_LOCK="${lock_path}"
      export RUNTIME_OPERATION_LOCK
      return 0
    fi

    runtime_secure_owned_directory_verify "${lock_path}" || return 1
    if [[ -f "${pid_path}" && ! -L "${pid_path}" && -O "${pid_path}" ]]; then
      IFS= read -r existing_pid < "${pid_path}" || true
    fi
    if [[ "${existing_pid}" =~ ^[1-9][0-9]*$ ]] \
      && kill -0 "${existing_pid}" 2>/dev/null; then
      printf 'Another product management operation is running (pid %s).\n' \
        "${existing_pid}" >&2
      return 1
    fi
    if [[ "${attempt}" -eq 1 ]]; then
      if [[ -e "${pid_path}" || -L "${pid_path}" ]]; then
        if [[ ! -f "${pid_path}" || -L "${pid_path}" || ! -O "${pid_path}" ]]; then
          printf 'Stale product operation lock is unsafe.\n' >&2
          return 1
        fi
        /bin/rm -f -- "${pid_path}"
      fi
      if ! /bin/rmdir "${lock_path}" 2>/dev/null; then
        printf 'Stale product operation lock could not be removed safely.\n' >&2
        return 1
      fi
    fi
  done
  printf 'Could not acquire the product operation lock.\n' >&2
  return 1
}

runtime_operation_lock_release() {
  local lock_path="${RUNTIME_OPERATION_LOCK:-}"
  local expected_path="${RUNTIME_INSTALL_HOME}/.product-operation.lock"
  local pid_path

  [[ -n "${lock_path}" ]] || return 0
  if [[ "${lock_path}" != "${expected_path}" ]]; then
    printf 'Refusing to release an unexpected product operation lock.\n' >&2
    return 1
  fi
  if [[ ! -e "${lock_path}" && ! -L "${lock_path}" ]]; then
    RUNTIME_OPERATION_LOCK=""
    export RUNTIME_OPERATION_LOCK
    return 0
  fi
  runtime_secure_owned_directory_verify "${lock_path}" || return 1
  pid_path="${lock_path}/pid"
  if [[ ! -f "${pid_path}" || -L "${pid_path}" || ! -O "${pid_path}" \
    || "$(command cat "${pid_path}")" != "$$" ]]; then
    printf 'Refusing to release a product operation lock not owned by this process.\n' >&2
    return 1
  fi
  /bin/rm -f -- "${pid_path}"
  /bin/rmdir "${lock_path}"
  RUNTIME_OPERATION_LOCK=""
  export RUNTIME_OPERATION_LOCK
}

runtime_owned_tree_remove() {
  local target_path="$1"

  case "${target_path}" in
    "${RUNTIME_INSTALL_HOME}/"*) ;;
    *)
      printf 'Refusing to remove a path outside the Runtime root.\n' >&2
      return 1
      ;;
  esac
  if [[ ! -e "${target_path}" && ! -L "${target_path}" ]]; then
    return 0
  fi
  runtime_secure_owned_directory_verify "${target_path}" || return 1
  /bin/rm -rf -- "${target_path}"
}

runtime_receipt_path_validate() {
  local receipt_path="$1"

  if [[ -L "${receipt_path}" || ( -e "${receipt_path}" && ! -f "${receipt_path}" ) ]]; then
    printf 'Runtime receipt path is unsafe: %s\n' "${receipt_path}" >&2
    return 1
  fi
}

runtime_receipt_write() {
  local receipt_path="$1"
  local temporary_receipt

  runtime_receipt_path_validate "${receipt_path}" || return 1
  temporary_receipt="$(mktemp "${RUNTIME_INSTALL_HOME}/.runtime-receipt.XXXXXX")"
  chmod 0600 "${temporary_receipt}"
  if ! {
    printf 'RECEIPT_SCHEMA="1"\n'
    printf 'RUNTIME_REPOSITORY="%s"\n' "${RUNTIME_REPOSITORY}"
    printf 'RUNTIME_COMMIT="%s"\n' "${RUNTIME_COMMIT}"
    printf 'RUNTIME_TREE="%s"\n' "${RUNTIME_TREE}"
    printf 'RUNTIME_PROJECT_NAME="%s"\n' "${RUNTIME_PROJECT_NAME}"
    printf 'RUNTIME_PROJECT_VERSION="%s"\n' "${RUNTIME_PROJECT_VERSION}"
  } > "${temporary_receipt}"; then
    rm -f -- "${temporary_receipt}"
    return 1
  fi
  if ! mv -f "${temporary_receipt}" "${receipt_path}"; then
    rm -f -- "${temporary_receipt}"
    return 1
  fi
}

runtime_receipt_verify() {
  local receipt_path="$1"
  local expected actual

  if [[ ! -f "${receipt_path}" || -L "${receipt_path}" || ! -O "${receipt_path}" ]]; then
    printf 'Pinned Runtime installation receipt is missing or unsafe: %s\n' \
      "${receipt_path}" >&2
    return 1
  fi
  expected="$(
    printf 'RECEIPT_SCHEMA="1"\n'
    printf 'RUNTIME_REPOSITORY="%s"\n' "${RUNTIME_REPOSITORY}"
    printf 'RUNTIME_COMMIT="%s"\n' "${RUNTIME_COMMIT}"
    printf 'RUNTIME_TREE="%s"\n' "${RUNTIME_TREE}"
    printf 'RUNTIME_PROJECT_NAME="%s"\n' "${RUNTIME_PROJECT_NAME}"
    printf 'RUNTIME_PROJECT_VERSION="%s"\n' "${RUNTIME_PROJECT_VERSION}"
  )"
  actual="$(command cat "${receipt_path}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'Installed Runtime does not match runtime.lock.\n' >&2
    return 1
  fi
}
