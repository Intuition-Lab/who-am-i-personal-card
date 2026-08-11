#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

DMG_PATH=""
TEAM_ID=""
KEYCHAIN_PROFILE=""
SIGNING_KEYCHAIN=""
TIMEOUT="30m"

usage() {
  cat <<'EOF'
Usage: bash scripts/notarize-macos-release.sh options

Submit a signed DMG with credentials already stored in a keychain, wait for
Apple acceptance, staple the ticket, and verify the DMG and contained App.

Required:
  --dmg PATH                    Signed final DMG.
  --team-id TEAMID              Expected Apple Developer Team ID.
  --keychain-profile NAME       notarytool credential profile name.

Optional:
  --keychain PATH               Explicit keychain containing the profile.
  --timeout DURATION            notarytool wait timeout (default: 30m).
  -h, --help                    Show this help.

Raw Apple credentials are deliberately not accepted by this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--dmg requires a value.' >&2
        exit 2
      }
      DMG_PATH="$2"
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
    --keychain-profile)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--keychain-profile requires a value.' >&2
        exit 2
      }
      KEYCHAIN_PROFILE="$2"
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
    --timeout)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--timeout requires a value.' >&2
        exit 2
      }
      TIMEOUT="$2"
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
  printf '%s\n' 'Apple notarization requires macOS.' >&2
  exit 1
fi
if [[ ! -f "${DMG_PATH}" || -L "${DMG_PATH}" || "${DMG_PATH}" != *.dmg ]]; then
  printf '%s\n' 'A signed DMG is required.' >&2
  exit 2
fi
if [[ ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  printf '%s\n' 'Team ID must be exactly 10 uppercase letters or digits.' >&2
  exit 2
fi
case "${KEYCHAIN_PROFILE}" in
  ""|-*|*[!A-Za-z0-9._-]*|*[[:cntrl:]]*)
    printf '%s\n' 'The notary keychain profile name is missing or unsafe.' >&2
    exit 2
    ;;
esac
if [[ ! "${TIMEOUT}" =~ ^[1-9][0-9]*(s|m|h)?$ ]]; then
  printf '%s\n' 'The notarization timeout is invalid.' >&2
  exit 2
fi
if [[ -n "${SIGNING_KEYCHAIN}" \
  && ( ! -f "${SIGNING_KEYCHAIN}" || -L "${SIGNING_KEYCHAIN}" ) ]]; then
  printf '%s\n' 'The notary keychain is missing or unsafe.' >&2
  exit 2
fi

codesign --verify --strict --verbose=2 "${DMG_PATH}"
signature_details="$(codesign --display --verbose=4 "${DMG_PATH}" 2>&1)"
if ! grep -Fq -- "TeamIdentifier=${TEAM_ID}" <<<"${signature_details}" \
  || ! grep -Fq -- 'Authority=Developer ID Application:' \
    <<<"${signature_details}"; then
  printf '%s\n' 'The DMG does not carry the expected Developer ID signature.' >&2
  exit 1
fi

temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
if [[ "${temporary_parent}" != /* || ! -d "${temporary_parent}" \
  || ! -w "${temporary_parent}" ]]; then
  temporary_parent="/tmp"
fi
temporary_root="$(mktemp -d "${temporary_parent}/whoami-notary.XXXXXX")"
cleanup() {
  local cleanup_status=$?
  if [[ -n "${mount_point:-}" && -d "${mount_point}" ]]; then
    hdiutil detach "${mount_point}" >/dev/null 2>&1 || true
  fi
  case "${temporary_root}" in
    "${temporary_parent}"/whoami-notary.??????)
      rm -rf -- "${temporary_root}"
      ;;
    *)
      printf '%s\n' 'Refusing unsafe notarization temporary cleanup.' >&2
      cleanup_status=1
      ;;
  esac
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

notary_arguments=(
  --keychain-profile "${KEYCHAIN_PROFILE}"
  --wait
  --timeout "${TIMEOUT}"
  --output-format plist
)
if [[ -n "${SIGNING_KEYCHAIN}" ]]; then
  notary_arguments+=(--keychain "${SIGNING_KEYCHAIN}")
fi
notary_result="${temporary_root}/notary-result.plist"
xcrun notarytool submit "${DMG_PATH}" \
  "${notary_arguments[@]}" > "${notary_result}"
status="$(plutil -extract status raw -o - "${notary_result}" 2>/dev/null || true)"
if [[ "${status}" != "Accepted" ]]; then
  submission_id="$(
    plutil -extract id raw -o - "${notary_result}" 2>/dev/null || true
  )"
  if [[ -n "${submission_id}" ]]; then
    printf 'Apple notarization was not accepted; submission id: %s\n' \
      "${submission_id}" >&2
  else
    printf '%s\n' 'Apple notarization was not accepted.' >&2
  fi
  exit 1
fi

xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
codesign --verify --strict --verbose=2 "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature \
  --verbose=4 "${DMG_PATH}"
hdiutil verify "${DMG_PATH}" >/dev/null

mount_point="${temporary_root}/mounted"
mkdir "${mount_point}"
hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "${mount_point}" \
  "${DMG_PATH}" >/dev/null
app_path="${mount_point}/Who Am I.app"
if [[ ! -d "${app_path}" || -L "${app_path}" ]]; then
  printf '%s\n' 'The notarized DMG does not contain Who Am I.app.' >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "${app_path}"
spctl --assess --type execute --verbose=4 "${app_path}"

printf '%s\n' 'Apple notarization, stapling, and Gatekeeper assessment passed.'
