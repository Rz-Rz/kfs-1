#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-release-kernel-exports-kmain}"

list_cases() {
  cat <<'EOF'
release-kernel-exports-kmain
EOF
}

describe_case() {
  case "$1" in
    release-kernel-exports-kmain) printf '%s\n' "release kernel exports kmain" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

assert_kmain_symbol() {
  local kernel="$1"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make all/iso arch=${ARCH})"

  if ! nm -n "${kernel}" | grep -qE '[[:space:]]T[[:space:]]+kmain$'; then
    echo "FAIL ${kernel}: missing Rust entry symbol (expected: T kmain)"
    nm -n "${kernel}" | grep -E '\bkmain\b' || true
    return 1
  fi
}

run_direct() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ "${CASE}" == "release-kernel-exports-kmain" ]] || die "unknown case: ${CASE}"
  assert_kmain_symbol "build/kernel-${ARCH}.bin"
}

run_host_case() {
  bash scripts/container.sh run -- \
    bash -lc "make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/release-kmain-symbol.sh '${ARCH}' '${CASE}'"
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

  run_direct
}

main "$@"
