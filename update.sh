#!/usr/bin/env bash
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

PRODUCT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERACTIVE_FLAG_PRESENT=0

for argument in "$@"; do
  case "${argument}" in
    --interactive)
      INTERACTIVE_FLAG_PRESENT=1
      ;;
    --non-interactive)
      printf '%s\n' \
        'Runtime updates cannot run non-interactively.' \
        'Use --interactive from a logged-in terminal.' >&2
      exit 2
      ;;
  esac
done

cat <<'EOF'
Updating through this product's immutable Runtime lock.
The product invokes only the pinned source tree's transactional updater.
Do not run the floating `persome update` command directly.
An existing Runtime update requires an interactive logged-in terminal.
EOF

if [[ "${INTERACTIVE_FLAG_PRESENT}" -eq 1 ]]; then
  exec bash "${PRODUCT_ROOT}/install.sh" "$@"
fi
exec bash "${PRODUCT_ROOT}/install.sh" --interactive "$@"
