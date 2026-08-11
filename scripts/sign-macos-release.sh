#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_TYPE=""
ARTIFACT_PATH=""
SIGN_IDENTITY=""
TEAM_ID=""
SIGNING_KEYCHAIN=""
ENTITLEMENTS_PATH="${PRODUCT_ROOT}/apps/personal-card/macos/WhoAmI.entitlements"

usage() {
  cat <<'EOF'
Usage: bash scripts/sign-macos-release.sh options

Sign one final macOS release artifact with a Developer ID Application identity.

Required:
  --app PATH                 Sign the fully assembled Who Am I.app, or
  --dmg PATH                 Sign the final DMG before notarization.
  --sign-identity ID         Exact Developer ID Application identity name.
  --team-id TEAMID           Expected 10-character Apple Developer Team ID.

Optional:
  --keychain PATH            Explicit keychain containing the identity.
  --entitlements PATH        Approved App entitlements plist.
  -h, --help                 Show this help.

This script never accepts ad-hoc signing. Development builds use the native
builder directly; a release request without a real identity fails closed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app|--dmg)
      [[ $# -ge 2 ]] || {
        printf '%s requires a value.\n' "$1" >&2
        exit 2
      }
      if [[ -n "${ARTIFACT_TYPE}" ]]; then
        printf '%s\n' 'Choose exactly one of --app or --dmg.' >&2
        exit 2
      fi
      ARTIFACT_TYPE="${1#--}"
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --sign-identity)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--sign-identity requires a value.' >&2
        exit 2
      }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --team-id)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--team-id requires a value.' >&2
        exit 2
      }
      TEAM_ID="$2"
      shift 2
      ;;
    --keychain)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--keychain requires a value.' >&2
        exit 2
      }
      SIGNING_KEYCHAIN="$2"
      shift 2
      ;;
    --entitlements)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--entitlements requires a value.' >&2
        exit 2
      }
      ENTITLEMENTS_PATH="$2"
      shift 2
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'Developer ID signing requires macOS.' >&2
  exit 1
fi
if [[ -z "${ARTIFACT_TYPE}" || -z "${ARTIFACT_PATH}" ]]; then
  printf '%s\n' 'Choose exactly one release artifact with --app or --dmg.' >&2
  exit 2
fi
if [[ -z "${SIGN_IDENTITY}" || "${SIGN_IDENTITY}" == "-" \
  || "${SIGN_IDENTITY}" != Developer\ ID\ Application:* \
  || "${SIGN_IDENTITY}" == *[[:cntrl:]]* ]]; then
  printf '%s\n' \
    'A full Developer ID Application identity name is required.' >&2
  exit 2
fi
if [[ ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  printf '%s\n' 'Team ID must be exactly 10 uppercase letters or digits.' >&2
  exit 2
fi
if [[ -n "${SIGNING_KEYCHAIN}" \
  && ( ! -f "${SIGNING_KEYCHAIN}" || -L "${SIGNING_KEYCHAIN}" ) ]]; then
  printf '%s\n' 'The explicit signing keychain is missing or unsafe.' >&2
  exit 2
fi

identity_arguments=(-v -p codesigning)
codesign_keychain_arguments=()
if [[ -n "${SIGNING_KEYCHAIN}" ]]; then
  identity_arguments+=("${SIGNING_KEYCHAIN}")
  codesign_keychain_arguments+=(--keychain "${SIGNING_KEYCHAIN}")
fi
identity_listing="$(security find-identity "${identity_arguments[@]}")"
if ! grep -Fq -- "\"${SIGN_IDENTITY}\"" <<<"${identity_listing}"; then
  printf '%s\n' \
    'The requested Developer ID Application identity is not available.' >&2
  exit 1
fi

verify_identity() {
  local artifact="$1"
  local signature_details
  signature_details="$(codesign --display --verbose=4 "${artifact}" 2>&1)"
  if ! grep -Fq -- "TeamIdentifier=${TEAM_ID}" <<<"${signature_details}"; then
    printf '%s\n' 'Signed artifact Team ID does not match the release Team ID.' >&2
    return 1
  fi
  if ! grep -Fq -- 'Authority=Developer ID Application:' \
    <<<"${signature_details}"; then
    printf '%s\n' 'Signed artifact is not a Developer ID Application artifact.' >&2
    return 1
  fi
}

if [[ "${ARTIFACT_TYPE}" == "app" ]]; then
  if [[ ! -d "${ARTIFACT_PATH}" || -L "${ARTIFACT_PATH}" \
    || ! -x "${ARTIFACT_PATH}/Contents/MacOS/WhoAmI" \
    || ! -f "${ARTIFACT_PATH}/Contents/Info.plist" ]]; then
    printf '%s\n' 'The App bundle is missing or unsafe.' >&2
    exit 2
  fi
  if [[ ! -f "${ENTITLEMENTS_PATH}" || -L "${ENTITLEMENTS_PATH}" ]]; then
    printf '%s\n' 'The approved entitlements plist is missing or unsafe.' >&2
    exit 2
  fi
  plutil -lint "${ENTITLEMENTS_PATH}" >/dev/null

  # The current bundle has one universal executable and no nested executable
  # bundles. Refuse an unreviewed nested-code topology instead of relying on
  # --deep to guess a signing order.
  nested_code="$({
    find "${ARTIFACT_PATH}/Contents" -mindepth 1 \
      \( -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \
        -o -name '*.appex' -o -name '*.plugin' \) \
      -o -type f \( -name '*.dylib' -o -name '*.so' \) \) -print -quit
  } 2>/dev/null || true)"
  if [[ -n "${nested_code}" ]]; then
    printf 'Unreviewed nested code requires an explicit inner-first signing rule: %s\n' \
      "${nested_code}" >&2
    exit 1
  fi

  codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    "${codesign_keychain_arguments[@]}" \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS_PATH}" \
    "${ARTIFACT_PATH}"
  codesign --verify --deep --strict --verbose=2 "${ARTIFACT_PATH}"
  signature_details="$(codesign --display --verbose=4 "${ARTIFACT_PATH}" 2>&1)"
  if ! grep -Eq 'flags=.*runtime' <<<"${signature_details}"; then
    printf '%s\n' 'The App signature does not enable the hardened runtime.' >&2
    exit 1
  fi
  verify_identity "${ARTIFACT_PATH}"
else
  if [[ ! -f "${ARTIFACT_PATH}" || -L "${ARTIFACT_PATH}" \
    || "${ARTIFACT_PATH}" != *.dmg ]]; then
    printf '%s\n' 'The DMG is missing or unsafe.' >&2
    exit 2
  fi
  codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    "${codesign_keychain_arguments[@]}" \
    --timestamp \
    "${ARTIFACT_PATH}"
  codesign --verify --strict --verbose=2 "${ARTIFACT_PATH}"
  verify_identity "${ARTIFACT_PATH}"
fi

printf 'Developer ID signature verified for %s.\n' "${ARTIFACT_TYPE}"
