#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
FAIL_RC="${TEST_FAIL_RC:-35}"
ISO="build/os-${ARCH}-test.iso"
LOG="build/m5-string-negative-${CASE}.log"

list_cases() {
  cat <<'EOF'
bad-string-self-check-fails
bad-string-stops-before-normal-flow
EOF
}

describe_case() {
  case "$1" in
    bad-string-self-check-fails) printf '%s\n' "rejects a broken string-helper self-check at runtime" ;;
    bad-string-stops-before-normal-flow) printf '%s\n' "string-helper failure stops before normal flow resumes" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
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

  if [[ "${rc}" -ne "${FAIL_RC}" ]]; then
    echo "FAIL ${CASE}: expected FAIL rc=${FAIL_RC}, got rc=${rc}" >&2
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

assert_log_not_contains() {
  local token="$1"
  if grep -qFx "${token}" "${LOG}"; then
    echo "FAIL ${CASE}: unexpected runtime marker ${token}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  run_qemu_capture

  case "${CASE}" in
    bad-string-self-check-fails)
      assert_log_contains "KMAIN_OK"
      assert_log_contains "BSS_OK"
      assert_log_contains "LAYOUT_OK"
      assert_log_contains "STRING_HELPERS_FAIL"
      ;;
    bad-string-stops-before-normal-flow)
      assert_log_contains "STRING_HELPERS_FAIL"
      assert_log_not_contains "EARLY_INIT_OK"
      assert_log_not_contains "KMAIN_FLOW_OK"
      ;;
    *)
      die "usage: $0 <arch> {bad-string-self-check-fails|bad-string-stops-before-normal-flow}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B iso-test arch='${ARCH}' KFS_TEST_BAD_STRING=1 >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' TEST_FAIL_RC='${FAIL_RC}' bash scripts/rejection-tests/string-rejections.sh '${ARCH}' '${CASE}'"
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

  if [[ -n "${CASE}" ]] && describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
