#!/usr/bin/env bash
set -u
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

# This command is intentionally conservative: every printed value is either a
# fixed status or validated against a small allowlist. Runtime command output,
# paths, environment variables, and personal data are never forwarded.

MODE="human"

usage() {
  cat <<'EOF'
Usage: bash scripts/diagnose.sh [--json]

Print a privacy-safe installation diagnostic for beta support.

Options:
  --json       Print the stable JSON schema instead of human-readable text.
  -h, --help   Show this help.
EOF
}

if [[ $# -gt 1 ]]; then
  printf 'Invalid arguments. Use --help for usage.\n' >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    --json)
      MODE="json"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # Do not echo an unknown argument: users sometimes paste secrets where
      # an option was expected.
      printf 'Invalid option. Use --help for usage.\n' >&2
      exit 2
      ;;
  esac
fi

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
if [[ -z "${PRODUCT_ROOT}" ]]; then
  printf 'Diagnostic could not locate the product files.\n' >&2
  exit 5
fi

if [[ ! -f "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh" \
  || -L "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh" ]]; then
  printf 'Diagnostic support files are unavailable.\n' >&2
  exit 5
fi
# shellcheck source=scripts/lib/runtime-lock.sh
if ! source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh" 2>/dev/null; then
  printf 'Diagnostic support files could not be loaded.\n' >&2
  exit 5
fi

product_version="unavailable"
expected_runtime_commit="unavailable"
macos_version="unavailable"
architecture="unsupported"
runtime_installation="unknown"
receipt_status="not_checked"
venv_identity_status="not_checked"
installed_package_version="unavailable"
package_version_status="not_checked"
cli_status="not_checked"
overall_status="diagnostic_error"
exit_code=5
platform_supported="false"
home_resolved="false"

if [[ -f "${PRODUCT_ROOT}/VERSION" && ! -L "${PRODUCT_ROOT}/VERSION" ]]; then
  IFS= read -r product_version < "${PRODUCT_ROOT}/VERSION" || true
fi
if [[ ! "${product_version}" =~ ^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$ ]]; then
  product_version="unavailable"
fi

if runtime_lock_load "${PRODUCT_ROOT}/runtime.lock" 2>/dev/null; then
  expected_runtime_commit="${RUNTIME_COMMIT:0:12}"
else
  expected_runtime_commit="unavailable"
fi

if [[ -x /usr/bin/uname ]]; then
  detected_system="$(/usr/bin/uname -s 2>/dev/null || true)"
  detected_architecture="$(/usr/bin/uname -m 2>/dev/null || true)"
else
  detected_system=""
  detected_architecture=""
fi

case "${detected_architecture}" in
  arm64|x86_64)
    architecture="${detected_architecture}"
    ;;
  *)
    architecture="unsupported"
    ;;
esac

if [[ "${detected_system}" == "Darwin" && -x /usr/bin/sw_vers ]]; then
  detected_version="$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)"
  if [[ "${detected_version}" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]]; then
    macos_version="${detected_version}"
    macos_major="${detected_version%%.*}"
    if (( macos_major >= 13 )) \
      && [[ "${architecture}" == "arm64" || "${architecture}" == "x86_64" ]]; then
      platform_supported="true"
    fi
  fi
fi

run_package_version_check() {
  local runtime_python="$1"
  local project_name="$2"

  /usr/bin/env -i \
    HOME="${HOME}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    PYTHONDONTWRITEBYTECODE="1" \
    "${runtime_python}" -I - "${project_name}" 2>/dev/null <<'PY'
import importlib.metadata
import sys

print(importlib.metadata.version(sys.argv[1]))
PY
}

run_cli_start_check() {
  local persome_bin="$1"
  local install_home="$2"
  local command_pid command_status attempts=0

  (
    exec /usr/bin/env -i \
      HOME="${HOME}" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      PERSOME_ROOT="${install_home}" \
      PYTHONDONTWRITEBYTECODE="1" \
      "${persome_bin}" --help >/dev/null 2>&1 </dev/null
  ) &
  command_pid=$!

  while kill -0 "${command_pid}" 2>/dev/null; do
    if (( attempts >= 100 )); then
      kill -TERM "${command_pid}" 2>/dev/null || true
      /bin/sleep 1
      kill -KILL "${command_pid}" 2>/dev/null || true
      break
    fi
    /bin/sleep 0.1
    attempts=$((attempts + 1))
  done
  wait "${command_pid}" 2>/dev/null
  command_status=$?
  return "${command_status}"
}

receipt_check() {
  local receipt_path="$1"
  local receipt_size

  if [[ ! -e "${receipt_path}" && ! -L "${receipt_path}" ]]; then
    printf 'not_found\n'
  elif [[ -L "${receipt_path}" || ! -f "${receipt_path}" \
    || ! -O "${receipt_path}" ]]; then
    printf 'unsafe\n'
  else
    receipt_size="$(/usr/bin/wc -c < "${receipt_path}" 2>/dev/null || true)"
    receipt_size="${receipt_size//[[:space:]]/}"
    if [[ ! "${receipt_size}" =~ ^[0-9]+$ ]] || (( receipt_size > 4096 )); then
      printf 'unsafe\n'
    elif runtime_receipt_verify "${receipt_path}" >/dev/null 2>&1; then
      printf 'match\n'
    else
      printf 'mismatch\n'
    fi
  fi
}

