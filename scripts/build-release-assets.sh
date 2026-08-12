#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

REPOSITORY=""
TAG=""
COMMIT=""
SOURCE_REF="HEAD"
OUTPUT_DIRECTORY=""
RUNTIME_CHECKOUT=""
RELEASE_SIGNING=0
SIGN_IDENTITY=""
TEAM_ID=""
NOTARY_KEYCHAIN_PROFILE=""
SIGNING_KEYCHAIN=""

usage() {
  cat <<'EOF'
Usage: bash scripts/build-release-assets.sh options

Build the exact five self-contained assets consumed by the GitHub Release
workflow.

Required:
  --repository OWNER/REPOSITORY
  --tag TAG
  --commit FULL_COMMIT
  --output-directory PATH

Optional:
  --source-ref GIT_REF  Git commit/ref to validate (default: HEAD).
  --runtime-checkout PATH
                        Reuse an already verified pinned Runtime checkout.
  --release-signing     Require Developer ID signing and Apple notarization.
  --sign-identity ID    Developer ID Application identity name.
  --team-id TEAMID      Apple Developer Team ID.
  --notary-profile NAME notarytool profile already stored in Keychain.
  --signing-keychain PATH
                        Explicit temporary signing/notary keychain.
  -h, --help            Show this help.

The output directory must not already exist. The source ref must resolve to the
declared commit and match the tracked working tree. The Personal Model source
is embedded at build time; release installation never contacts its repository.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--repository requires a value.' >&2
        exit 2
      }
      REPOSITORY="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--tag requires a value.' >&2
        exit 2
      }
      TAG="$2"
      shift 2
      ;;
    --commit)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--commit requires a value.' >&2
        exit 2
      }
      COMMIT="$2"
      shift 2
      ;;
    --source-ref)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--source-ref requires a value.' >&2
        exit 2
      }
      SOURCE_REF="$2"
      shift 2
      ;;
    --output-directory)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--output-directory requires a value.' >&2
        exit 2
      }
      OUTPUT_DIRECTORY="$2"
      shift 2
      ;;
    --runtime-checkout)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--runtime-checkout requires a value.' >&2
        exit 2
      }
      RUNTIME_CHECKOUT="$2"
      shift 2
      ;;
    --release-signing)
      RELEASE_SIGNING=1
      shift
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
    --notary-profile)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--notary-profile requires a value.' >&2
        exit 2
      }
      NOTARY_KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --signing-keychain)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--signing-keychain requires a value.' >&2
        exit 2
      }
      SIGNING_KEYCHAIN="$2"
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

