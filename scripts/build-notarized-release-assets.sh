#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_environment=(
  WHOAMI_APPLE_DEVELOPER_ID_P12_BASE64
  WHOAMI_APPLE_DEVELOPER_ID_P12_PASSWORD
  WHOAMI_APPLE_SIGNING_KEYCHAIN_PASSWORD
  WHOAMI_APPLE_SIGN_IDENTITY
  WHOAMI_APPLE_TEAM_ID
  WHOAMI_APPLE_NOTARY_API_KEY_BASE64
  WHOAMI_APPLE_NOTARY_KEY_ID
  WHOAMI_APPLE_NOTARY_ISSUER_ID
)
for environment_name in "${required_environment[@]}"; do
  if [[ -z "${!environment_name:-}" ]]; then
    printf 'Required Apple release environment is missing: %s\n' \
      "${environment_name}" >&2
    exit 2
  fi
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'A notarized release must be built on macOS.' >&2
  exit 1
fi
if [[ "${WHOAMI_APPLE_SIGN_IDENTITY}" != Developer\ ID\ Application:* \
  || "${WHOAMI_APPLE_SIGN_IDENTITY}" == *[[:cntrl:]]* ]]; then
  printf '%s\n' \
    'WHOAMI_APPLE_SIGN_IDENTITY must be a Developer ID Application identity.' >&2
  exit 2
fi
if [[ ! "${WHOAMI_APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  printf '%s\n' 'WHOAMI_APPLE_TEAM_ID is invalid.' >&2
  exit 2
fi
if [[ ! "${WHOAMI_APPLE_NOTARY_KEY_ID}" =~ ^[A-Z0-9]{10}$ \
  || ! "${WHOAMI_APPLE_NOTARY_ISSUER_ID}" \
    =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  printf '%s\n' 'App Store Connect notary API key metadata is invalid.' >&2
  exit 2
fi

temporary_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
temporary_parent="${temporary_parent%/}"
if [[ "${temporary_parent}" != /* || ! -d "${temporary_parent}" \
  || ! -w "${temporary_parent}" ]]; then
  temporary_parent="/tmp"
fi
temporary_root="$(mktemp -d "${temporary_parent}/whoami-apple-release.XXXXXX")"
signing_keychain="${temporary_root}/release-signing.keychain-db"
certificate_path="${temporary_root}/developer-id.p12"
notary_key_path="${temporary_root}/AuthKey.p8"
notary_profile="whoami-release-$$"

cleanup() {
  local cleanup_status=$?
  security delete-keychain "${signing_keychain}" >/dev/null 2>&1 || true
  case "${temporary_root}" in
    "${temporary_parent}"/whoami-apple-release.??????)
      rm -rf -- "${temporary_root}"
      ;;
    *)
      printf '%s\n' 'Refusing unsafe Apple release temporary cleanup.' >&2
      cleanup_status=1
      ;;
  esac
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf '%s' "${WHOAMI_APPLE_DEVELOPER_ID_P12_BASE64}" \
  | base64 --decode > "${certificate_path}"
printf '%s' "${WHOAMI_APPLE_NOTARY_API_KEY_BASE64}" \
  | base64 --decode > "${notary_key_path}"
chmod 0600 "${certificate_path}" "${notary_key_path}"

security create-keychain \
  -p "${WHOAMI_APPLE_SIGNING_KEYCHAIN_PASSWORD}" \
  "${signing_keychain}"
security set-keychain-settings -lut 21600 "${signing_keychain}"
security unlock-keychain \
  -p "${WHOAMI_APPLE_SIGNING_KEYCHAIN_PASSWORD}" \
  "${signing_keychain}"
security import "${certificate_path}" \
  -k "${signing_keychain}" \
  -P "${WHOAMI_APPLE_DEVELOPER_ID_P12_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "${WHOAMI_APPLE_SIGNING_KEYCHAIN_PASSWORD}" \
  "${signing_keychain}" >/dev/null

identity_listing="$(
  security find-identity -v -p codesigning "${signing_keychain}"
)"
if ! grep -Fq -- "\"${WHOAMI_APPLE_SIGN_IDENTITY}\"" \
  <<<"${identity_listing}"; then
  printf '%s\n' \
    'Imported certificate does not contain the configured signing identity.' >&2
  exit 1
fi

xcrun notarytool store-credentials "${notary_profile}" \
  --key "${notary_key_path}" \
  --key-id "${WHOAMI_APPLE_NOTARY_KEY_ID}" \
  --issuer "${WHOAMI_APPLE_NOTARY_ISSUER_ID}" \
  --keychain "${signing_keychain}" \
  --validate >/dev/null

cd "${PRODUCT_ROOT}"
bash scripts/build-release-assets.sh \
  "$@" \
  --release-signing \
  --sign-identity "${WHOAMI_APPLE_SIGN_IDENTITY}" \
  --team-id "${WHOAMI_APPLE_TEAM_ID}" \
  --notary-profile "${notary_profile}" \
  --signing-keychain "${signing_keychain}"

printf '%s\n' \
  'Built Developer ID signed, notarized, stapled release assets.'
