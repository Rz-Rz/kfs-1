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
    panic-handler-halts) printf '%s\n' "freestanding panic handler converges to the halt path" ;;
    release-kmain-disassembly-halts) printf '%s\n' "release kmain disassembly contains cli/hlt" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

assert_rust_kmain_path_halts() {
  if ! grep -q 'fn halt_forever() -> !' src/kernel/core/entry.rs; then
    echo "FAIL src/kernel/core/entry.rs: missing halt_forever()" >&2
    exit 1
  fi

  if ! grep -q 'kfs_arch_halt_forever()' src/kernel/core/entry.rs; then
    echo "FAIL src/kernel/core/entry.rs: missing arch halt handoff" >&2
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
  if ! grep -qF '#[panic_handler]' src/freestanding/panic.rs; then
    echo "FAIL src/freestanding/panic.rs: missing panic handler" >&2
    exit 1
  fi

  if ! grep -A12 -F '#[panic_handler]' src/freestanding/panic.rs | grep -q 'halt_forever()'; then
    echo "FAIL src/freestanding/panic.rs: panic handler does not call halt_forever()" >&2
    exit 1
  fi
}

assert_release_kmain_disassembly_halts() {
  local kernel="build/kernel-${ARCH}.bin"
  local start_addr
  local stop_addr
  local halt_disasm
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make all arch=${ARCH})"

  start_addr="$(
    nm -n "${kernel}" |
      awk '$3 == "kfs_arch_halt_forever" { print "0x" $1; exit }'
  )"
  [[ -n "${start_addr}" ]] || die "missing symbol: kfs_arch_halt_forever in ${kernel}"

  stop_addr="$(
    nm -n "${kernel}" |
      awk '
        $3 == "kfs_arch_halt_forever" { seen = 1; next }
        seen && $2 ~ /^[Tt]$/ && index($3, "kfs_arch_halt_forever") != 1 {
          print "0x" $1
          exit
        }
      '
  )"

  if [[ -n "${stop_addr}" ]]; then
    halt_disasm="$(objdump -d --start-address="${start_addr}" --stop-address="${stop_addr}" "${kernel}")"
  else
    halt_disasm="$(objdump -d --start-address="${start_addr}" "${kernel}")"
  fi

  if ! printf '%s\n' "${halt_disasm}" | grep -q 'cli'; then
    echo "FAIL ${kernel}: halt routine disassembly missing cli" >&2
    printf '%s\n' "${halt_disasm}" >&2 || true
    exit 1
  fi

  if ! printf '%s\n' "${halt_disasm}" | grep -q 'hlt'; then
    echo "FAIL ${kernel}: halt routine disassembly missing hlt" >&2
    printf '%s\n' "${halt_disasm}" >&2 || true
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