if [[ ! "${REPOSITORY}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ \
  || "${REPOSITORY}" == *".."* ]]; then
  printf 'Repository must be an explicit OWNER/REPOSITORY name.\n' >&2
  exit 2
fi
if [[ ! "${COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'Release commit must be a full lowercase Git commit ID.\n' >&2
  exit 2
fi
case "${SOURCE_REF}" in
  ""|-*|*[[:cntrl:]]*)
    printf 'Source ref is unsafe.\n' >&2
    exit 2
    ;;
esac
case "${OUTPUT_DIRECTORY}" in
  *[[:cntrl:]]*)
    printf 'Output directory contains unsafe characters.\n' >&2
    exit 2
    ;;
esac
if [[ -z "${OUTPUT_DIRECTORY}" || "${OUTPUT_DIRECTORY}" == "/" \
  || -e "${OUTPUT_DIRECTORY}" || -L "${OUTPUT_DIRECTORY}" ]]; then
  printf 'Output directory must be a new, non-root path.\n' >&2
  exit 2
fi
if [[ "${RELEASE_SIGNING}" -eq 1 ]]; then
  if [[ -z "${SIGN_IDENTITY}" || "${SIGN_IDENTITY}" == "-" \
    || "${SIGN_IDENTITY}" != Developer\ ID\ Application:* \
    || ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s\n' \
      'Release assets require a Developer ID identity and valid Team ID.' >&2
    exit 2
  fi
  case "${NOTARY_KEYCHAIN_PROFILE}" in
    ""|-*|*[!A-Za-z0-9._-]*|*[[:cntrl:]]*)
      printf '%s\n' \
        'Release assets require a safe notary Keychain profile name.' >&2
      exit 2
      ;;
  esac
  if [[ -n "${SIGNING_KEYCHAIN}" \
    && ( ! -f "${SIGNING_KEYCHAIN}" || -L "${SIGNING_KEYCHAIN}" ) ]]; then
    printf '%s\n' 'The explicit signing keychain is missing or unsafe.' >&2
    exit 2
  fi
elif [[ -n "${SIGN_IDENTITY}" || -n "${TEAM_ID}" \
  || -n "${NOTARY_KEYCHAIN_PROFILE}" || -n "${SIGNING_KEYCHAIN}" ]]; then
  printf '%s\n' \
    'Signing inputs require the explicit --release-signing mode.' >&2
  exit 2
fi
output_parent="${OUTPUT_DIRECTORY%/*}"
if [[ "${output_parent}" == "${OUTPUT_DIRECTORY}" ]]; then
  output_parent="."
fi
if [[ ! -d "${output_parent}" || -L "${output_parent}" \
  || ! -w "${output_parent}" ]]; then
  printf 'Output parent must be an existing writable directory.\n' >&2
  exit 2
fi

cd "${PRODUCT_ROOT}"
bash scripts/release-readiness.sh --check >/dev/null
version="$(tr -d '[:space:]' < VERSION)"
if [[ "${TAG}" != "v${version}" ]]; then
  printf 'Tag %s does not match product version %s.\n' \
    "${TAG}" "${version}" >&2
  exit 2
fi

source_commit="$(
  /usr/bin/git rev-parse --verify --end-of-options "${SOURCE_REF}^{commit}"
)"
if [[ "${source_commit}" != "${COMMIT}" ]]; then
  printf 'Source ref resolves to %s instead of declared commit %s.\n' \
    "${source_commit}" "${COMMIT}" >&2
  exit 1
fi

release_manifest="${PRODUCT_ROOT}/release.manifest"
if [[ ! -f "${release_manifest}" || -L "${release_manifest}" ]]; then
  printf 'Release manifest is missing or unsafe.\n' >&2
  exit 1
fi
manifest_seen="|"
manifest_line_number=0
while IFS= read -r manifest_line || [[ -n "${manifest_line}" ]]; do
  manifest_line_number=$((manifest_line_number + 1))
  case "${manifest_line}" in
    ""|\#*) continue ;;
  esac
  if [[ ! "${manifest_line}" =~ ^\??[A-Za-z0-9._-]+$ ]]; then
    printf 'Unsafe release manifest entry at line %s.\n' \
      "${manifest_line_number}" >&2
    exit 1
  fi
  release_path="${manifest_line#\?}"
  case "${release_path}" in
    .|..|.git|.github|tests|work|outputs|dist)
      printf 'Forbidden release manifest entry: %s\n' "${release_path}" >&2
      exit 1
      ;;
  esac
  case "${manifest_seen}" in
    *"|${release_path}|"*)
      printf 'Duplicate release manifest entry: %s\n' "${release_path}" >&2
      exit 1
      ;;
  esac
  manifest_seen="${manifest_seen}${release_path}|"
  if /usr/bin/git cat-file -e \
    "${source_commit}:${release_path}" 2>/dev/null; then
    :
  elif [[ "${manifest_line}" != \?* ]]; then
    printf 'Required release manifest entry is missing: %s\n' \
      "${release_path}" >&2
    exit 1
  fi
done < "${release_manifest}"
for required_release_path in \
  .agents README.md RELEASE_STATUS PILOT_STATUS VERSION docs install.sh \
  plugins release.manifest runtime.lock scripts uninstall-runtime.sh update.sh; do
  case "${manifest_seen}" in
    *"|${required_release_path}|"*) ;;
    *)
      printf 'Release manifest omits required entry: %s\n' \
        "${required_release_path}" >&2
      exit 1
      ;;
  esac
done

while IFS= read -r -d '' tree_entry; do
  tree_mode="${tree_entry%% *}"
  tracked_path="${tree_entry#*$'\t'}"
  case "${tree_mode}" in
    100644|100755) ;;
    *)
      printf 'Release source contains a symlink, submodule, or unsafe mode: %s\n' \
        "${tracked_path}" >&2
      exit 1
      ;;
  esac
  case "${tracked_path}" in
    *[[:cntrl:]]*|work|work/*|outputs|outputs/*|dist|dist/*)
      printf 'Release source contains an excluded or unsafe path: %s\n' \
        "${tracked_path}" >&2
      exit 1
      ;;
  esac
done < <(/usr/bin/git ls-tree -r -z "${source_commit}")
if ! /usr/bin/git diff --quiet "${source_commit}" -- .; then
  printf 'Tracked working tree does not match the release source ref.\n' >&2
  exit 1
fi

# Publication assets are never built from a source tree that has not passed
# the complete Personal Model beta gate on this macOS runner.
bash scripts/beta-release-gate.sh

repository_name="${REPOSITORY#*/}"
package_name="who-am-i-${version}-self-contained-macos"
dmg_name="${package_name}.dmg"
bundle_name="${package_name}.tar.gz"
release_notes="docs/release-notes/${TAG}.md"
if [[ ! -f "${release_notes}" || -L "${release_notes}" ]]; then
  printf 'Missing version-controlled release notes: %s\n' \
    "${release_notes}" >&2
  exit 1
