#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset CDPATH

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_ROOT="${WHOAMI_SMOKE_PRODUCT_ROOT:-${TEST_ROOT}}"
case "${PRODUCT_ROOT}" in
  /*) ;;
  *)
    printf 'Smoke-test product root must be an absolute path.\n' >&2
    exit 2
    ;;
esac
if [[ ! -d "${PRODUCT_ROOT}" || -L "${PRODUCT_ROOT}" \
  || ! -f "${PRODUCT_ROOT}/runtime.lock" \
  || ! -f "${PRODUCT_ROOT}/install.sh" ]]; then
  printf 'Smoke-test product root is missing or unsafe: %s\n' \
    "${PRODUCT_ROOT}" >&2
  exit 2
fi
PRODUCT_ROOT="$(cd "${PRODUCT_ROOT}" && pwd -P)"

# shellcheck source=scripts/lib/runtime-lock.sh
source "${PRODUCT_ROOT}/scripts/lib/runtime-lock.sh"

UNINSTALL_PATH="receipt"

usage() {
  cat <<'EOF'
Usage: bash scripts/smoke-install.sh [option]

Perform a real non-interactive install, privacy-safe diagnosis, and
preserve-data uninstall inside an owner-controlled disposable HOME.

Options:
  --uninstall-via-receipt
                    Exercise the completed-install receipt. This is the default.
  --uninstall-via-intent
                    Force a real late install failure before receipts and
                    recover through the stable offline management bundle.
  -h, --help        Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall-via-receipt)
      UNINSTALL_PATH="receipt"
      shift
      ;;
    --uninstall-via-intent)
      UNINSTALL_PATH="intent"
      shift
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
  printf 'The installation smoke test requires macOS.\n' >&2
  exit 1
fi

runtime_lock_load "${PRODUCT_ROOT}/runtime.lock"

smoke_root="$(runtime_temporary_root_create "product-install-smoke")"
cleanup() {
  local cleanup_status=$?
  if [[ -n "${smoke_root:-}" ]]; then
    runtime_temporary_root_remove \
      "${smoke_root}" "product-install-smoke" || true
  fi
  return "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -p "${smoke_root}/home"
chmod 0700 "${smoke_root}/home"

export HOME="${smoke_root}/home"
export PERSOME_INSTALL_HOME="${HOME}/.persome"
export TMPDIR="${smoke_root}"

/bin/mkdir -p "${PERSOME_INSTALL_HOME}"
/bin/chmod 0700 "${PERSOME_INSTALL_HOME}"
printf 'preserve-me\n' \
  > "${PERSOME_INSTALL_HOME}/product-preservation-sentinel"

if [[ "${UNINSTALL_PATH}" == "intent" ]]; then
  failed_install_output="${smoke_root}/late-failed-install.out"
  if PRODUCT_FOUNDATION_TESTING=1 \
    PRODUCT_FOUNDATION_TEST_FAIL_PHASE=after-upstream-before-receipts \
    bash "${PRODUCT_ROOT}/install.sh" --non-interactive \
      > "${failed_install_output}" 2>&1; then
    printf 'The real late-failure smoke unexpectedly completed installation.\n' \
      >&2
    exit 1
  else
    failed_install_status=$?
  fi
  if [[ "${failed_install_status}" -ne 86 ]] \
    || ! /usr/bin/grep -Fq \
      "Foundation test failpoint reached: after-upstream-before-receipts" \
      "${failed_install_output}"; then
    printf 'Late-failure install exited %s before the expected failpoint.\n' \
      "${failed_install_status}" >&2
    /bin/cat "${failed_install_output}" >&2
    exit 1
  fi
  for required_partial_path in \
    "${PERSOME_INSTALL_HOME}/venv" \
    "${PERSOME_INSTALL_HOME}/product-runtime.installing" \
    "${PERSOME_INSTALL_HOME}/product-management/uninstall-runtime.sh"; do
    if [[ ! -e "${required_partial_path}" ]]; then
      printf 'Late-failure recovery path is missing: %s\n' \
        "${required_partial_path}" >&2
      /bin/cat "${failed_install_output}" >&2
      exit 1
    fi
  done
  if [[ -e "${PERSOME_INSTALL_HOME}/product-runtime.lock" \
    || -e "${PERSOME_INSTALL_HOME}/venv/.product-runtime.lock" ]]; then
    printf 'A product receipt was written before the late-failure gate.\n' >&2
    exit 1
  fi
  management_root="${PERSOME_INSTALL_HOME}/product-management"
  test -x "${management_root}/uninstall-runtime.sh"
else
  bash "${PRODUCT_ROOT}/install.sh" --non-interactive
  bash "${PRODUCT_ROOT}/scripts/verify.sh" --quick
  bash "${PRODUCT_ROOT}/scripts/verify-product.sh"
  test ! -e \
    "${PERSOME_INSTALL_HOME}/product-app/$(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")/fixtures"
  test ! -e \
    "${PERSOME_INSTALL_HOME}/product-app/$(tr -d '[:space:]' < "${PRODUCT_ROOT}/VERSION")/tests"

  diagnostic="$(bash "${PRODUCT_ROOT}/scripts/diagnose.sh" --json)"
  grep -Fq '"status": "healthy"' <<<"${diagnostic}"
  printf '%s\n' "${diagnostic}"

  test -f "${PERSOME_INSTALL_HOME}/env"
  environment_digest_before="$(
    /usr/bin/shasum -a 256 "${PERSOME_INSTALL_HOME}/env" \
      | /usr/bin/awk '{print $1}'
  )"
  configuration_digest_before=""
  if [[ -f "${PERSOME_INSTALL_HOME}/config.toml" ]]; then
    configuration_digest_before="$(
      /usr/bin/shasum -a 256 "${PERSOME_INSTALL_HOME}/config.toml" \
        | /usr/bin/awk '{print $1}'
    )"
  fi

  # Reinstalling the exact same pinned Runtime may refresh the native App and
  # management bundle without rerunning Runtime setup or permission checks.
  # The foundation suite separately proves that a different pinned Runtime is
  # still rejected in non-interactive mode before Runtime mutation.
  non_interactive_update_output="${smoke_root}/non-interactive-update.out"
  bash "${PRODUCT_ROOT}/install.sh" --non-interactive \
    > "${non_interactive_update_output}" 2>&1
  /usr/bin/grep -Fq \
    "already matches this product's pinned Runtime" \
    "${non_interactive_update_output}"
  bash "${PRODUCT_ROOT}/scripts/verify.sh" --quick
  bash "${PRODUCT_ROOT}/scripts/verify-product.sh"
  test "$(
    /bin/cat "${PERSOME_INSTALL_HOME}/product-preservation-sentinel"
  )" = "preserve-me"
  test -d "${PERSOME_INSTALL_HOME}/product-cache/uv"
  test ! -e "${PERSOME_INSTALL_HOME}/product-runtime.installing"
  test "$(
    /usr/bin/shasum -a 256 "${PERSOME_INSTALL_HOME}/env" \
      | /usr/bin/awk '{print $1}'
  )" = "${environment_digest_before}"
  if [[ -n "${configuration_digest_before}" ]]; then
    test "$(
      /usr/bin/shasum -a 256 "${PERSOME_INSTALL_HOME}/config.toml" \
        | /usr/bin/awk '{print $1}'
    )" = "${configuration_digest_before}"
  fi
fi

management_root="${PERSOME_INSTALL_HOME}/product-management"
if [[ "${UNINSTALL_PATH}" == "intent" ]]; then
  # Use only the stable bundle retained before Runtime mutation. The temporary
  # checkout used by the failed installer has already been removed.
  /bin/bash "${management_root}/uninstall-runtime.sh" --preserve-data
else
  bash "${PRODUCT_ROOT}/uninstall-runtime.sh" --preserve-data
fi

test -f "${PERSOME_INSTALL_HOME}/product-preservation-sentinel"
test ! -e "${PERSOME_INSTALL_HOME}/venv"
test ! -e "${PERSOME_INSTALL_HOME}/managed-python"
test ! -e "${PERSOME_INSTALL_HOME}/product-cache"
test ! -e "${PERSOME_INSTALL_HOME}/product-runtime.lock"
test ! -e "${PERSOME_INSTALL_HOME}/product-runtime.installing"
test ! -e "${HOME}/.local/bin/persome"
test -x "${management_root}/uninstall-runtime.sh"
test -x "${management_root}/scripts/diagnose.sh"
test -x "${management_root}/scripts/verify.sh"
test -x \
  "${management_root}/upstream-uninstall-${RUNTIME_UNINSTALLER_SHA256}.sh"
runtime_receipt_verify \
  "${PERSOME_INSTALL_HOME}/product-runtime.uninstalled"

# The stable management bundle must remain usable after the release download
# directory is gone, and repeated preserve-data uninstall is idempotent/offline.
/bin/bash "${management_root}/uninstall-runtime.sh" --check-ownership \
  | /usr/bin/grep -Fq "Runtime ownership state: data-only"
/bin/bash "${management_root}/uninstall-runtime.sh" --preserve-data
runtime_receipt_verify \
  "${PERSOME_INSTALL_HOME}/product-runtime.uninstalled"

# Exercise the separate, later permanent-deletion decision through a real
# pseudo-terminal. The product uninstaller refuses this operation without a
# TTY, and the test must observe its exact prompt before sending DELETE.
python3 - \
  "${management_root}/uninstall-runtime.sh" \
  "${HOME}" \
  "${PERSOME_INSTALL_HOME}" <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time

uninstaller, home, install_home = sys.argv[1:]
child_pid, descriptor = pty.fork()
if child_pid == 0:
    environment = {
        "HOME": home,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "PERSOME_INSTALL_HOME": install_home,
        "TERM": "dumb",
    }
    os.execve(
        "/bin/bash",
        ["/bin/bash", uninstaller, "--delete-data"],
        environment,
    )

output = bytearray()
confirmation_sent = False
deadline = time.monotonic() + 30
child_status = None
while time.monotonic() < deadline:
    readable, _, _ = select.select([descriptor], [], [], 0.1)
    if descriptor not in readable:
        waited_pid, waited_status = os.waitpid(child_pid, os.WNOHANG)
        if waited_pid:
            child_status = waited_status
            break
        continue
    try:
        chunk = os.read(descriptor, 4096)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    output.extend(chunk)
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
    if not confirmation_sent and b"Type DELETE" in output:
        os.write(descriptor, b"DELETE\n")
        confirmation_sent = True
else:
    os.kill(child_pid, signal.SIGKILL)
    os.waitpid(child_pid, 0)
    raise SystemExit("confirmed Runtime deletion timed out")

if child_status is None:
    _, child_status = os.waitpid(child_pid, 0)
if not confirmation_sent:
    raise SystemExit("Runtime deletion prompt was not observed")
if not os.WIFEXITED(child_status) or os.WEXITSTATUS(child_status) != 0:
    if os.WIFEXITED(child_status):
        raise SystemExit(os.WEXITSTATUS(child_status))
    raise SystemExit(128 + os.WTERMSIG(child_status))
PY

test ! -e "${PERSOME_INSTALL_HOME}"
test ! -e "${HOME}/.local/bin/persome"

printf 'Install smoke passed on %s via %s recovery.\n' \
  "$(uname -m)" "${UNINSTALL_PATH}"
