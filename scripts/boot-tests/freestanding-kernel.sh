#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-all}"
CUSTOM_KERNEL="${KFS_M0_2_KERNEL:-}"

list_cases() {
	cat <<'EOF'
rust-entry-symbol-present
asm-entry-symbol-present
no-pt-interp-segment
no-interp-section
no-dynamic-section
no-undefined-symbols
no-libc-strings
no-loader-strings
EOF
}

describe_case() {
	case "$1" in
	rust-entry-symbol-present) printf '%s\n' "kernel includes the Rust entry symbol" ;;
	asm-entry-symbol-present) printf '%s\n' "kernel exposes the ASM entry symbol" ;;
	no-pt-interp-segment) printf '%s\n' "kernel has no PT_INTERP segment" ;;
	no-interp-section) printf '%s\n' "kernel has no .interp section" ;;
	no-dynamic-section) printf '%s\n' "kernel has no .dynamic section" ;;
	no-undefined-symbols) printf '%s\n' "kernel has no undefined symbols" ;;
	no-libc-strings) printf '%s\n' "kernel has no libc marker strings" ;;
	no-loader-strings) printf '%s\n' "kernel has no loader marker strings" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_rust_entry_symbol() {
	local kernel="$1"
	local symbol_table
	symbol_table="$(nm -n "${kernel}")"
	if ! awk '$3 == "kmain" { found = 1 } END { exit(found ? 0 : 1) }' <<<"${symbol_table}"; then
		echo "FAIL ${kernel}: Rust entry symbol missing (kmain)"
		echo "hint: the kernel must include the Rust kernel entrypoint so M0.2 is proven for ASM+Rust, not ASM-only"
		return 1
	fi
}

assert_asm_entry_symbol() {
	local kernel="$1"
	local symbol_table
	symbol_table="$(nm -n "${kernel}")"
	if ! awk '$3 == "start" { found = 1 } END { exit(found ? 0 : 1) }' <<<"${symbol_table}"; then
		echo "FAIL ${kernel}: ASM entry symbol missing (start)"
		echo "hint: the test kernel must link the ASM boot object and expose the entry symbol"
		return 1
	fi
}

assert_no_pt_interp_segment() {
	local kernel="$1"
	if readelf -lW "${kernel}" | grep -qE '^[[:space:]]*INTERP[[:space:]]'; then
		echo "FAIL ${kernel}: PT_INTERP present (dynamic loader required)"
		readelf -lW "${kernel}" | grep -E '^[[:space:]]*INTERP[[:space:]]' || true
		return 1
	fi
}

assert_no_interp_section() {
	local kernel="$1"
	if readelf -SW "${kernel}" | grep -qE '[[:space:]]\.interp[[:space:]]'; then
		echo "FAIL ${kernel}: .interp section present (dynamic linking metadata)"
		readelf -SW "${kernel}" | grep -E '[[:space:]]\.interp[[:space:]]' || true
		return 1
	fi
}

assert_no_dynamic_section() {
	local kernel="$1"
	if readelf -SW "${kernel}" | grep -qE '[[:space:]]\.dynamic[[:space:]]'; then
		echo "FAIL ${kernel}: .dynamic section present (dynamic linking metadata)"
		readelf -SW "${kernel}" | grep -E '[[:space:]]\.dynamic[[:space:]]' || true
		return 1
	fi
}

assert_no_undefined_symbols() {
	local kernel="$1"
	if [[ -n "$(nm -u "${kernel}" | head -n 1)" ]]; then
		echo "FAIL ${kernel}: undefined symbols present"
		nm -u "${kernel}" | head -n 50 || true
		return 1
	fi
}

assert_no_libc_strings() {
	local kernel="$1"
	if strings "${kernel}" | grep -qiE '(glibc|libc\.so)'; then
		echo "FAIL ${kernel}: libc marker strings found"
		strings "${kernel}" | grep -iE '(glibc|libc\.so)' | head -n 20 || true
		return 1
	fi
}

assert_no_loader_strings() {
	local kernel="$1"
	if strings "${kernel}" | grep -qiE 'ld-linux'; then
		echo "FAIL ${kernel}: loader marker strings found"
		strings "${kernel}" | grep -iE 'ld-linux' | head -n 20 || true
		return 1
	fi
}

run_case_against_kernel() {
	local kernel="$1"
	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

	case "${CASE}" in
	rust-entry-symbol-present) assert_rust_entry_symbol "${kernel}" ;;
	asm-entry-symbol-present) assert_asm_entry_symbol "${kernel}" ;;
	no-pt-interp-segment) assert_no_pt_interp_segment "${kernel}" ;;
	no-interp-section) assert_no_interp_section "${kernel}" ;;
	no-dynamic-section) assert_no_dynamic_section "${kernel}" ;;
	no-undefined-symbols) assert_no_undefined_symbols "${kernel}" ;;
	no-libc-strings) assert_no_libc_strings "${kernel}" ;;
	no-loader-strings) assert_no_loader_strings "${kernel}" ;;
	*) die "unknown case: ${CASE}" ;;
	esac
}

run_all_cases_against_kernel() {
	local kernel="$1"
	local failure=0
	local case_name
	local original_case="${CASE}"

	for case_name in \
		rust-entry-symbol-present \
		asm-entry-symbol-present \
		no-pt-interp-segment \
		no-interp-section \
		no-dynamic-section \
		no-undefined-symbols \
		no-libc-strings \
		no-loader-strings; do
		CASE="${case_name}"
		run_case_against_kernel "${kernel}" || failure=1
	done

	CASE="${original_case}"

	if [[ "${failure}" -eq 0 ]]; then
		echo "PASS ${kernel}"
		return 0
	fi

	return 1
}

run_direct() {
	case "${CASE}" in
	all | rust-entry-symbol-present | asm-entry-symbol-present | no-pt-interp-segment | no-interp-section | no-dynamic-section | no-undefined-symbols | no-libc-strings | no-loader-strings) ;;
	*) die "unknown case: ${CASE}" ;;
	esac

	local failures=0

	if [[ -n "${CUSTOM_KERNEL}" ]]; then
		[[ -r "${CUSTOM_KERNEL}" ]] || die "missing custom kernel artifact: ${CUSTOM_KERNEL}"
		if [[ "${CASE}" == "all" ]]; then
			run_all_cases_against_kernel "${CUSTOM_KERNEL}" || failures=$((failures + 1))
		else
			run_case_against_kernel "${CUSTOM_KERNEL}" || failures=$((failures + 1))
		fi

		if [[ "${failures}" -ne 0 ]]; then
			exit 1
		fi
		return 0
	fi

	[[ -r "build/kernel-${ARCH}-test.bin" ]] || die "missing test kernel: build/kernel-${ARCH}-test.bin (build it with make iso-test arch=${ARCH})"
	if [[ "${CASE}" == "all" ]]; then
		run_all_cases_against_kernel "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))
	else
		run_case_against_kernel "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))
	fi

	if [[ "${KFS_M0_2_INCLUDE_RELEASE:-0}" == "1" ]]; then
		[[ -r "build/kernel-${ARCH}.bin" ]] || die "missing release kernel: build/kernel-${ARCH}.bin (build it with make all arch=${ARCH})"
		if [[ "${CASE}" == "all" ]]; then
			run_all_cases_against_kernel "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
		else
			run_case_against_kernel "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
		fi
	fi

	if [[ "${failures}" -ne 0 ]]; then
		exit 1
	fi
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

	run_direct
}

main "$@"
