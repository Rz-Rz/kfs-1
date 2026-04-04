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
	kernel-entrypoint-not-root-fails) printf '%s\n' "rejects build where kernel root entrypoint is not src/main.rs" ;;
	kernel-sources-not-single-fails) printf '%s\n' "rejects multiple src/kernel sources being compiled" ;;
	kernel-subsystem-objects-fail) printf '%s\n' "rejects separate Rust outputs for kernel subsystem files" ;;
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
		rg -n "${pattern}" "$@"
	else
		grep -En "${pattern}" "$@"
	fi
}

stdin_matches_pattern() {
	local pattern="$1"

	if command -v rg >/dev/null 2>&1; then
		rg -q "${pattern}"
	else
		grep -Eq "${pattern}"
	fi
}

filter_stdin_pattern() {
	local pattern="$1"

	if command -v rg >/dev/null 2>&1; then
		rg "${pattern}" || true
	else
		grep -E "${pattern}" || true
	fi
}

extract_make_var() {
	local var_name="$1"

	awk -v var="${var_name}" '
    $1 == var && ($2=="=" || $2==":=" || $2=="?=" || $2=="+=") {
      $1 = "";
      $2 = "";
      sub(/^[[:space:]]+/, "");
      print;
      exit;
    }
  ' <<<"${MAKE_DB}"
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

	cat >"${TMPDIR}/src/main.rs" <<'EOF'
pub fn kmain() {}
EOF

	cat >"${TMPDIR}/Makefile" <<'EOF'
arch ?= i386
rust_source_files := src/main.rs
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

	RUST_SOURCE_FILES="$(extract_make_var "rust_source_files")"
	RUST_OBJECT_FILES="$(extract_make_var "rust_object_files")"

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
	if find_pattern 'src/kernel/\*\.rs' "${TMPDIR}/Makefile" >/dev/null; then
		return 1
	fi
	return 0
}

assert_kernel_root_is_single_entry() {
	mapfile -t kernel_sources < <(
		printf '%s\n' "${RUST_SOURCE_FILES}" | tr ' ' '\n' | filter_stdin_pattern '^src/(main\.rs|kernel/[^[:space:]]+\.rs)$'
	)

	local -a disallowed_sources=()
	local has_kernel_root=0
	local file

	for file in "${kernel_sources[@]}"; do
		[[ -n "${file}" ]] || continue
		if [[ "${file}" == "src/main.rs" ]]; then
			has_kernel_root=1
		else
			disallowed_sources+=("${file}")
		fi
	done

	if ((has_kernel_root == 0)); then
		return 1
	fi
	if ((${#disallowed_sources[@]} > 0)); then
		return 1
	fi

	return 0
}

assert_no_kernel_subsystem_outputs() {
	if printf '%s\n' "${RUST_OBJECT_FILES}" | tr ' ' '\n' | stdin_matches_pattern "build/arch/${ARCH}/rust/kernel/"; then
		return 1
	fi
	return 0
}

run_case() {
	make_tree

	case "${CASE}" in
	kernel-sources-glob-fails)
		set_kernel_sources '$$(wildcard src/kernel/*.rs)'
		expect_failure "src/kernel/*.rs glob in rust_source_files" assert_no_kernel_peer_glob
		;;
	kernel-entrypoint-not-root-fails)
		printf '\n' >"${TMPDIR}/src/kernel/extra.rs"
		set_kernel_sources 'src/kernel/extra.rs'
		load_make_state
		expect_failure "non-root kernel source entrypoint" assert_kernel_root_is_single_entry
		;;
	kernel-sources-not-single-fails)
		printf '\n' >"${TMPDIR}/src/kernel/extra.rs"
		set_kernel_sources 'src/main.rs src/kernel/extra.rs'
		load_make_state
		expect_failure "multiple kernel tree sources" assert_kernel_root_is_single_entry
		;;
	kernel-subsystem-objects-fail)
		printf '\n' >"${TMPDIR}/src/kernel/extra.rs"
		set_kernel_sources 'src/main.rs src/kernel/extra.rs'
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