if [[ "${expected_runtime_commit}" != "unavailable" ]] \
  && runtime_install_home_resolve 2>/dev/null; then
  home_resolved="true"
  receipt_path="${RUNTIME_INSTALL_HOME}/product-runtime.lock"
  venv_identity_path="${RUNTIME_INSTALL_HOME}/venv/.product-runtime.lock"
  runtime_python="${RUNTIME_INSTALL_HOME}/venv/bin/python"
  persome_bin="${RUNTIME_INSTALL_HOME}/venv/bin/${RUNTIME_CLI}"

  expected_artifacts=0
  [[ -e "${receipt_path}" || -L "${receipt_path}" ]] \
    && expected_artifacts=$((expected_artifacts + 1))
  [[ -e "${venv_identity_path}" || -L "${venv_identity_path}" ]] \
    && expected_artifacts=$((expected_artifacts + 1))
  [[ -e "${runtime_python}" || -L "${runtime_python}" ]] \
    && expected_artifacts=$((expected_artifacts + 1))
  [[ -e "${persome_bin}" || -L "${persome_bin}" ]] \
    && expected_artifacts=$((expected_artifacts + 1))

  case "${expected_artifacts}" in
    0)
      runtime_installation="not_found"
      ;;
    4)
      runtime_installation="present"
      ;;
    *)
      runtime_installation="partial"
      ;;
  esac

  receipt_status="$(receipt_check "${receipt_path}")"
  venv_identity_status="$(receipt_check "${venv_identity_path}")"

  execution_identity_safe="false"
  if [[ "${receipt_status}" == "match" \
    && "${venv_identity_status}" == "match" ]]; then
    if runtime_managed_venv_artifacts_verify >/dev/null 2>&1; then
      execution_identity_safe="true"
    else
      venv_identity_status="unsafe"
    fi
  fi

  if [[ "${execution_identity_safe}" == "true" ]]; then
    detected_package_version="$(
      run_package_version_check \
        "${runtime_python}" "${RUNTIME_PROJECT_NAME}" \
        | /usr/bin/head -c 65 || true
    )"
    if [[ "${detected_package_version}" \
      =~ ^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$ ]]; then
      installed_package_version="${detected_package_version}"
      if [[ "${detected_package_version}" == "${RUNTIME_PROJECT_VERSION}" ]]; then
        package_version_status="match"
      else
        package_version_status="mismatch"
      fi
    else
      installed_package_version="unavailable"
      package_version_status="unreadable"
    fi
  elif [[ ! -e "${runtime_python}" && ! -L "${runtime_python}" ]]; then
    package_version_status="not_found"
  fi

  if [[ "${execution_identity_safe}" == "true" ]]; then
    if run_cli_start_check "${persome_bin}" "${RUNTIME_INSTALL_HOME}"; then
      cli_status="starts"
    else
      cli_status="failed"
    fi
  elif [[ ! -e "${persome_bin}" && ! -L "${persome_bin}" ]]; then
    cli_status="not_found"
  fi
fi

if [[ "${platform_supported}" != "true" ]]; then
  overall_status="unsupported_platform"
  exit_code=6
elif [[ "${product_version}" == "unavailable" \
  || "${expected_runtime_commit}" == "unavailable" \
  || "${home_resolved}" != "true" ]]; then
  overall_status="diagnostic_error"
  exit_code=5
elif [[ "${runtime_installation}" == "not_found" ]]; then
  overall_status="not_installed"
  exit_code=3
elif [[ "${receipt_status}" != "match" \
  || "${venv_identity_status}" != "match" \
  || "${package_version_status}" == "mismatch" ]]; then
  overall_status="identity_mismatch"
  exit_code=4
elif [[ "${runtime_installation}" != "present" \
  || "${package_version_status}" != "match" \
  || "${cli_status}" != "starts" ]]; then
  overall_status="unhealthy"
  exit_code=5
else
  overall_status="healthy"
  exit_code=0
fi

if [[ "${MODE}" == "json" ]]; then
  if [[ "${installed_package_version}" == "unavailable" ]]; then
    installed_version_json="null"
  else
    installed_version_json="\"${installed_package_version}\""
  fi
  cat <<EOF
{
  "schema_version": 1,
  "status": "${overall_status}",
  "product_version": "${product_version}",
  "expected_runtime_commit": "${expected_runtime_commit}",
  "macos_version": "${macos_version}",
  "architecture": "${architecture}",
  "runtime_installation": "${runtime_installation}",
  "receipt": "${receipt_status}",
  "venv_identity": "${venv_identity_status}",
  "installed_package_version": ${installed_version_json},
  "package_version": "${package_version_status}",
  "cli": "${cli_status}"
}
EOF
else
  if [[ "${installed_package_version}" == "unavailable" ]]; then
    human_installed_version="not available"
  else
    human_installed_version="${installed_package_version}"
  fi
  cat <<EOF
Personal Model product diagnostic
Status:                    ${overall_status}
Product version:           ${product_version}
Expected Runtime commit:   ${expected_runtime_commit}
macOS version:             ${macos_version}
Architecture:              ${architecture}
Runtime installation:      ${runtime_installation}
Installation receipt:      ${receipt_status}
Venv identity marker:      ${venv_identity_status}
Installed package version: ${human_installed_version}
Package version status:    ${package_version_status}
CLI startup:               ${cli_status}
EOF
fi

exit "${exit_code}"
