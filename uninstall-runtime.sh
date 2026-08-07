#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

DELETE_DATA=0
PRINT_PLAN=0
CHECK_OWNERSHIP=0

usage() {
  cat <<'EOF'
Usage: bash uninstall-runtime.sh [option]

Remove the product-managed Persome Runtime.

Options:
  --preserve-data   Remove the daemon, shim, venv, and managed Python; keep
                    ~/.persome data and stable product-management commands.
                    This is the default.
  --delete-data     Permanently delete the Runtime data root after an
                    interactive product confirmation. This is never automatic.
  --print-plan      Show the exact target and data policy without changes.
  --check-ownership Validate product ownership markers without uninstalling.
  -h, --help        Show this help.

This removes the Runtime, not future product-owned application files.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preserve-data)
      DELETE_DATA=0
      shift
      ;;
    --delete-data)
      DELETE_DATA=1
      shift
      ;;
    --print-plan)
      PRINT_PLAN=1
      shift
      ;;
    --check-ownership)
      CHECK_OWNERSHIP=1
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

runtime_lock_load "${PRODUCT_ROOT}/runtime.lock"
runtime_install_home_resolve

data_policy="preserve"
if [[ "${DELETE_DATA}" -eq 1 ]]; then
  data_policy="permanently delete after typing DELETE"
fi

printf 'Runtime project:   %s %s\n' \
  "${RUNTIME_PROJECT_NAME}" "${RUNTIME_PROJECT_VERSION}"
printf 'Runtime commit:    %s\n' "${RUNTIME_COMMIT}"
printf 'Runtime data root: %s\n' "${RUNTIME_INSTALL_HOME}"
printf 'Runtime data:      %s\n' "${data_policy}"

if [[ "${PRINT_PLAN}" -eq 1 ]]; then
  exit 0
fi

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  printf 'This beta currently supports macOS only.\n' >&2
  exit 1
fi

external_receipt="${RUNTIME_INSTALL_HOME}/product-runtime.lock"
internal_receipt="${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock"
install_intent="${RUNTIME_INSTALL_HOME}/product-runtime.installing"
uninstall_tombstone="${RUNTIME_INSTALL_HOME}/product-runtime.uninstalled"
venv_path="${RUNTIME_INSTALL_HOME}/venv"
venv_quarantine="${RUNTIME_INSTALL_HOME}/.product-runtime-venv.quarantine"
managed_python_path="${RUNTIME_INSTALL_HOME}/managed-python"
product_cache_path="${RUNTIME_INSTALL_HOME}/product-cache"
shim_path="${HOME}/.local/bin/${RUNTIME_CLI}"

if [[ ! -d "${RUNTIME_INSTALL_HOME}" || -L "${RUNTIME_INSTALL_HOME}" ]]; then
  printf 'No product-managed Runtime data root was found.\n' >&2
  exit 1
fi
runtime_secure_owned_directory_verify "${RUNTIME_INSTALL_HOME}"
runtime_operation_lock_acquire

temporary_root=""
quarantine_active=0
cleanup() {
  local cleanup_status=$?
  if [[ "${quarantine_active:-0}" -eq 1 \
    && -d "${venv_quarantine:-}" && ! -L "${venv_quarantine:-}" \
    && ! -e "${venv_path:-}" ]]; then
    /bin/mv "${venv_quarantine}" "${venv_path}" || true
  fi
  if [[ -n "${temporary_root:-}" ]]; then
    runtime_temporary_root_remove \
      "${temporary_root}" "personal-model-uninstall" || true
  fi
  runtime_operation_lock_release || true
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

runtime_receipt_path_validate "${external_receipt}"
runtime_receipt_path_validate "${internal_receipt}"
runtime_receipt_path_validate "${install_intent}"
runtime_receipt_path_validate "${uninstall_tombstone}"

ownership_state=""
if runtime_receipt_verify "${external_receipt}" >/dev/null 2>&1; then
  if runtime_receipt_verify "${internal_receipt}" >/dev/null 2>&1 \
    && runtime_managed_venv_artifacts_verify >/dev/null 2>&1; then
    ownership_state="complete"
  else
    ownership_state="recovery"
    printf '%s\n' \
      'The external product receipt matches, but the venv identity is incomplete.' \
      'The venv will be quarantined and removed without executing it.'
  fi
elif runtime_receipt_verify "${install_intent}" >/dev/null 2>&1; then
  ownership_state="recovery"
  printf 'Recovering a product-managed installation that did not finish.\n'
elif runtime_receipt_verify "${uninstall_tombstone}" >/dev/null 2>&1; then
  ownership_state="data-only"
  printf 'Found preserved data from an earlier product-managed uninstall.\n'
else
  printf '%s\n' \
    'No matching product receipt, install intent, or uninstall tombstone was found.' \
    'Refusing to remove an installation whose ownership is unverified.' >&2
  exit 1
fi

if [[ "${CHECK_OWNERSHIP}" -eq 1 ]]; then
  printf 'Runtime ownership state: %s\n' "${ownership_state}"
  exit 0
fi

if [[ "${ownership_state}" == "data-only" && "${DELETE_DATA}" -eq 0 ]]; then
  printf '%s\n' \
    'Runtime executables are already removed and personal data remains.' \
    'Use --delete-data later only if permanent deletion is intended.'
  exit 0
fi

if [[ "${DELETE_DATA}" -eq 1 ]]; then
  if [[ ! -t 0 || ! -t 1 ]]; then
    printf '%s\n' \
      'Deleting Runtime data requires an interactive terminal.' \
      'Run again from a terminal and type DELETE at the product confirmation.' >&2
    exit 2
  fi
  printf 'Type DELETE to permanently remove all Runtime data under %s: ' \
    "${RUNTIME_INSTALL_HOME}"
  IFS= read -r delete_confirmation
  if [[ "${delete_confirmation}" != "DELETE" ]]; then
    printf 'Runtime data deletion cancelled; nothing was changed.\n'
    exit 1
  fi
fi

temporary_root="$(runtime_temporary_root_create "personal-model-uninstall")"
management_root="${RUNTIME_INSTALL_HOME}/product-management"
cached_uninstaller="${management_root}/upstream-uninstall-${RUNTIME_UNINSTALLER_SHA256}.sh"
legacy_cached_uninstaller="${management_root}/upstream-uninstall.sh"
verified_uninstaller="${temporary_root}/uninstall.sh"
if [[ ! -e "${cached_uninstaller}" && ! -L "${cached_uninstaller}" \
  && ( -e "${legacy_cached_uninstaller}" \
    || -L "${legacy_cached_uninstaller}" ) ]]; then
  # Migration compatibility for pre-content-addressed foundation builds. The
  # digest check below remains mandatory before execution.
  cached_uninstaller="${legacy_cached_uninstaller}"
fi
if [[ -e "${cached_uninstaller}" || -L "${cached_uninstaller}" ]]; then
  runtime_secure_owned_directory_verify "${management_root}"
  if [[ ! -f "${cached_uninstaller}" || -L "${cached_uninstaller}" \
    || ! -O "${cached_uninstaller}" ]]; then
    printf 'Cached Runtime uninstaller is unsafe.\n' >&2
    exit 1
  fi
  cached_digest="$(
    /usr/bin/shasum -a 256 "${cached_uninstaller}" \
      | /usr/bin/awk '{print $1}'
  )"
  if [[ "${cached_digest}" != "${RUNTIME_UNINSTALLER_SHA256}" ]]; then
    printf 'Cached Runtime uninstaller digest mismatch.\n' >&2
    exit 1
  fi
  /usr/bin/install -m 0700 "${cached_uninstaller}" "${verified_uninstaller}"
