#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-release-kernel-links-vga-writer}"
KERNEL="build/kernel-${ARCH}.bin"
SOURCE="src/kernel/vga.rs"
KMAIN="src/kernel/kmain.rs"

list_cases() {
  cat <<'EOF'
release-kernel-exports-vga-init
release-kernel-exports-vga-putc
release-kernel-exports-vga-puts
release-kernel-links-vga-writer
rust-kmain-uses-vga-init
rust-kmain-uses-vga-puts
EOF
}

describe_case() {
  case "$1" in
    release-kernel-exports-vga-init) printf '%s\n' "release kernel exports vga_init" ;;
    release-kernel-exports-vga-putc) printf '%s\n' "release kernel exports vga_putc" ;;
    release-kernel-exports-vga-puts) printf '%s\n' "release kernel exports vga_puts" ;;
    release-kernel-links-vga-writer) printf '%s\n' "release kernel links VGA writer symbols" ;;
    rust-kmain-uses-vga-init) printf '%s\n' "kmain uses vga_init" ;;
    rust-kmain-uses-vga-puts) printf '%s\n' "kmain uses vga_puts" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

assert_source_pattern() {
  local pattern="$1"
  local description="$2"
  local file="$3"

  [[ -r "${file}" ]] || die "missing source file: ${file}"

  if command -v rg >/dev/null 2>&1; then
    if ! rg -n "${pattern}" -S "${file}" >/dev/null; then
      echo "FAIL ${file}: missing ${description}"
      return 1
    fi
  else
    if ! grep -En "${pattern}" "${file}" >/dev/null; then
      echo "FAIL ${file}: missing ${description}"
      return 1
    fi
  fi
}

assert_release_symbol() {
  local symbol="$1"

  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"

  if ! nm -n "${KERNEL}" | grep -qE "[[:space:]]T[[:space:]]+${symbol}$"; then
    echo "FAIL ${KERNEL}: missing symbol ${symbol}"
    return 1
  fi
}

run_direct_case() {
  case "${CASE}" in
    release-kernel-exports-vga-init)
      assert_release_symbol 'vga_init'
      ;;
    release-kernel-exports-vga-putc)
      assert_release_symbol 'vga_putc'
      ;;
    release-kernel-exports-vga-puts)
      assert_release_symbol 'vga_puts'
      ;;
    release-kernel-links-vga-writer)
      assert_release_symbol 'vga_init'
      assert_release_symbol 'vga_putc'
      assert_release_symbol 'vga_puts'
      ;;
    rust-kmain-uses-vga-init)
      assert_source_pattern '\bvga_init\b' 'kmain call to vga_init' "${KMAIN}"
      ;;
    rust-kmain-uses-vga-puts)
      assert_source_pattern '\bvga_puts\b' 'kmain call to vga_puts' "${KMAIN}"
      ;;
    *)
      die "unknown case: ${CASE}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/vga-writer.sh '${ARCH}' '${CASE}'"
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
  [[ -r "${SOURCE}" ]] || die "missing VGA writer source: ${SOURCE}"

  if describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
