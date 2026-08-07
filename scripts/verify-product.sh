#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"
# shellcheck source=scripts/lib/product-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/product-lock.sh"

runtime_lock_load "${PRODUCT_ROOT}/runtime.lock"
product_lock_load "${PRODUCT_ROOT}/product.lock"
runtime_install_home_resolve

product_version="$(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")"
card_root="${RUNTIME_INSTALL_HOME}/product-app/${product_version}"
node_path="${card_root}/runtime/node/bin/node"
app_bundle="${HOME}/Applications/Who Am I.app"
app_executable="${app_bundle}/Contents/MacOS/Who Am I"
app_plist="${app_bundle}/Contents/Info.plist"

for required_directory in \
  "${RUNTIME_INSTALL_HOME}/product-app" \
  "${card_root}" \
  "${card_root}/runtime" \
  "${card_root}/runtime/node" \
  "${app_bundle}" \
  "${app_bundle}/Contents" \
  "${app_bundle}/Contents/MacOS"; do
  runtime_secure_owned_directory_verify "${required_directory}"
done

for required_file in \
  "${card_root}/product-version" \
  "${card_root}/package-lock.json" \
  "${card_root}/persome-card-server.mjs" \
  "${node_path}" \
  "${app_executable}" \
  "${app_plist}"; do
  runtime_secure_owned_file_verify "${required_file}"
done

if [[ "$(tr -d '[:space:]' < "${card_root}/product-version")" \
  != "${product_version}" ]]; then
  printf 'Installed Personal Card version does not match VERSION.\n' >&2
  exit 1
fi

installed_node_version="$(
  /usr/bin/env -i \
    HOME="${HOME}" \
    PATH="${RUNTIME_SYSTEM_PATH}" \
    "${node_path}" --version
)"
if [[ "${installed_node_version}" != "v${PRODUCT_NODE_VERSION}" ]]; then
  printf 'Installed Node version mismatch: expected v%s, got %s\n' \
    "${PRODUCT_NODE_VERSION}" "${installed_node_version}" >&2
  exit 1
fi

if [[ -e "${card_root}/fixtures" || -e "${card_root}/tests" ]]; then
  printf 'Development fixtures or tests were installed into the product app.\n' >&2
  exit 1
fi
if ! /usr/bin/grep -Fq \
  '<string>ai.intuition.whoami</string>' "${app_plist}" \
  || ! /usr/bin/grep -Fq "${card_root}" "${app_executable}"; then
  printf 'Who Am I.app does not point to this verified product version.\n' >&2
  exit 1
fi

/usr/bin/env -i \
  HOME="${HOME}" \
  PATH="${RUNTIME_SYSTEM_PATH}" \
  "${node_path}" --check "${card_root}/persome-card-server.mjs" >/dev/null

printf 'Product OK: Who Am I %s (Node %s)\n' \
  "${product_version}" "${installed_node_version}"