else
  runtime_checkout_create "${temporary_root}/runtime"
  runtime_checkout_verify "${temporary_root}/runtime"
  /usr/bin/install -m 0700 \
    "${temporary_root}/runtime/uninstall.sh" "${verified_uninstaller}"
fi
verified_digest="$(
  /usr/bin/shasum -a 256 "${verified_uninstaller}" \
    | /usr/bin/awk '{print $1}'
)"
if [[ "${verified_digest}" != "${RUNTIME_UNINSTALLER_SHA256}" ]]; then
  printf 'Prepared Runtime uninstaller digest mismatch.\n' >&2
  exit 1
fi

if [[ -e "${shim_path}" || -L "${shim_path}" ]]; then
  if [[ -L "${shim_path}" || ! -f "${shim_path}" \
    || ! -O "${shim_path}" ]]; then
    printf 'Runtime command shim is unsafe; refusing to mutate it.\n' >&2
    exit 1
  fi
  runtime_path_reject_shared_write "${shim_path}"
fi

if [[ -e "${venv_quarantine}" || -L "${venv_quarantine}" ]]; then
  printf 'Runtime venv quarantine path already exists; refusing cleanup.\n' >&2
  exit 1
fi
if [[ -e "${venv_path}" || -L "${venv_path}" ]]; then
  runtime_secure_owned_directory_verify "${venv_path}"
  /bin/mv "${venv_path}" "${venv_quarantine}"
  quarantine_active=1
fi

uninstall_arguments=(
  --install-home "${RUNTIME_INSTALL_HOME}"
  --bin-dir "${HOME}/.local/bin"
)
if [[ "${DELETE_DATA}" -eq 1 ]]; then
  uninstall_arguments+=(--delete-data --yes)
fi

/usr/bin/env -i \
  HOME="${HOME}" \
  PATH="${RUNTIME_SYSTEM_PATH}" \
  TMPDIR="${temporary_root}" \
  PERSOME_INSTALL_HOME="${RUNTIME_INSTALL_HOME}" \
  /bin/bash "${verified_uninstaller}" "${uninstall_arguments[@]}" \
  | /usr/bin/sed \
      "\\|run 'bash uninstall.sh --delete-data --yes' to delete it explicitly|d"

if [[ "${DELETE_DATA}" -eq 0 ]]; then
  if [[ "${quarantine_active}" -eq 1 ]]; then
    runtime_owned_tree_remove "${venv_quarantine}"
    quarantine_active=0
  fi
  if [[ -e "${managed_python_path}" || -L "${managed_python_path}" ]]; then
    runtime_owned_tree_remove "${managed_python_path}"
  fi
  if [[ -e "${product_cache_path}" || -L "${product_cache_path}" ]]; then
    runtime_owned_tree_remove "${product_cache_path}"
  fi
  runtime_receipt_path_validate "${external_receipt}"
  runtime_receipt_path_validate "${install_intent}"
  runtime_receipt_path_validate "${uninstall_tombstone}"
  runtime_receipt_write "${uninstall_tombstone}"
  /bin/rm -f -- "${external_receipt}" "${install_intent}"
  printf '%s\n' \
    'Personal data remains. To delete it later, run:' \
    "  /bin/bash \"${RUNTIME_INSTALL_HOME}/product-management/uninstall-runtime.sh\" --delete-data"
else
  quarantine_active=0
fi

printf 'Product-managed Runtime uninstall finished.\n'
