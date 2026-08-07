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

usage() {
  cat <<'EOF'
Usage: bash scripts/build-release-assets.sh options

Build the exact four assets consumed by the GitHub Release workflow.

Required:
  --repository OWNER/REPOSITORY
  --tag TAG
  --commit FULL_COMMIT
  --output-directory PATH

Optional:
  --source-ref GIT_REF  Git commit/ref to archive (default: HEAD).
  -h, --help            Show this help.

The output directory must not already exist. The source ref must resolve to the
declared commit and match the tracked working tree.
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
release_paths=()
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
    release_paths+=("${release_path}")
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

repository_name="${REPOSITORY#*/}"
bundle_name="${repository_name}-${version}.tar.gz"
release_notes="docs/release-notes/${TAG}.md"
if [[ ! -f "${release_notes}" || -L "${release_notes}" ]]; then
  printf 'Missing version-controlled release notes: %s\n' \
    "${release_notes}" >&2
  exit 1
fi

/bin/mkdir "${OUTPUT_DIRECTORY}"
/usr/bin/git archive \
  --format=tar \
  --prefix="${repository_name}-${version}/" \
  --output="${OUTPUT_DIRECTORY}/${repository_name}-${version}.tar" \
  "${source_commit}" \
  "${release_paths[@]}"
/usr/bin/gzip -n -9 \
  "${OUTPUT_DIRECTORY}/${repository_name}-${version}.tar"

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
  printf 'runtime_project=%s\n' "${RUNTIME_PROJECT_NAME}"
  printf 'runtime_version=%s\n' "${RUNTIME_PROJECT_VERSION}"
} > "${OUTPUT_DIRECTORY}/RELEASE-METADATA.txt"
/bin/cp "${release_notes}" "${OUTPUT_DIRECTORY}/RELEASE-NOTES.md"

cat >> "${OUTPUT_DIRECTORY}/RELEASE-NOTES.md" <<EOF

## Exact release assets

This release contains exactly these four assets:

- \`${bundle_name}\`
- \`RELEASE-METADATA.txt\`
- \`RELEASE-NOTES.md\`
- \`SHA256SUMS\`

### Install from a public repository

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
  test "\$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
  shasum -a 256 --check SHA256SUMS
  tar -xzf "${bundle_name}"
  cd "${repository_name}-${version}"
  bash install.sh --interactive
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
    --pattern "${bundle_name}" \
    --pattern "RELEASE-METADATA.txt" \
    --pattern "RELEASE-NOTES.md" \
    --pattern "SHA256SUMS"
  test "\$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
  gh release verify "${TAG}" \
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
  cd "${repository_name}-${version}"
  bash install.sh --interactive
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
  'bash install.sh --interactive'; do
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
    "${bundle_name}" \
    RELEASE-METADATA.txt \
    RELEASE-NOTES.md \
    > SHA256SUMS
  /usr/bin/shasum -a 256 --check SHA256SUMS
  [[ "$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4 ]]
)

printf 'Built four verified release assets in %s.\n' \
  "${OUTPUT_DIRECTORY}"
