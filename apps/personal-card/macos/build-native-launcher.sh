#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PATH="${SCRIPT_DIR}/WhoAmIApp.swift"
NATIVE_UI_SOURCE_PATH="${SCRIPT_DIR}/WhoAmINativeUI.swift"
PRODUCT_ROOT=""
PERSOME_ROOT=""
PRODUCT_VERSION=""
OUTPUT_DIRECTORY="${SCRIPT_DIR}/build"
SIGN_IDENTITY="-"
TEAM_ID=""
ENTITLEMENTS_PATH="${SCRIPT_DIR}/WhoAmI.entitlements"
BOOTSTRAP_INSTALL=0

usage() {
  /usr/bin/printf '%s\n' \
    'Usage: build-native-launcher.sh options' \
    '' \
    'Required:' \
    '  --product-version VERSION Expected /api/setup/status product version.' \
    '' \
    'Optional:' \
    '  --product-root PATH       Installed Personal Card product root.' \
    '  --persome-root PATH       Owner-local Personal Model root.' \
    '  --bootstrap               Build the DMG first-run installer App.' \
    '  --output-directory PATH   New app output parent (default: macos/build).' \
    '  --sign-identity ID        Developer ID identity (default: ad-hoc "-").' \
    '  --team-id TEAMID          Required with a Developer ID identity.' \
    '  --entitlements PATH       Approved entitlements plist.' \
    '  -h, --help                Show this help.'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --product-root)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--product-root requires a value.' >&2
        exit 2
      }
      PRODUCT_ROOT="$2"
      shift 2
      ;;
    --persome-root)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--persome-root requires a value.' >&2
        exit 2
      }
      PERSOME_ROOT="$2"
      shift 2
      ;;
    --product-version)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--product-version requires a value.' >&2
        exit 2
      }
      PRODUCT_VERSION="$2"
      shift 2
      ;;
    --output-directory)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--output-directory requires a value.' >&2
        exit 2
      }
      OUTPUT_DIRECTORY="$2"
      shift 2
      ;;
    --sign-identity)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--sign-identity requires a value.' >&2
        exit 2
      }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --team-id)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--team-id requires a value.' >&2
        exit 2
      }
      TEAM_ID="$2"
      shift 2
      ;;
    --entitlements)
      [[ $# -ge 2 ]] || {
        /usr/bin/printf '%s\n' '--entitlements requires a value.' >&2
        exit 2
      }
      ENTITLEMENTS_PATH="$2"
      shift 2
      ;;
    --bootstrap)
      BOOTSTRAP_INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      /usr/bin/printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${BOOTSTRAP_INSTALL}" -eq 1 ]]; then
  if [[ -n "${PRODUCT_ROOT}" || -n "${PERSOME_ROOT}" ]]; then
    /usr/bin/printf '%s\n' \
      '--bootstrap cannot be combined with installed product paths.' >&2
    exit 2
  fi
