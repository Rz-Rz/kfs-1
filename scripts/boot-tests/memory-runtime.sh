#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
ISO="build/os-${ARCH}-test.iso"
LOG="build/m5-memory-runtime-${CASE}.log"
INIT_SOURCE="src/kernel/core/init.rs"

list_cases() {
  cat <<'EOF'
release-kmain-calls-kfs-memcpy
runtime-confirms-memcpy
release-kmain-calls-kfs-memset
runtime-confirms-memset
runtime-confirms-memory-helpers
runtime-memory-markers-are-ordered
EOF
}

describe_case() {
  case "$1" in
    release-kmain-calls-kfs-memcpy) printf '%s\n' "release core init calls memory::memcpy in the memory sanity path" ;;
    runtime-confirms-memcpy) printf '%s\n' "runtime emits MEMCPY_OK" ;;
    release-kmain-calls-kfs-memset) printf '%s\n' "release core init calls memory::memset in the memory sanity path" ;;
    runtime-confirms-memset) printf '%s\n' "runtime emits MEMSET_OK" ;;
    runtime-confirms-memory-helpers) printf '%s\n' "runtime emits MEMORY_HELPERS_OK" ;;
    runtime-memory-markers-are-ordered) printf '%s\n' "runtime emits MEMCPY_OK then MEMSET_OK then MEMORY_HELPERS_OK in order" ;;
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

run_qemu_capture() {
  [[ -r "${ISO}" ]] || die "missing ISO: ${ISO} (build it with make iso-test arch=${ARCH})"

  set +e
  timeout --foreground "${TIMEOUT_SECS}" \
    qemu-system-i386 \
    -cdrom "${ISO}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -serial stdio \
    -display none \
    -monitor none \
    -no-reboot \
    -no-shutdown \
    </dev/null >"${LOG}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -ne "${PASS_RC}" ]]; then
    echo "FAIL ${CASE}: expected PASS rc=${PASS_RC}, got rc=${rc}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

assert_log_contains() {
  local token="$1"
  if ! grep -qFx "${token}" "${LOG}"; then
    echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

assert_log_order() {
  local previous_line=0
  local token
  local line

  for token in "$@"; do
    line="$(grep -nFx "${token}" "${LOG}" | head -n 1 | cut -d: -f1)"
    [[ -n "${line}" ]] || {
      echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
      cat "${LOG}" >&2
      exit 1
    }

    if (( line <= previous_line )); then
      echo "FAIL ${CASE}: runtime marker ${token} is out of order" >&2
      cat "${LOG}" >&2
      exit 1
    fi

    previous_line="${line}"
  done
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  run_qemu_capture

  case "${CASE}" in
    release-kmain-calls-kfs-memcpy)
      assert_pattern 'memory::memcpy\(' 'memory::memcpy call in core init' "${INIT_SOURCE}"
      assert_log_contains "MEMCPY_OK"
      ;;
    runtime-confirms-memcpy)
      assert_log_contains "MEMCPY_OK"
      ;;
    release-kmain-calls-kfs-memset)
      assert_pattern 'memory::memset\(' 'memory::memset call in core init' "${INIT_SOURCE}"
      assert_log_contains "MEMSET_OK"
      ;;
    runtime-confirms-memset)
      assert_log_contains "MEMSET_OK"
      ;;
    runtime-confirms-memory-helpers)
      assert_log_contains "MEMORY_HELPERS_OK"
      ;;
    runtime-memory-markers-are-ordered)
      assert_log_order "MEMCPY_OK" "MEMSET_OK" "MEMORY_HELPERS_OK"
      ;;
    *)
      die "usage: $0 <arch> {release-kmain-calls-kfs-memcpy|runtime-confirms-memcpy|release-kmain-calls-kfs-memset|runtime-confirms-memset|runtime-confirms-memory-helpers|runtime-memory-markers-are-ordered}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B iso-test arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' TEST_PASS_RC='${PASS_RC}' bash scripts/boot-tests/memory-runtime.sh '${ARCH}' '${CASE}'"
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
