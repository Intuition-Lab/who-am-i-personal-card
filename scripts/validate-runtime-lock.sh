#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

runtime_lock_load "${PRODUCT_ROOT}/runtime.lock"

temporary_root="$(runtime_temporary_root_create "runtime-lock-check")"
cleanup() {
  if [[ -n "${temporary_root:-}" ]]; then
    runtime_temporary_root_remove "${temporary_root}" "runtime-lock-check" || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

runtime_checkout_create "${temporary_root}/runtime"
runtime_checkout_verify "${temporary_root}/runtime"

printf 'Runtime lock verified: %s at %s\n' \
  "${RUNTIME_PROJECT_NAME} ${RUNTIME_PROJECT_VERSION}" "${RUNTIME_COMMIT}"
