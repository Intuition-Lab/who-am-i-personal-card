#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

OUTPUT_DIRECTORY=""
RUNTIME_CHECKOUT=""

usage() {
  cat <<'EOF'
Usage: bash scripts/build-self-contained-package.sh options

Build a single product package containing the pinned Personal Model Runtime.
The resulting installer never fetches the Personal Model source repository.

Required:
  --output-directory PATH

Optional:
  --runtime-checkout PATH  Reuse an already verified pinned Runtime checkout.
                           Without this option the builder fetches it now.
  -h, --help               Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

case "${OUTPUT_DIRECTORY}" in
  ""|/|*[[:cntrl:]])
    printf '%s\n' 'Output directory is missing or unsafe.' >&2
    exit 2
    ;;
esac
if [[ -e "${OUTPUT_DIRECTORY}" || -L "${OUTPUT_DIRECTORY}" ]]; then
  printf 'Output directory already exists: %s\n' "${OUTPUT_DIRECTORY}" >&2
  exit 2
fi

output_parent="${OUTPUT_DIRECTORY%/*}"
if [[ "${output_parent}" == "${OUTPUT_DIRECTORY}" ]]; then
  output_parent="."
fi
if [[ ! -d "${output_parent}" || -L "${output_parent}" \
  || ! -w "${output_parent}" ]]; then
  printf 'Output parent is missing or unsafe: %s\n' "${output_parent}" >&2
  exit 2
fi

cd "${PRODUCT_ROOT}"
runtime_lock_load runtime.lock
version="$(tr -d '[:space:]' < VERSION)"
package_name="who-am-i-${version}-self-contained-macos"
temporary_root="$(runtime_temporary_root_create "who-am-i-package")"
stage_root="${temporary_root}/${package_name}"
runtime_stage="${stage_root}/runtime-source"

cleanup() {
  local cleanup_status=$?
  if [[ -n "${temporary_root:-}" && -d "${temporary_root}" ]]; then
    runtime_temporary_root_remove "${temporary_root}" "who-am-i-package" || true
  fi
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

copy_file() {
  local relative_path="$1"
  local source_path="${PRODUCT_ROOT}/${relative_path}"
  local target_path="${stage_root}/${relative_path}"

  if [[ ! -f "${source_path}" || -L "${source_path}" ]]; then
    printf 'Required package file is missing or unsafe: %s\n' \
      "${relative_path}" >&2
    return 1
  fi
  /bin/mkdir -p "${target_path%/*}"
  /bin/cp "${source_path}" "${target_path}"
}

copy_directory() {
  local relative_path="$1"
  local source_path="${PRODUCT_ROOT}/${relative_path}"
  local target_parent="${stage_root}/${relative_path%/*}"

  if [[ ! -d "${source_path}" || -L "${source_path}" ]]; then
    printf 'Required package directory is missing or unsafe: %s\n' \
      "${relative_path}" >&2
    return 1
  fi
  /bin/mkdir -p "${target_parent}"
  /bin/cp -R "${source_path}" "${target_parent}/"
}

/bin/mkdir "${stage_root}"

for package_file in \
  "Install Who Am I.command" \
  LICENSE \
  THIRD_PARTY_NOTICES.md \
  VERSION \
  install.sh \
  product.lock \
  runtime.lock \
  uninstall-runtime.sh \
  update.sh \
  scripts/diagnose.sh \
  scripts/verify-product.sh \
  scripts/verify.sh \
  scripts/lib/product-lock.sh \
  scripts/lib/runtime-lock.sh; do
  copy_file "${package_file}"
done

for package_directory in \
  apps/personal-card/assets \
  apps/personal-card/macos \
  apps/personal-card/src/auth \
  apps/personal-card/src/client \
  apps/personal-card/src/connectors \
  apps/personal-card/src/contracts \
  apps/personal-card/src/evidence \
  apps/personal-card/src/setup; do
  copy_directory "${package_directory}"
done

/bin/mkdir -p "${stage_root}/apps/personal-card/src/providers"
for package_file in \
  apps/personal-card/package.json \
  apps/personal-card/package-lock.json \
  apps/personal-card/persome-card-server.mjs \
  apps/personal-card/whoami-mcp-proxy.mjs \
  "apps/personal-card/WhoAmI v5 · Persome Live.html" \
  "apps/personal-card/设置我的 Personal Model.command" \
  apps/personal-card/src/providers/local-persome-provider.mjs \
  apps/personal-card/src/providers/provider-registry.mjs \
  apps/personal-card/src/providers/remote-personal-model-provider.mjs \
  apps/personal-card/src/providers/snapshot-backed-provider.mjs; do
  copy_file "${package_file}"
done

if [[ -n "${RUNTIME_CHECKOUT}" ]]; then
  runtime_checkout_verify "${RUNTIME_CHECKOUT}"
  if [[ -f "${RUNTIME_CHECKOUT}/.git/objects/info/alternates" \
    || -L "${RUNTIME_CHECKOUT}/.git/objects/info/alternates" ]]; then
    printf 'Runtime checkout uses an external Git object store.\n' >&2
    exit 1
  fi
  # A developer checkout may be a partial clone. Reading the complete pinned
  # tree here materializes every object required by the package while the
  # reviewed build-time remote is still available.
  runtime_git -C "${RUNTIME_CHECKOUT}" archive --format=tar HEAD \
    | /usr/bin/shasum -a 256 >/dev/null
  /bin/cp -R "${RUNTIME_CHECKOUT}" "${runtime_stage}"
else
  runtime_checkout_create "${runtime_stage}"
  runtime_checkout_verify "${runtime_stage}"
fi

# A packaged Runtime is a verified immutable input, not a future network
# update source. Remove the remote, every non-HEAD reference, and every reflog,
# so partial developer checkouts become a minimal self-contained Git object
# graph and accidental fetches fail closed.
runtime_git -C "${runtime_stage}" remote remove origin 2>/dev/null || true
while IFS= read -r runtime_ref; do
  [[ -n "${runtime_ref}" ]] || continue
  runtime_git -C "${runtime_stage}" update-ref -d "${runtime_ref}"
done < <(
  runtime_git -C "${runtime_stage}" for-each-ref \
    --format='%(refname)' refs/heads refs/tags refs/remotes
)
runtime_git -C "${runtime_stage}" reflog expire --expire=now --all
runtime_checkout_verify "${runtime_stage}"
if [[ -n "$(runtime_git -C "${runtime_stage}" remote)" \
  || -n "$(runtime_git -C "${runtime_stage}" for-each-ref)" ]]; then
  printf 'Packaged Runtime retained an unexpected Git remote or reference.\n' >&2
  exit 1
fi

unsafe_link="$(
  /usr/bin/find "${stage_root}" -type l -print -quit 2>/dev/null || true
)"
if [[ -n "${unsafe_link}" ]]; then
  printf 'Self-contained package contains a symbolic link: %s\n' \
    "${unsafe_link}" >&2
  exit 1
