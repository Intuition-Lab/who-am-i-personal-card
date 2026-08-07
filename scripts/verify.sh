#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

MODE="quick"
if [[ $# -gt 1 ]]; then
  printf 'Usage: bash scripts/verify.sh [--quick|--full]\n' >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    --quick)
      MODE="quick"
      ;;
    --full)
      MODE="full"
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash scripts/verify.sh [--quick|--full]

--quick verifies that the installed Persome CLI starts.
--full also checks Runtime health, model status, and local prerequisites.
EOF
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
fi

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

runtime_lock_load "${PRODUCT_ROOT}/runtime.lock"
runtime_install_home_resolve

persome_bin="${RUNTIME_INSTALL_HOME}/venv/bin/${RUNTIME_CLI}"
runtime_python="${RUNTIME_INSTALL_HOME}/venv/bin/python"

if ! runtime_managed_install_verify; then
  printf '%s\n' \
    'Pinned Persome installation identity or executable path is unsafe.' \
    'Rerun this product installer; no Runtime executable was started.' >&2
  exit 1
fi

installed_version="$(
  /usr/bin/env -i \
    HOME="${HOME}" \
    PATH="${RUNTIME_SYSTEM_PATH}" \
    PYTHONDONTWRITEBYTECODE="1" \
    "${runtime_python}" -I - "${RUNTIME_PROJECT_NAME}" <<'PY'
import importlib.metadata
import sys

print(importlib.metadata.version(sys.argv[1]))
PY
)"
if [[ "${installed_version}" != "${RUNTIME_PROJECT_VERSION}" ]]; then
  printf 'Installed Runtime version mismatch: expected %s, got %s\n' \
    "${RUNTIME_PROJECT_VERSION}" "${installed_version}" >&2
  exit 1
fi

/usr/bin/env -i \
  HOME="${HOME}" \
  PATH="${RUNTIME_SYSTEM_PATH}" \
  PERSOME_ROOT="${RUNTIME_INSTALL_HOME}" \
  PYTHONDONTWRITEBYTECODE="1" \
  "${persome_bin}" --help >/dev/null
printf 'CLI OK: %s %s (%s)\n' \
  "${RUNTIME_PROJECT_NAME}" "${installed_version}" "${persome_bin}"

if [[ "${MODE}" == "quick" ]]; then
  exit 0
fi

/usr/bin/env -i \
  HOME="${HOME}" \
  PATH="${RUNTIME_SYSTEM_PATH}" \
  PERSOME_ROOT="${RUNTIME_INSTALL_HOME}" \
  PYTHONDONTWRITEBYTECODE="1" \
  "${persome_bin}" doctor
/usr/bin/env -i \
  HOME="${HOME}" \
  PATH="${RUNTIME_SYSTEM_PATH}" \
  PERSOME_ROOT="${RUNTIME_INSTALL_HOME}" \
  PYTHONDONTWRITEBYTECODE="1" \
  "${persome_bin}" status
/usr/bin/env -i \
  HOME="${HOME}" \
  PATH="${RUNTIME_SYSTEM_PATH}" \
  PERSOME_ROOT="${RUNTIME_INSTALL_HOME}" \
  PYTHONDONTWRITEBYTECODE="1" \
  "${persome_bin}" model status

printf 'Full Runtime verification passed.\n'
