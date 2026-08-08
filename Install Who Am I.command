#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_MANIFEST="${PRODUCT_ROOT}/SELF-CONTAINED-SHA256SUMS"

if [[ ! -f "${PACKAGE_MANIFEST}" || -L "${PACKAGE_MANIFEST}" ]]; then
  printf '%s\n' \
    'Who Am I package verification data is missing.' \
    'Download a fresh self-contained package from the product repository.' >&2
  exit 1
fi

(
  cd "${PRODUCT_ROOT}"
  /usr/bin/shasum -a 256 --check "${PACKAGE_MANIFEST}" >/dev/null
)

exec /bin/bash "${PRODUCT_ROOT}/install.sh" --interactive
