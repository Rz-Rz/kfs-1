#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
ALLOWLIST="${SCRIPT_DIR}/fixtures/exports.${ARCH}.allowlist"

list_cases() {
	cat <<'EOF'
kernel-binary-crate-root-exists
host-library-crate-root-exists
shared-kernel-module-root-exists
freestanding-support-root-exists
kernel-first-level-dirs-match-allowlist
no-top-level-kernel-peer-files
types-has-no-abi-exports
core-services-types-have-no-raw-hardware-access
core-entry-does-not-call-driver-abi-directly
abi-exports-live-only-in-target-facades
exports-match-allowlist
makefile-does-not-compile-src-kernel-peers-individually
rust-kernel-entrypoint-is-src-main-rs
EOF
}

describe_case() {
	case "$1" in
	kernel-binary-crate-root-exists) printf '%s\n' "kernel binary crate root exists at src/main.rs" ;;
	host-library-crate-root-exists) printf '%s\n' "host library crate root exists at src/lib.rs" ;;
	shared-kernel-module-root-exists) printf '%s\n' "shared kernel module root exists at src/kernel/mod.rs" ;;
	freestanding-support-root-exists) printf '%s\n' "freestanding support root exists at src/freestanding/mod.rs" ;;
	kernel-first-level-dirs-match-allowlist) printf '%s\n' "kernel first-level directories match the architecture allowlist" ;;
	no-top-level-kernel-peer-files) printf '%s\n' "src/kernel has only the canonical top-level mod.rs file" ;;
	types-has-no-abi-exports) printf '%s\n' "types layer does not export ABI symbols" ;;
	core-services-types-have-no-raw-hardware-access) printf '%s\n' "core, services, and types avoid raw hardware access" ;;
	core-entry-does-not-call-driver-abi-directly) printf '%s\n' "core entry avoids direct driver ABI calls and direct VGA writes" ;;
	abi-exports-live-only-in-target-facades) printf '%s\n' "ABI exports live only in target entry and klib facade files" ;;
	exports-match-allowlist) printf '%s\n' "kernel exports match the architecture allowlist exactly" ;;
	makefile-does-not-compile-src-kernel-peers-individually) printf '%s\n' "Makefile does not compile src/kernel peer files individually" ;;
	rust-kernel-entrypoint-is-src-main-rs) printf '%s\n' "Makefile uses src/main.rs as the kernel Rust entrypoint" ;;
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

assert_kernel_binary_root_exists() {
	[[ -f "${REPO_ROOT}/src/main.rs" ]] || {
		echo "FAIL ${CASE}: missing src/main.rs"
		return 1
	}

	echo "PASS ${CASE}: src/main.rs exists"
}

assert_host_library_root_exists() {
	[[ -f "${REPO_ROOT}/src/lib.rs" ]] || {
		echo "FAIL ${CASE}: missing src/lib.rs"
		return 1
	}

	echo "PASS ${CASE}: src/lib.rs exists"
}

assert_shared_kernel_module_root_exists() {
	[[ -f "${REPO_ROOT}/src/kernel/mod.rs" ]] || {
		echo "FAIL ${CASE}: missing src/kernel/mod.rs"
		return 1
	}

	echo "PASS ${CASE}: src/kernel/mod.rs exists"
}

assert_freestanding_support_root_exists() {
	[[ -f "${REPO_ROOT}/src/freestanding/mod.rs" ]] || {
		echo "FAIL ${CASE}: missing src/freestanding/mod.rs"
		return 1
	}

	echo "PASS ${CASE}: src/freestanding/mod.rs exists"
}

assert_first_level_dirs_match_allowlist() {
	local expected actual

	expected="$(
		cat <<'EOF'
core
drivers
klib
machine
services
types
EOF
	)"
	actual="$(
		find "${REPO_ROOT}/src/kernel" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
	)"

	if [[ "${actual}" != "${expected}" ]]; then
		echo "FAIL ${CASE}: first-level directories do not match allowlist"
		printf 'expected:\n%s\n' "${expected}"
		printf 'actual:\n%s\n' "${actual}"
		return 1
	fi

	echo "PASS ${CASE}: kernel first-level directories match allowlist"
}

assert_no_top_level_peer_files() {
	local peers

	peers="$(
		find "${REPO_ROOT}/src/kernel" -mindepth 1 -maxdepth 1 -type f -name '*.rs' -printf '%f\n' | sort
	)"

	if [[ -n "${peers}" ]] && [[ "${peers}" != "mod.rs" ]]; then
		echo "FAIL ${CASE}: found forbidden top-level kernel peer files"
		printf '%s\n' "${peers}"
		return 1
	fi

	echo "PASS ${CASE}: src/kernel exposes only mod.rs at the top level"
}

assert_types_has_no_abi_exports() {
	local type_files

	mapfile -t type_files < <(find "${REPO_ROOT}/src/kernel/types" -type f -name '*.rs' 2>/dev/null | sort)

	if find_pattern '#\[no_mangle\]|extern[[:space:]]+"C"' "${type_files[@]}"; then
		echo "FAIL ${CASE}: types layer contains ABI export markers"
		if command -v rg >/dev/null 2>&1; then
			rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S "${type_files[@]}" || true
		fi
		return 1
	fi

	echo "PASS ${CASE}: types layer has no ABI exports"
}

