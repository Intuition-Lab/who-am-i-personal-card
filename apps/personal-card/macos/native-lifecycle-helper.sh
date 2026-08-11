#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

ACTION="${1:-}"
PERSOME_ROOT="${2:-}"
APP_PATH="${3:-}"

fail() {
  /usr/bin/printf '%s\n' "$*" >&2
  exit 1
}

shell_quote() {
  local value="$1"
  value="${value//\'/\'\\\'\'}"
  /usr/bin/printf "'%s'" "${value}"
}

case "${ACTION}" in
  remove-product|remove-runtime-preserve|prepare-permanent-delete) ;;
  *) fail 'Unknown native lifecycle action.' ;;
esac

case "${HOME:-}" in
  /*) ;;
  *) fail 'HOME is unavailable.' ;;
esac
if [[ ! -d "${HOME}" || -L "${HOME}" || ! -O "${HOME}" ]]; then
  fail 'HOME is not an owner-controlled directory.'
fi
HOME_REAL="$(cd "${HOME}" && pwd -P)"
if [[ "${HOME_REAL}" != "${HOME}" ]]; then
  fail 'HOME must not traverse symbolic links.'
fi

case "${PERSOME_ROOT}" in
  "${HOME}"/*) ;;
  *) fail 'Personal Model root is outside this macOS account.' ;;
esac
case "${PERSOME_ROOT}" in
  *'/../'*|*/..|*'/./'*|*/.)
    fail 'Personal Model root contains unsafe path components.'
    ;;
esac

EXPECTED_APP_PATH="${HOME}/Applications/Who Am I.app"
if [[ "${APP_PATH}" != "${EXPECTED_APP_PATH}" ]]; then
  fail 'Who Am I App path is not the managed installation target.'
fi

PRODUCT_APP_ROOT="${PERSOME_ROOT}/product-app"
MANAGEMENT_ROOT="${PERSOME_ROOT}/product-management"
UNINSTALLER="${MANAGEMENT_ROOT}/uninstall-runtime.sh"
SUPPORT_ROOT="${HOME}/Library/Application Support/Who Am I"

validate_app() {
  local plist="${APP_PATH}/Contents/Info.plist"
  if [[ ! -d "${APP_PATH}" || -L "${APP_PATH}" \
    || ! -f "${plist}" || -L "${plist}" \
    || ! -O "${APP_PATH}" ]]; then
    fail 'Who Am I.app is missing or is not an owner-controlled product App.'
  fi
  if [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${plist}" 2>/dev/null || true)" \
    != 'ai.intuition.whoami' \
    || "$(/usr/bin/plutil -extract WhoAmIManagedInstall raw -o - "${plist}" 2>/dev/null || true)" \
    != 'true' ]]; then
    fail 'Who Am I.app does not carry the managed-install identity.'
  fi
}

validate_product_root_if_present() {
  local product_mode
  if [[ -e "${PRODUCT_APP_ROOT}" || -L "${PRODUCT_APP_ROOT}" ]]; then
    if [[ ! -d "${PRODUCT_APP_ROOT}" || -L "${PRODUCT_APP_ROOT}" \
      || ! -O "${PRODUCT_APP_ROOT}" ]]; then
      fail 'Product code directory is unsafe.'
    fi
    product_mode="$(/usr/bin/stat -f '%OLp' "${PRODUCT_APP_ROOT}")"
    if [[ ! "${product_mode}" =~ ^[0-7]{3,4}$ ]] \
      || (( (8#${product_mode} & 8#22) != 0 )); then
      fail 'Product code directory is group- or world-writable.'
    fi
  fi
}

remove_product_files() {
  validate_app
  validate_product_root_if_present
  /bin/sleep 1
  if [[ -d "${PRODUCT_APP_ROOT}" && ! -L "${PRODUCT_APP_ROOT}" ]]; then
    /bin/rm -rf -- "${PRODUCT_APP_ROOT}"
  fi
  if [[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]]; then
    /bin/rm -rf -- "${APP_PATH}"
  fi
}

case "${ACTION}" in
  remove-product)
    remove_product_files
    /usr/bin/printf '%s\n' \
      'Who Am I App and product code were removed.' \
      'Personal Model data and the local Card profile were preserved.'
    ;;
  remove-runtime-preserve)
    if [[ ! -f "${UNINSTALLER}" || -L "${UNINSTALLER}" \
      || ! -x "${UNINSTALLER}" || ! -O "${UNINSTALLER}" ]]; then
      fail 'Verified product-managed Runtime uninstaller is unavailable.'
    fi
    /bin/bash "${UNINSTALLER}" --check-ownership >/dev/null
    /bin/bash "${UNINSTALLER}" --preserve-data
    remove_product_files
    /usr/bin/printf '%s\n' \
      'Who Am I and product-managed Runtime executables were removed.' \
      'Personal Model data and the local Card profile were preserved.'
    ;;
  prepare-permanent-delete)
    validate_app
    validate_product_root_if_present
    if [[ ! -f "${UNINSTALLER}" || -L "${UNINSTALLER}" \
      || ! -x "${UNINSTALLER}" || ! -O "${UNINSTALLER}" ]]; then
      fail 'Verified product-managed Runtime uninstaller is unavailable.'
    fi
    # This ownership check is the boundary that prevents an App connected to
    # an independently managed Personal Model from deleting it.
    /bin/bash "${UNINSTALLER}" --check-ownership >/dev/null
    /bin/mkdir -p "${SUPPORT_ROOT}"
    /bin/chmod 0700 "${SUPPORT_ROOT}"
    DELETE_COMMAND="${SUPPORT_ROOT}/Permanently Delete Personal Model.command"
    {
      /usr/bin/printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'umask 077'
      /usr/bin/printf 'PERSOME_ROOT=%s\n' "$(shell_quote "${PERSOME_ROOT}")"
      /usr/bin/printf 'APP_PATH=%s\n' "$(shell_quote "${APP_PATH}")"
      /usr/bin/printf 'SUPPORT_ROOT=%s\n' "$(shell_quote "${SUPPORT_ROOT}")"
      # These variables are deliberately expanded later by the generated,
      # owner-only confirmation command rather than by this helper.
      # shellcheck disable=SC2016
      /usr/bin/printf '%s\n' \
        'UNINSTALLER="${PERSOME_ROOT}/product-management/uninstall-runtime.sh"' \
        '/bin/bash "${UNINSTALLER}" --delete-data' \
        '/bin/sleep 1' \
        'if [[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]]; then /bin/rm -rf -- "${APP_PATH}"; fi' \
        'if [[ -d "${SUPPORT_ROOT}" && ! -L "${SUPPORT_ROOT}" ]]; then /bin/rm -rf -- "${SUPPORT_ROOT}"; fi' \
        '/usr/bin/printf "Who Am I and Personal Model data were permanently removed.\\n"'
    } > "${DELETE_COMMAND}"
    /bin/chmod 0700 "${DELETE_COMMAND}"
    /usr/bin/printf '%s\n' "${DELETE_COMMAND}"
    ;;
esac
