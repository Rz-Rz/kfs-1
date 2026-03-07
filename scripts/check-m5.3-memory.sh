#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
TEST_BIN="build/ut_mem"
TEST_SOURCE="tests/host_mem.rs"
SOURCE_CRATE="src/kernel/memory.rs"
SOURCE_IMPL="src/kernel/memory/memory_impl.rs"

# This stops the script as soon as it finds a blocking problem.
die() {
  echo "error: $*" >&2
  exit 2
}

# This searches the source tree for a pattern so we can verify that the Rust helpers are really present.
find_src_pattern() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S src >/dev/null
  else
    grep -REn "${pattern}" src >/dev/null
  fi
}

# This prints matching lines from the source tree to make a failed check easier to understand.
print_src_pattern() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S src || true
  else
    grep -REn "${pattern}" src || true
  fi
}

# This builds and runs the memory helper tests, then proves the expected Rust code and marker symbol are linked in.
main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${SOURCE_CRATE}" ]] || die "missing memory helper crate: ${SOURCE_CRATE}"
  [[ -r "${SOURCE_IMPL}" ]] || die "missing memory helper implementation: ${SOURCE_IMPL}"

  rustc --test -o "${TEST_BIN}" "${TEST_SOURCE}"
  "${TEST_BIN}"

  if ! find_src_pattern '\bfn[[:space:]]+(memcpy|memset)\b'; then
    echo "FAIL src: missing Rust functions memcpy/memset"
    exit 1
  fi

  if find_src_pattern 'extern[[:space:]]+"C".*\b(memcpy|memset)\b'; then
    echo "FAIL src: found extern \"C\" fallback for memcpy/memset"
    print_src_pattern 'extern[[:space:]]+"C".*\b(memcpy|memset)\b'
    exit 1
  fi

  local kernel_symbols
  kernel_symbols="$(nm -n "${KERNEL}")"
  if ! grep -qE '[[:space:]]T[[:space:]]+kfs_memory_helpers_marker$' <<<"${kernel_symbols}"; then
    echo "FAIL ${KERNEL}: missing marker symbol kfs_memory_helpers_marker"
    grep -E 'kfs_memory_helpers_marker|memory' <<<"${kernel_symbols}" || true
    exit 1
  fi

  echo "PASS ${TEST_SOURCE}"
  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${SOURCE_IMPL}"
  echo "PASS ${KERNEL}"
}

main "$@"
