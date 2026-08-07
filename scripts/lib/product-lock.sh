#!/usr/bin/env bash

product_lock_load() {
  local lock_path="$1"
  local line line_number=0 key value seen_keys=""
  local assignment_pattern='^([A-Z][A-Z0-9_]*)="([^"]*)"$'
  local schema="" node_version="" base_url="" arm64_sha="" x64_sha=""

  if [[ ! -f "${lock_path}" || -L "${lock_path}" ]]; then
    printf 'Product lock is missing or unsafe.\n' >&2
    return 1
  fi

  unset PRODUCT_NODE_VERSION
  unset PRODUCT_NODE_BASE_URL
  unset PRODUCT_NODE_DARWIN_ARM64_SHA256
  unset PRODUCT_NODE_DARWIN_X64_SHA256

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_number=$((line_number + 1))
    case "${line}" in
      ""|\#*)
        continue
        ;;
    esac
    if [[ ! "${line}" =~ ${assignment_pattern} ]]; then
      printf 'Invalid product lock syntax at %s:%s.\n' \
        "${lock_path}" "${line_number}" >&2
      return 1
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "|${seen_keys}|" in
      *"|${key}|"*)
        printf 'Duplicate product lock key at %s:%s: %s\n' \
          "${lock_path}" "${line_number}" "${key}" >&2
        return 1
        ;;
    esac
    seen_keys="${seen_keys}|${key}"
    case "${key}" in
      PRODUCT_LOCK_SCHEMA) schema="${value}" ;;
      PRODUCT_NODE_VERSION) node_version="${value}" ;;
      PRODUCT_NODE_BASE_URL) base_url="${value}" ;;
      PRODUCT_NODE_DARWIN_ARM64_SHA256) arm64_sha="${value}" ;;
      PRODUCT_NODE_DARWIN_X64_SHA256) x64_sha="${value}" ;;
      *)
        printf 'Unknown product lock key at %s:%s: %s\n' \
          "${lock_path}" "${line_number}" "${key}" >&2
        return 1
        ;;
    esac
  done < "${lock_path}"

  if [[ "${schema}" != "1" \
    || ! "${node_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ \
    || "${base_url}" != "https://nodejs.org/dist/v${node_version}" \
    || ! "${arm64_sha}" =~ ^[a-f0-9]{64}$ \
    || ! "${x64_sha}" =~ ^[a-f0-9]{64}$ ]]; then
    printf 'Product lock validation failed.\n' >&2
    return 1
  fi

  PRODUCT_NODE_VERSION="${node_version}"
  PRODUCT_NODE_BASE_URL="${base_url}"
  PRODUCT_NODE_DARWIN_ARM64_SHA256="${arm64_sha}"
  PRODUCT_NODE_DARWIN_X64_SHA256="${x64_sha}"
  export PRODUCT_NODE_VERSION PRODUCT_NODE_BASE_URL
  export PRODUCT_NODE_DARWIN_ARM64_SHA256 PRODUCT_NODE_DARWIN_X64_SHA256
}
