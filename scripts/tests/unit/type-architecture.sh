#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_types.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

list_cases() {
  cat <<'EOF'
port-host-unit-tests-pass
kernel-range-host-unit-tests-pass
EOF
}

describe_case() {
  case "$1" in
    port-host-unit-tests-pass) printf '%s\n' "host Port unit tests pass" ;;
    kernel-range-host-unit-tests-pass) printf '%s\n' "host KernelRange unit tests pass" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_types_${filter%_}"

  [[ -r "${TEST_SOURCE}" ]] || die "missing required source: ${TEST_SOURCE}"
  run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
  case "${CASE}" in
    port-host-unit-tests-pass)
      run_host_tests 'port_'
      ;;
    kernel-range-host-unit-tests-pass)
      run_host_tests 'kernel_range_'
      ;;
    *)
      die "usage: $0 <arch> {port-host-unit-tests-pass|kernel-range-host-unit-tests-pass}"
      ;;
  esac
}

main() {
  if [[ "${ARCH}" == "--list" ]]; then
    list_cases
    return 0
  fi

  if [[ "${ARCH}" == "--description" ]]; then
    describe_case "${CASE}"
    return 0
  fi

  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  run_direct_case
}

main "$@"
