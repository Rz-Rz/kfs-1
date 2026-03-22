#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
ENTRY_SOURCE="src/kernel/core/entry.rs"
INIT_SOURCE="src/kernel/core/init.rs"

list_cases() {
  cat <<'EOF'
runtime-serial-path-works-with-port
runtime-layout-path-works-with-kernel-range
EOF
}

describe_case() {
  case "$1" in
    runtime-serial-path-works-with-port) printf '%s\n' "runtime serial path works through machine Port and serial driver layers" ;;
    runtime-layout-path-works-with-kernel-range) printf '%s\n' "runtime layout path still works through KernelRange" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

find_pattern() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S "$@" >/dev/null
  else
    grep -En "${pattern}" "$@" >/dev/null
  fi
}

assert_pattern() {
  local pattern="$1"
  local label="$2"
  shift 2

  if ! find_pattern "${pattern}" "$@"; then
    echo "FAIL src: missing ${label}"
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  case "${CASE}" in
    runtime-serial-path-works-with-port)
      assert_pattern '\bcrate::kernel::machine::port::Port\b' 'serial driver imports Port' "src/kernel/drivers/serial/mod.rs"
      assert_pattern '\bdrivers::serial\b' 'diagnostics service reaches serial driver facade' "src/kernel/services/diagnostics.rs"
      KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS="${TIMEOUT_SECS}" TEST_PASS_RC="${PASS_RC}" \
        bash scripts/boot-tests/runtime-markers.sh "${ARCH}" runtime-reaches-kmain
      ;;
    runtime-layout-path-works-with-kernel-range)
      assert_pattern 'KernelRange::new\(' 'KernelRange construction in runtime path' "${ENTRY_SOURCE}"
      assert_pattern 'layout_order_is_sane\(' 'layout helper use in runtime path' "${INIT_SOURCE}"
      KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS="${TIMEOUT_SECS}" TEST_PASS_RC="${PASS_RC}" \
        bash scripts/boot-tests/runtime-markers.sh "${ARCH}" runtime-confirms-layout
      ;;
    *)
      die "usage: $0 <arch> {runtime-serial-path-works-with-port|runtime-layout-path-works-with-kernel-range}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B iso-test arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' TEST_PASS_RC='${PASS_RC}' bash scripts/boot-tests/type-architecture.sh '${ARCH}' '${CASE}'"
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

  if describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