assert_no_raw_hardware_access_in_high_layers() {
	local search_roots=()

	[[ -d "${REPO_ROOT}/src/kernel/core" ]] && search_roots+=("${REPO_ROOT}/src/kernel/core")
	[[ -d "${REPO_ROOT}/src/kernel/services" ]] && search_roots+=("${REPO_ROOT}/src/kernel/services")
	[[ -d "${REPO_ROOT}/src/kernel/types" ]] && search_roots+=("${REPO_ROOT}/src/kernel/types")

	[[ "${#search_roots[@]}" -gt 0 ]] || {
		echo "PASS ${CASE}: no high-layer directories exist yet"
		return 0
	}

	if find_pattern '0x[bB]8000|write_volatile|read_volatile|\binb\b|\boutb\b' "${search_roots[@]}"; then
		echo "FAIL ${CASE}: found raw hardware access in core/services/types"
		if command -v rg >/dev/null 2>&1; then
			rg -n '0x[bB]8000|write_volatile|read_volatile|\binb\b|\boutb\b' -S "${search_roots[@]}" || true
		fi
		return 1
	fi

	echo "PASS ${CASE}: core/services/types avoid raw hardware access"
}

assert_core_entry_avoids_driver_abi_directly() {
	local search_roots=()
	local offenders

	[[ -d "${REPO_ROOT}/src/kernel/core" ]] && search_roots+=("${REPO_ROOT}/src/kernel/core")

	[[ "${#search_roots[@]}" -gt 0 ]] || {
		echo "PASS ${CASE}: no core entry sources exist yet"
		return 0
	}

	offenders="$(
		rg -n '\bvga_(init|putc|puts)\b|0x[bB]8000|write_volatile' -S "${search_roots[@]}" || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found direct driver ABI call or VGA write in core entry path"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: core entry avoids direct driver ABI and VGA writes"
}

assert_abi_exports_live_only_in_target_facades() {
	local offenders

	offenders="$(
		find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
			xargs -0 rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S 2>/dev/null |
			grep -vE '^.*/src/kernel/(core/entry\.rs|drivers/keyboard/mod\.rs|klib/string/mod\.rs|klib/memory/mod\.rs):' || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found ABI export markers outside target facade files"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: ABI export markers stay in target facade files"
}

collect_actual_exports() {
	bash "${REPO_ROOT}/scripts/with-build-lock.sh" \
		bash "${REPO_ROOT}/scripts/container.sh" run -- \
		bash -lc "make -B all arch='${ARCH}' >/dev/null && nm -g --defined-only 'build/kernel-${ARCH}.bin' | awk '{print \$3}' | sed '/^$/d' | LC_ALL=C sort -u"
}

assert_exports_match_allowlist() {
	[[ -f "${ALLOWLIST}" ]] || die "missing allowlist: ${ALLOWLIST}"

	local expected actual
	expected="$(LC_ALL=C sort -u "${ALLOWLIST}")"
	actual="$(collect_actual_exports)"

	if [[ "${actual}" != "${expected}" ]]; then
		echo "FAIL ${CASE}: kernel exports do not match allowlist"
		printf 'expected:\n%s\n' "${expected}"
		printf 'actual:\n%s\n' "${actual}"
		return 1
	fi

	echo "PASS ${CASE}: kernel exports match allowlist"
}

assert_makefile_does_not_compile_peer_files() {
	local offenders

	offenders="$(
		rg -n 'wildcard src/kernel/\*\.rs|filter-out src/kernel/types\.rs,\$\(wildcard src/kernel/\*\.rs\)|build/arch/\$\(arch\)/rust/%\.o: src/%\.rs' "${REPO_ROOT}/Makefile" || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: Makefile still compiles kernel peer files individually"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: Makefile avoids per-file kernel peer compilation"
}

assert_kernel_entrypoint_is_src_main_rs() {
	local offenders

	offenders="$(
		rg -n 'src/main\.rs' "${REPO_ROOT}/Makefile" || true
	)"

	if [[ -z "${offenders}" ]]; then
		echo "FAIL ${CASE}: Makefile does not reference src/main.rs"
		return 1
	fi

	echo "PASS ${CASE}: Makefile references src/main.rs"
}

run_case() {
	case "${CASE}" in
	kernel-binary-crate-root-exists)
		assert_kernel_binary_root_exists
		;;
	host-library-crate-root-exists)
		assert_host_library_root_exists
		;;
	shared-kernel-module-root-exists)
		assert_shared_kernel_module_root_exists
		;;
	freestanding-support-root-exists)
		assert_freestanding_support_root_exists
		;;
	kernel-first-level-dirs-match-allowlist)
		assert_first_level_dirs_match_allowlist
		;;
	no-top-level-kernel-peer-files)
		assert_no_top_level_peer_files
		;;
	types-has-no-abi-exports)
		assert_types_has_no_abi_exports
		;;
	core-services-types-have-no-raw-hardware-access)
		assert_no_raw_hardware_access_in_high_layers
		;;
	core-entry-does-not-call-driver-abi-directly)
		assert_core_entry_avoids_driver_abi_directly
		;;
	abi-exports-live-only-in-target-facades)
		assert_abi_exports_live_only_in_target_facades
		;;
	exports-match-allowlist)
		assert_exports_match_allowlist
		;;
	makefile-does-not-compile-src-kernel-peers-individually)
		assert_makefile_does_not_compile_peer_files
		;;
	rust-kernel-entrypoint-is-src-main-rs)
		assert_kernel_entrypoint_is_src_main_rs
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
	describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
	run_case
}

main "$@"
