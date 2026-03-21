#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""
MAKE_DB=""
RUST_SOURCE_FILES=""
RUST_OBJECT_FILES=""

list_cases() {
  cat <<'EOF'
kernel-sources-glob-fails
kernel-entrypoint-not-root-fails
kernel-sources-not-single-fails
kernel-subsystem-objects-fail
EOF
}

describe_case() {
  case "$1" in
    kernel-sources-glob-fails) printf '%s\n' "rejects Makefile using src/kernel/*.rs in source selection" ;;
    kernel-entrypoint-not-root-fails) printf '%s\n' "rejects build where kernel root entrypoint is not src/kernel.rs" ;;
    kernel-sources-not-single-fails) printf '%s\n' "rejects multiple src/kernel sources being compiled" ;;
    kernel-subsystem-objects-fail) printf '%s\n' "rejects separate Rust outputs for kernel subsystem files" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

cleanup() {
  if [[ -n "${TMPDIR}" && -d "${TMPDIR}" ]]; then
    rm -rf "${TMPDIR}"
  fi
}

trap cleanup EXIT

make_tree() {
  TMPDIR="$(mktemp -d)"

  mkdir -p "${TMPDIR}/src/kernel"

  cat >"${TMPDIR}/src/kernel.rs" <<'EOF'
pub fn kmain() {}
EOF

cat >"${TMPDIR}/Makefile" <<'EOF'
arch ?= i386
rust_source_files := src/kernel.rs
rust_source_files += src/rust/kernel_marker.rs
rust_object_files := $(patsubst src/%.rs, build/arch/$(arch)/rust/%.o, $(rust_source_files))

build/arch/$(arch)/%.o: src/%.rs
	@mkdir -p $$(shell dirname $$@)
	@rustc \
		--crate-type lib \
		--emit=obj \
		-o $$@ \
		$$<
EOF

  # src/rust input keeps fixture deterministic for make -np expansion.
  mkdir -p "${TMPDIR}/src/rust"
  cat >"${TMPDIR}/src/rust/kernel_marker.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn kfs_rust_marker() {}
EOF
}

load_make_state() {
  MAKE_DB="$(make -np -f "${TMPDIR}/Makefile" ARCH="${ARCH}" 2>/dev/null || true)"
  if [[ -z "${MAKE_DB}" ]]; then
    echo "FAIL ${CASE}: failed to load temporary Makefile database"
    return 1
  fi

  RUST_SOURCE_FILES="$(
    printf '%s\n' "${MAKE_DB}" \
      | awk -v var="rust_source_files" '
        $1 == var && ($2=="=" || $2==":=" || $2=="?=" || $2=="+=") {
          $1 = "";
          $2 = "";
          sub(/^[[:space:]]+/, "");
          print;
          exit;
        }'
  )"
  RUST_OBJECT_FILES="$(
    printf '%s\n' "${MAKE_DB}" \
      | awk -v var="rust_object_files" '
        $1 == var && ($2=="=" || $2==":=" || $2=="?=" || $2=="+=") {
          $1 = "";
          $2 = "";
          sub(/^[[:space:]]+/, "");
          print;
          exit;
        }'
  )"

  if [[ -z "${RUST_SOURCE_FILES}" ]]; then
    echo "FAIL ${CASE}: rust_source_files is empty"
    return 1
  fi
  if [[ -z "${RUST_OBJECT_FILES}" ]]; then
    echo "FAIL ${CASE}: rust_object_files is empty"
    return 1
  fi
}

expect_failure() {
  local description="$1"
  shift
  if "$@"; then
    echo "FAIL ${CASE}: ${description} unexpectedly passed"
    return 1
  fi
  echo "PASS ${CASE}: ${description} rejected"
}

set_kernel_sources() {
  local value="$1"
  cat >>"${TMPDIR}/Makefile" <<EOF
rust_source_files := ${value}
rust_object_files := \$(patsubst src/%.rs, build/arch/\$(arch)/rust/%.o, \$(rust_source_files))
EOF
}

assert_no_kernel_peer_glob() {
  if rg -n 'src/kernel/\*\.rs' "${TMPDIR}/Makefile" >/dev/null; then
    return 1
  fi
  return 0
}

assert_kernel_root_is_single_entry() {
  mapfile -t kernel_sources < <(
    printf '%s\n' "${RUST_SOURCE_FILES}" | tr ' ' '\n' | rg '^src/kernel/[^[:space:]]+\.rs$' || true
  )

  local -a disallowed_sources=()
  local has_kernel_root=0
  local file

  for file in "${kernel_sources[@]}"; do
    [[ -n "${file}" ]] || continue
    if [[ "${file}" == "src/kernel.rs" ]]; then
      has_kernel_root=1
    else
      disallowed_sources+=("${file}")
    fi
  done

  if (( has_kernel_root == 0 )); then
    return 1
  fi
  if (( ${#disallowed_sources[@]} > 0 )); then
    return 1
  fi

  return 0
}

assert_no_kernel_subsystem_outputs() {
  if printf '%s\n' "${RUST_OBJECT_FILES}" | tr ' ' '\n' | rg "build/arch/${ARCH}/rust/kernel/" >/dev/null; then
    return 1
  fi
  return 0
}

run_case() {
  make_tree

  case "${CASE}" in
    kernel-sources-glob-fails)
      mkdir -p "${TMPDIR}/src/kernel"
      printf '\n' >"${TMPDIR}/src/kernel/kmain.rs"
      set_kernel_sources '$$(wildcard src/kernel/*.rs)'
      expect_failure "src/kernel/*.rs glob in rust_source_files" assert_no_kernel_peer_glob
      ;;
    kernel-entrypoint-not-root-fails)
      set_kernel_sources 'src/kernel/memory.rs'
      load_make_state
      expect_failure "non-root kernel source entrypoint" assert_kernel_root_is_single_entry
      ;;
    kernel-sources-not-single-fails)
      set_kernel_sources 'src/kernel.rs src/kernel/memory.rs'
      printf '\n' >"${TMPDIR}/src/kernel/memory.rs"
      load_make_state
      expect_failure "multiple kernel tree sources" assert_kernel_root_is_single_entry
      ;;
    kernel-subsystem-objects-fail)
      set_kernel_sources 'src/kernel.rs src/kernel/vga.rs'
      printf '\n' >"${TMPDIR}/src/kernel/vga.rs"
      load_make_state
      expect_failure "separate kernel subsystem object outputs" assert_no_kernel_subsystem_outputs
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

  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  run_case
}

main "$@"
