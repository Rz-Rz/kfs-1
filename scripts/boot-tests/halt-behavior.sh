#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
rust-kmain-path-halts
asm-boot-path-halts
panic-handler-halts
release-kmain-disassembly-halts
EOF
}

describe_case() {
  case "$1" in
    rust-kmain-path-halts) printf '%s\n' "Rust kmain path ends in a halt loop" ;;
    asm-boot-path-halts) printf '%s\n' "ASM boot path provides a halt loop" ;;
    panic-handler-halts) printf '%s\n' "panic handler converges to the halt path" ;;
    release-kmain-disassembly-halts) printf '%s\n' "release kmain disassembly contains cli/hlt" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

assert_rust_kmain_path_halts() {
  if ! grep -q 'fn halt_forever() -> !' src/kernel/kmain.rs; then
    echo "FAIL src/kernel/kmain.rs: missing halt_forever()" >&2
    exit 1
  fi

  if ! grep -q 'core::arch::asm!(\"cli\", \"hlt\"' src/kernel/kmain.rs; then
    echo "FAIL src/kernel/kmain.rs: missing cli/hlt halt loop" >&2
    exit 1
  fi
}

assert_asm_boot_path_halts() {
  if ! grep -q '^halt_loop:' src/arch/i386/boot.asm; then
    echo "FAIL src/arch/i386/boot.asm: missing halt_loop label" >&2
    exit 1
  fi

  if ! grep -A3 '^halt_loop:' src/arch/i386/boot.asm | grep -q 'hlt'; then
    echo "FAIL src/arch/i386/boot.asm: halt_loop does not execute hlt" >&2
    exit 1
  fi
}

assert_panic_handler_halts() {
  if ! grep -qF '#[panic_handler]' src/kernel/kmain.rs; then
    echo "FAIL src/kernel/kmain.rs: missing panic handler" >&2
    exit 1
  fi

  if ! grep -A8 -F '#[panic_handler]' src/kernel/kmain.rs | grep -q 'halt_forever()'; then
    echo "FAIL src/kernel/kmain.rs: panic handler does not call halt_forever()" >&2
    exit 1
  fi
}

assert_release_kmain_disassembly_halts() {
  local kernel="build/kernel-${ARCH}.bin"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make all arch=${ARCH})"

  if ! objdump -d "${kernel}" | sed -n '/<kmain>:/,/^$/p' | grep -q 'cli'; then
    echo "FAIL ${kernel}: kmain disassembly missing cli" >&2
    objdump -d "${kernel}" | sed -n '/<kmain>:/,/^$/p' >&2 || true
    exit 1
  fi

  if ! objdump -d "${kernel}" | sed -n '/<kmain>:/,/^$/p' | grep -q 'hlt'; then
    echo "FAIL ${kernel}: kmain disassembly missing hlt" >&2
    objdump -d "${kernel}" | sed -n '/<kmain>:/,/^$/p' >&2 || true
    exit 1
  fi
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  case "${CASE}" in
    rust-kmain-path-halts)
      assert_rust_kmain_path_halts
      ;;
    asm-boot-path-halts)
      assert_asm_boot_path_halts
      ;;
    panic-handler-halts)
      assert_panic_handler_halts
      ;;
    release-kmain-disassembly-halts)
      assert_release_kmain_disassembly_halts
      ;;
    *)
      die "usage: $0 <arch> {rust-kmain-path-halts|asm-boot-path-halts|panic-handler-halts|release-kmain-disassembly-halts}"
      ;;
  esac
}

run_host_case() {
  case "${CASE}" in
    rust-kmain-path-halts|asm-boot-path-halts|panic-handler-halts)
      run_direct_case
      ;;
    release-kmain-disassembly-halts)
      bash scripts/with-build-lock.sh \
        bash scripts/container.sh run -- \
        bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/halt-behavior.sh '${ARCH}' '${CASE}'"
      ;;
    *)
      die "unknown case: ${CASE}"
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

  if describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
