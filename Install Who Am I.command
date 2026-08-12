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

/bin/bash "${PRODUCT_ROOT}/install.sh" --interactive

product_version="$(/usr/bin/tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")"
case "${product_version}" in
  ""|*[!A-Za-z0-9._-]*)
    printf '%s\n' 'Installed product version is unsafe.' >&2
    exit 1
    ;;
esac
state_root="${HOME}/Library/Application Support/Who Am I"
if [[ -e "${state_root}" || -L "${state_root}" ]]; then
  if [[ ! -d "${state_root}" || -L "${state_root}" \
    || "$(/usr/bin/stat -f '%u' "${state_root}")" != "$(/usr/bin/id -u)" ]]; then
    printf '%s\n' 'Who Am I state directory is unsafe.' >&2
    exit 1
  fi
else
  /bin/mkdir -p "${state_root}"
fi
/bin/chmod 0700 "${state_root}"
completion_path="${state_root}/installer-complete-${product_version}.txt"
completion_temporary="${completion_path}.tmp.$$"
{
  printf 'version=%s\n' "${product_version}"
  printf 'completed_at=%s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "${completion_temporary}"
/bin/chmod 0600 "${completion_temporary}"
/bin/mv "${completion_temporary}" "${completion_path}"
