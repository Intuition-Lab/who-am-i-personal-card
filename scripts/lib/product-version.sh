#!/usr/bin/env bash

# Product release versions use SemVer core and prerelease syntax. Build metadata
# is intentionally excluded because the same value is used in Git tags, asset
# names, directories, and release-note filenames.
product_version_validate() {
  local candidate="$1"
  local major minor patch prerelease identifier
  local -a identifiers
  local version_pattern='^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'

  if [[ ! "${candidate}" =~ ${version_pattern} ]]; then
    return 1
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  prerelease="${BASH_REMATCH[5]:-}"

  for identifier in "${major}" "${minor}" "${patch}"; do
    if [[ "${identifier}" != "0" && "${identifier}" == 0* ]]; then
      return 1
    fi
  done

  if [[ -n "${prerelease}" ]]; then
    IFS='.' read -r -a identifiers <<< "${prerelease}"
    for identifier in "${identifiers[@]}"; do
      if [[ "${identifier}" =~ ^[0-9]+$ \
        && "${identifier}" != "0" && "${identifier}" == 0* ]]; then
        return 1
      fi
    done
  fi
}