fi

package_build_root="$(runtime_temporary_root_create 'product-release-assets')"
cleanup() {
  local cleanup_status=$?
  runtime_temporary_root_remove \
    "${package_build_root}" "product-release-assets" || true
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

package_build_arguments=(
  --output-directory "${package_build_root}/package"
)
if [[ -n "${RUNTIME_CHECKOUT}" ]]; then
  package_build_arguments+=(--runtime-checkout "${RUNTIME_CHECKOUT}")
fi
if [[ "${RELEASE_SIGNING}" -eq 1 ]]; then
  package_build_arguments+=(
    --release-signing
    --sign-identity "${SIGN_IDENTITY}"
    --team-id "${TEAM_ID}"
    --notary-profile "${NOTARY_KEYCHAIN_PROFILE}"
  )
  if [[ -n "${SIGNING_KEYCHAIN}" ]]; then
    package_build_arguments+=(--signing-keychain "${SIGNING_KEYCHAIN}")
  fi
fi
bash scripts/build-self-contained-package.sh \
  "${package_build_arguments[@]}"
for package_asset in "${dmg_name}" "${bundle_name}"; do
  if [[ ! -f "${package_build_root}/package/${package_asset}" \
    || -L "${package_build_root}/package/${package_asset}" ]]; then
    printf 'Self-contained builder did not produce required asset: %s\n' \
      "${package_asset}" >&2
    exit 1
  fi
done

/bin/mkdir "${package_build_root}/extracted"
/usr/bin/tar -xzf \
  "${package_build_root}/package/${bundle_name}" \
  -C "${package_build_root}/extracted"
native_app_path="${package_build_root}/extracted/${package_name}/Who Am I.app"
embedded_product_path="${native_app_path}/Contents/Resources/product"
if [[ ! -d "${native_app_path}" \
  || ! -x "${native_app_path}/Contents/MacOS/WhoAmI" ]]; then
  printf 'Self-contained package does not contain the native App entry point.\n' >&2
  exit 1
fi
/usr/bin/codesign --verify --strict "${native_app_path}"
/usr/bin/lipo "${native_app_path}/Contents/MacOS/WhoAmI" \
  -verify_arch arm64 x86_64
if [[ "$(/usr/bin/plutil -extract WhoAmIBootstrapInstall raw -o - \
  "${native_app_path}/Contents/Info.plist")" != "true" ]]; then
  printf 'Release App is not configured for first-run installation.\n' >&2
  exit 1
fi
if [[ ! -x "${embedded_product_path}/Install Who Am I.command" \
  || ! -d "${embedded_product_path}/runtime-source/.git" \
  || ! -f "${embedded_product_path}/apps/personal-card/persome-card-server.mjs" ]]; then
  printf 'Self-contained App does not contain its backend and Runtime.\n' >&2
  exit 1
fi
(
  cd "${embedded_product_path}"
  /usr/bin/shasum -a 256 --check SELF-CONTAINED-SHA256SUMS >/dev/null
)

/bin/mkdir "${OUTPUT_DIRECTORY}"
/bin/cp \
  "${package_build_root}/package/${dmg_name}" \
  "${package_build_root}/package/${bundle_name}" \
  "${OUTPUT_DIRECTORY}/"

runtime_lock_load runtime.lock
{
  printf 'repository=%s\n' "${REPOSITORY}"
  printf 'tag=%s\n' "${TAG}"
  printf 'commit=%s\n' "${COMMIT}"
  printf 'version=%s\n' "${version}"
  printf 'release_status=%s\n' "$(/bin/cat RELEASE_STATUS)"
  printf 'pilot_status=%s\n' "$(/bin/cat PILOT_STATUS)"
  printf 'runtime_repository=%s\n' "${RUNTIME_REPOSITORY}"
  printf 'runtime_commit=%s\n' "${RUNTIME_COMMIT}"
  printf 'runtime_tree=%s\n' "${RUNTIME_TREE}"
  printf 'runtime_project=%s\n' "${RUNTIME_PROJECT_NAME}"
  printf 'runtime_version=%s\n' "${RUNTIME_PROJECT_VERSION}"
  printf 'runtime_delivery=embedded\n'
  printf 'native_app_included=true\n'
  printf 'native_app_entrypoint=Who Am I.app\n'
  printf 'backend_embedded_in_app=true\n'
  printf 'embedded_product_path=Who Am I.app/Contents/Resources/product\n'
  if [[ "${RELEASE_SIGNING}" -eq 1 ]]; then
    printf 'apple_signing=developer-id\n'
    printf 'apple_team_id=%s\n' "${TEAM_ID}"
    printf 'apple_dmg_notarized=true\n'
  else
    printf 'apple_signing=ad-hoc\n'
    printf 'apple_team_id=none\n'
    printf 'apple_dmg_notarized=false\n'
  fi
  printf 'dmg_asset=%s\n' "${dmg_name}"
  printf 'tar_asset=%s\n' "${bundle_name}"
} > "${OUTPUT_DIRECTORY}/RELEASE-METADATA.txt"
/bin/cp "${release_notes}" "${OUTPUT_DIRECTORY}/RELEASE-NOTES.md"

cat >> "${OUTPUT_DIRECTORY}/RELEASE-NOTES.md" <<EOF

## Exact release assets

This release contains exactly these five assets:

- \`${dmg_name}\`
- \`${bundle_name}\`
- \`RELEASE-METADATA.txt\`
- \`RELEASE-NOTES.md\`
- \`SHA256SUMS\`

### Install from a public repository

For the normal macOS flow, verify \`${dmg_name}\` against \`SHA256SUMS\`, open
the DMG, and double-click \`Who Am I.app\`. Its native first-run window opens
the verified installer and then launches the installed App. The equivalent
command-line flow is:

\`\`\`bash
(
  set -euo pipefail
  download_directory="\$(
    mktemp -d "\${TMPDIR:-/tmp}/${repository_name}-${version}-download.XXXXXX"
  )"
  cd "\${download_directory}"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/${dmg_name}"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/${bundle_name}"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/RELEASE-METADATA.txt"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/RELEASE-NOTES.md"
  curl --proto '=https' --tlsv1.2 --fail \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --location --remote-name \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/SHA256SUMS"
  test "\$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 5
  shasum -a 256 --check SHA256SUMS
  tar -xzf "${bundle_name}"
  cd "${package_name}"
  bash "Who Am I.app/Contents/Resources/product/Install Who Am I.command"
)
\`\`\`

### Install from a private repository

Install and authenticate the GitHub CLI first, then run:

\`\`\`bash
(
  set -euo pipefail
  gh auth status
  download_directory="\$(
    mktemp -d "\${TMPDIR:-/tmp}/${repository_name}-${version}-download-private.XXXXXX"
  )"
  cd "\${download_directory}"
  gh release download "${TAG}" \
    --repo "${REPOSITORY}" \
    --pattern "${dmg_name}" \
    --pattern "${bundle_name}" \
    --pattern "RELEASE-METADATA.txt" \
    --pattern "RELEASE-NOTES.md" \
    --pattern "SHA256SUMS"
  test "\$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 5
  gh release verify "${TAG}" \
    --repo "${REPOSITORY}"
  gh release verify-asset "${TAG}" "${dmg_name}" \
    --repo "${REPOSITORY}"
  gh release verify-asset "${TAG}" "${bundle_name}" \
    --repo "${REPOSITORY}"
  gh release verify-asset "${TAG}" "RELEASE-METADATA.txt" \
    --repo "${REPOSITORY}"
  gh release verify-asset "${TAG}" "RELEASE-NOTES.md" \
    --repo "${REPOSITORY}"
  gh release verify-asset "${TAG}" "SHA256SUMS" \
    --repo "${REPOSITORY}"
  shasum -a 256 --check SHA256SUMS
  tar -xzf "${bundle_name}"
  cd "${package_name}"
  bash "Who Am I.app/Contents/Resources/product/Install Who Am I.command"
)
\`\`\`
EOF

if /usr/bin/grep -Eq '<owner>|<new-product|TBD' \
  "${OUTPUT_DIRECTORY}/RELEASE-NOTES.md"; then
  printf 'Generated release notes contain an unresolved placeholder.\n' >&2
  exit 1
fi
for required_recipe_marker in \
  '  set -euo pipefail' \
  'mktemp -d ' \
  'find . -maxdepth 1 -type f | wc -l' \
  '--retry 3 --retry-delay 2 --retry-all-errors' \
  'shasum -a 256 --check SHA256SUMS' \
  'bash "Who Am I.app/Contents/Resources/product/Install Who Am I.command"'; do
  if ! /usr/bin/grep -Fq -- \
    "${required_recipe_marker}" "${OUTPUT_DIRECTORY}/RELEASE-NOTES.md"; then
    printf 'Generated install recipe is missing a fail-closed marker: %s\n' \
      "${required_recipe_marker}" >&2
    exit 1
  fi
done

(
  cd "${OUTPUT_DIRECTORY}"
  LC_ALL=C /usr/bin/shasum -a 256 \
    "${dmg_name}" \
    "${bundle_name}" \
    RELEASE-METADATA.txt \
    RELEASE-NOTES.md \
    > SHA256SUMS
  /usr/bin/shasum -a 256 --check SHA256SUMS
  [[ "$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 5 ]]
)

printf 'Built five verified self-contained release assets in %s.\n' \
  "${OUTPUT_DIRECTORY}"