fi

cat > "${stage_root}/README.txt" <<EOF
Who Am I ${version} — self-contained macOS installer

Double-click "Install Who Am I.command".

This package contains Personal Model Runtime commit ${RUNTIME_COMMIT}.
Installation does not access the Personal Model source repository.
Personal data is created only on this Mac under the signed-in account.
EOF

cat > "${stage_root}/PACKAGE-METADATA.txt" <<EOF
package=${package_name}
product_version=${version}
runtime_commit=${RUNTIME_COMMIT}
runtime_tree=${RUNTIME_TREE}
runtime_project=${RUNTIME_PROJECT_NAME}
runtime_version=${RUNTIME_PROJECT_VERSION}
runtime_delivery=embedded
personal_data_included=false
EOF

# A DMG preserves the builder's numeric owner. Release contents therefore
# need public read/traverse modes so another macOS account can mount and run
# the installer. The installer creates all personal data separately under its
# own 0077 umask.
/usr/bin/find "${stage_root}" -exec /bin/chmod a+rX,u+w,go-w {} +
/bin/chmod 0755 \
  "${stage_root}/Install Who Am I.command" \
  "${stage_root}/install.sh" \
  "${stage_root}/uninstall-runtime.sh" \
  "${stage_root}/update.sh" \
  "${stage_root}/scripts/diagnose.sh" \
  "${stage_root}/scripts/verify-product.sh" \
  "${stage_root}/scripts/verify.sh" \
  "${stage_root}/apps/personal-card/设置我的 Personal Model.command" \
  "${runtime_stage}/install.sh" \
  "${runtime_stage}/uninstall.sh"

manifest_temporary="${temporary_root}/SELF-CONTAINED-SHA256SUMS"
(
  cd "${stage_root}"
  /usr/bin/find . -type f -print0 \
    | LC_ALL=C /usr/bin/sort -z \
    | /usr/bin/xargs -0 /usr/bin/shasum -a 256 \
    > "${manifest_temporary}"
  /bin/mv "${manifest_temporary}" SELF-CONTAINED-SHA256SUMS
  /usr/bin/shasum -a 256 --check SELF-CONTAINED-SHA256SUMS >/dev/null
)
/bin/chmod 0644 "${stage_root}/SELF-CONTAINED-SHA256SUMS"

/bin/mkdir "${OUTPUT_DIRECTORY}"
/usr/bin/tar -czf \
  "${OUTPUT_DIRECTORY}/${package_name}.tar.gz" \
  -C "${temporary_root}" "${package_name}"

if [[ "$(/usr/bin/uname -s)" == "Darwin" && -x /usr/bin/hdiutil ]]; then
  /usr/bin/hdiutil create \
    -quiet \
    -volname "Who Am I Installer" \
    -srcfolder "${stage_root}" \
    -format UDZO \
    "${OUTPUT_DIRECTORY}/${package_name}.dmg"
fi

(
  cd "${OUTPUT_DIRECTORY}"
  LC_ALL=C /usr/bin/shasum -a 256 ./* > SHA256SUMS
  /usr/bin/shasum -a 256 --check SHA256SUMS >/dev/null
)

printf 'Built self-contained Who Am I package in %s.\n' \
  "${OUTPUT_DIRECTORY}"