else
  case "${PRODUCT_ROOT}" in
    /*) ;;
    *)
      /usr/bin/printf '%s\n' '--product-root must be an absolute path.' >&2
      exit 2
      ;;
  esac
  case "${PERSOME_ROOT}" in
    /*) ;;
    *)
      /usr/bin/printf '%s\n' '--persome-root must be an absolute path.' >&2
      exit 2
      ;;
  esac
fi
case "${PRODUCT_VERSION}" in
  ""|*[[:cntrl:]]*)
    /usr/bin/printf '%s\n' '--product-version is missing or unsafe.' >&2
    exit 2
    ;;
esac
case "${OUTPUT_DIRECTORY}" in
  ""|/|*[[:cntrl:]]*)
    /usr/bin/printf '%s\n' '--output-directory is unsafe.' >&2
    exit 2
    ;;
esac
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  if [[ -n "${TEAM_ID}" ]]; then
    /usr/bin/printf '%s\n' \
      '--team-id cannot be used with an ad-hoc signature.' >&2
    exit 2
  fi
else
  if [[ "${SIGN_IDENTITY}" != Developer\ ID\ Application:* \
    || "${SIGN_IDENTITY}" == *[[:cntrl:]]* ]]; then
    /usr/bin/printf '%s\n' \
      'A full Developer ID Application identity name is required.' >&2
    exit 2
  fi
  if [[ ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
    /usr/bin/printf '%s\n' \
      'Team ID must be exactly 10 uppercase letters or digits.' >&2
    exit 2
  fi
  if [[ ! -f "${ENTITLEMENTS_PATH}" || -L "${ENTITLEMENTS_PATH}" ]]; then
    /usr/bin/printf '%s\n' \
      'The approved entitlements plist is missing or unsafe.' >&2
    exit 2
  fi
  /usr/bin/plutil -lint "${ENTITLEMENTS_PATH}" >/dev/null
fi

for source_file in "${SOURCE_PATH}" "${NATIVE_UI_SOURCE_PATH}"; do
  if [[ ! -f "${source_file}" || -L "${source_file}" ]]; then
    /usr/bin/printf 'Swift source is missing or unsafe: %s\n' "${source_file}" >&2
    exit 1
  fi
done

/bin/mkdir -p "${OUTPUT_DIRECTORY}"
OUTPUT_DIRECTORY="$(cd "${OUTPUT_DIRECTORY}" && pwd -P)"
APP_PATH="${OUTPUT_DIRECTORY}/Who Am I.app"
if [[ -e "${APP_PATH}" || -L "${APP_PATH}" ]]; then
  /usr/bin/printf 'Output app already exists: %s\n' "${APP_PATH}" >&2
  exit 1
fi
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
if [[ "${TMP_BASE}" != /* || ! -d "${TMP_BASE}" || ! -w "${TMP_BASE}" ]]; then
  TMP_BASE="/tmp"
fi
TEMPORARY_ROOT="$(/usr/bin/mktemp -d "${TMP_BASE}/whoami-native-launcher.XXXXXX")"
cleanup() {
  local status=$?
  case "${TEMPORARY_ROOT}" in
    "${TMP_BASE}"/whoami-native-launcher.??????)
      /bin/rm -rf -- "${TEMPORARY_ROOT}"
      ;;
    *)
      /usr/bin/printf 'Refusing unsafe temporary cleanup: %s\n' \
        "${TEMPORARY_ROOT}" >&2
      status=1
      ;;
  esac
  return "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(/usr/bin/xcrun --sdk macosx --find swiftc)"
STAGING_APP="${TEMPORARY_ROOT}/Who Am I.app"
CONTENTS="${STAGING_APP}/Contents"
MACOS_DIRECTORY="${CONTENTS}/MacOS"
/bin/mkdir -p "${MACOS_DIRECTORY}"

for architecture in arm64 x86_64; do
  "${SWIFTC}" \
    -sdk "${SDK_PATH}" \
    -target "${architecture}-apple-macos13.0" \
    -Onone \
    -framework Cocoa \
    -framework SwiftUI \
    "${SOURCE_PATH}" \
    "${NATIVE_UI_SOURCE_PATH}" \
    -o "${TEMPORARY_ROOT}/WhoAmI-${architecture}"
done

/usr/bin/lipo -create \
  "${TEMPORARY_ROOT}/WhoAmI-arm64" \
  "${TEMPORARY_ROOT}/WhoAmI-x86_64" \
  -output "${MACOS_DIRECTORY}/WhoAmI"
/bin/chmod 0755 "${MACOS_DIRECTORY}/WhoAmI"

INFO_PLIST="${CONTENTS}/Info.plist"
/usr/bin/plutil -create xml1 "${INFO_PLIST}"
/usr/bin/plutil -insert CFBundleName -string "Who Am I" "${INFO_PLIST}"
/usr/bin/plutil -insert CFBundleDisplayName -string "Who Am I" "${INFO_PLIST}"
/usr/bin/plutil -insert CFBundleIdentifier -string "ai.intuition.whoami" "${INFO_PLIST}"
/usr/bin/plutil -insert CFBundleExecutable -string "WhoAmI" "${INFO_PLIST}"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "${INFO_PLIST}"
MARKETING_VERSION="${PRODUCT_VERSION#v}"
MARKETING_VERSION="${MARKETING_VERSION%%-*}"
case "${PRODUCT_VERSION}" in
  *-beta.[0-9]*)
    BUILD_VERSION="${MARKETING_VERSION%.*}.${PRODUCT_VERSION##*beta.}"
    ;;
  *)
    BUILD_VERSION="${MARKETING_VERSION}"
    ;;
esac
/usr/bin/plutil -insert CFBundleShortVersionString \
  -string "${MARKETING_VERSION}" "${INFO_PLIST}"
/usr/bin/plutil -insert CFBundleVersion -string "${BUILD_VERSION}" "${INFO_PLIST}"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "${INFO_PLIST}"
/usr/bin/plutil -insert LSApplicationCategoryType \
  -string "public.app-category.productivity" "${INFO_PLIST}"
/usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "${INFO_PLIST}"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "${INFO_PLIST}"
/usr/bin/plutil -insert LSUIElement -bool true "${INFO_PLIST}"
/usr/bin/plutil -insert LSMultipleInstancesProhibited -bool true "${INFO_PLIST}"
/usr/bin/plutil -insert NSAppTransportSecurity -dictionary "${INFO_PLIST}"
/usr/bin/plutil -insert NSAppTransportSecurity.NSAllowsLocalNetworking \
  -bool true "${INFO_PLIST}"
if [[ "${BOOTSTRAP_INSTALL}" -eq 1 ]]; then
  /usr/bin/plutil -insert WhoAmIBootstrapInstall -bool true "${INFO_PLIST}"
else
  /usr/bin/plutil -insert WhoAmIProductRoot \
    -string "${PRODUCT_ROOT}" "${INFO_PLIST}"
  /usr/bin/plutil -insert WhoAmIPersomeRoot \
    -string "${PERSOME_ROOT}" "${INFO_PLIST}"
fi
/usr/bin/plutil -insert WhoAmIProductVersion \
  -string "${PRODUCT_VERSION}" "${INFO_PLIST}"
/usr/bin/plutil -insert WhoAmIManagedInstall -bool true "${INFO_PLIST}"
/usr/bin/plutil -lint "${INFO_PLIST}" >/dev/null

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  /usr/bin/codesign \
    --force \
    --sign - \
    --timestamp=none \
    "${STAGING_APP}"
else
  /usr/bin/codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS_PATH}" \
    "${STAGING_APP}"
fi
/usr/bin/codesign --verify --deep --strict "${STAGING_APP}"
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
  signature_details="$(
    /usr/bin/codesign --display --verbose=4 "${STAGING_APP}" 2>&1
  )"
  if ! /usr/bin/grep -Fq -- "TeamIdentifier=${TEAM_ID}" \
    <<<"${signature_details}" \
    || ! /usr/bin/grep -Fq -- 'Authority=Developer ID Application:' \
      <<<"${signature_details}" \
    || ! /usr/bin/grep -Eq 'flags=.*runtime' <<<"${signature_details}"; then
    /usr/bin/printf '%s\n' \
      'Developer ID signature identity, Team ID, or hardened runtime is invalid.' >&2
    exit 1
  fi
fi
/usr/bin/lipo "${MACOS_DIRECTORY}/WhoAmI" -verify_arch arm64 x86_64

/bin/mv "${STAGING_APP}" "${APP_PATH}"
/usr/bin/printf 'Built universal Who Am I launcher: %s\n' "${APP_PATH}"
