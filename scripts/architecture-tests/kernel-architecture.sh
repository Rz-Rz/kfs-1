#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
ALLOWLIST="${SCRIPT_DIR}/fixtures/exports.${ARCH}.allowlist"

list_cases() {
	cat <<'EOF'
target-tree-has-kernel-root
required-architecture-artifacts-exist
kernel-first-level-dirs-match-allowlist
no-top-level-kernel-peer-files
types-layer-contains-only-current-files
private-leaves-stay-under-owning-subsystem
forbidden-leaf-imports-are-absent
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
	target-tree-has-kernel-root) printf '%s\n' "kernel Rust tree is rooted at src/main.rs" ;;
	required-architecture-artifacts-exist) printf '%s\n' "all required future-architecture artifacts exist" ;;
	kernel-first-level-dirs-match-allowlist) printf '%s\n' "kernel first-level directories match the architecture allowlist" ;;
	no-top-level-kernel-peer-files) printf '%s\n' "src/kernel has only the canonical top-level mod.rs file" ;;
	types-layer-contains-only-current-files) printf '%s\n' "the types layer contains only the current canonical files" ;;
	private-leaves-stay-under-owning-subsystem) printf '%s\n' "private leaves stay under their owning subsystem directories" ;;
	forbidden-leaf-imports-are-absent) printf '%s\n' "private leaves are not imported outside their owning facade" ;;
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

assert_kernel_root_exists() {
	[[ -f "${REPO_ROOT}/src/main.rs" ]] || {
		echo "FAIL ${CASE}: missing src/main.rs"
		return 1
	}

	echo "PASS ${CASE}: src/main.rs exists"
}

assert_required_architecture_artifacts_exist() {
	local missing=()
	local path

	while IFS= read -r path; do
		[[ -f "${REPO_ROOT}/${path}" ]] || missing+=("${path}")
	done <<'EOF'
src/main.rs
src/freestanding/mod.rs
src/freestanding/panic.rs
src/freestanding/section_markers.rs
src/kernel/mod.rs
src/kernel/core/entry.rs
src/kernel/core/init.rs
src/kernel/machine/port.rs
src/kernel/types/range.rs
src/kernel/types/screen.rs
src/kernel/klib/string/mod.rs
src/kernel/klib/string/imp.rs
src/kernel/klib/memory/mod.rs
src/kernel/klib/memory/imp.rs
src/kernel/drivers/serial/mod.rs
src/kernel/drivers/keyboard/mod.rs
src/kernel/drivers/keyboard/imp.rs
src/kernel/drivers/vga_text/mod.rs
src/kernel/drivers/vga_text/writer.rs
src/kernel/services/diagnostics.rs
src/kernel/services/console.rs
EOF

	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: missing required architecture artifacts"
		printf '%s\n' "${missing[@]}"
		return 1
	fi

	echo "PASS ${CASE}: all required architecture artifacts exist"
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

assert_types_layer_contains_only_current_files() {
	local actual expected

	if [[ ! -d "${REPO_ROOT}/src/kernel/types" ]]; then
		echo "FAIL ${CASE}: missing src/kernel/types"
		return 1
	fi

	actual="$(
		find "${REPO_ROOT}/src/kernel/types" -mindepth 1 -maxdepth 1 -type f -name '*.rs' -printf '%f\n' | sort
	)"
	expected="$(
		cat <<'EOF'
mod.rs
range.rs
screen.rs
EOF
	)"

	if [[ "${actual}" != "${expected}" ]]; then
		echo "FAIL ${CASE}: types layer contains unexpected files"
		printf 'expected:\n%s\n' "${expected}"
		printf 'actual:\n%s\n' "${actual}"
		return 1
	fi

	echo "PASS ${CASE}: types layer contains only the current canonical files"
}

assert_private_leaves_stay_under_owning_subsystem() {
	local offenders

	offenders="$(
		find "${REPO_ROOT}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' -o -name '*_impl.rs' -o -name 'logic_impl.rs' \) -printf '%P\n' |
			awk -F/ '
        {
          if (NF < 3) {
            print $0
            next
          }
          if ($1 !~ /^(core|drivers|klib|machine|services|types)$/) {
            print $0
          }
        }
      '
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found private leaves outside allowed subsystem directories"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: private leaves stay under owning subsystem directories"
}

assert_forbidden_leaf_imports_are_absent() {
	local offenders

	if command -v rg >/dev/null 2>&1; then
		offenders="$(
			find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
				xargs -0 rg -n '#\[path = ".*(imp|writer|logic_impl|string_impl|memory_impl)\.rs"\]' -S 2>/dev/null |
				grep -vE '^.*/(mod|entry|string|memory|vga|kmain)\.rs:|^.*/drivers/keyboard/mod\.rs:' || true
		)"
	else
		offenders="$(
			find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
				xargs -0 grep -En '#\[path = ".*(imp|writer|logic_impl|string_impl|memory_impl)\.rs"\]' 2>/dev/null |
				grep -vE '^.*/(mod|entry|string|memory|vga|kmain)\.rs:|^.*/drivers/keyboard/mod\.rs:' || true
		)"
	fi

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found private leaf import outside owning facade"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: private leaf imports stay behind facades"
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
	target-tree-has-kernel-root)
		assert_kernel_root_exists
		;;
	required-architecture-artifacts-exist)
		assert_required_architecture_artifacts_exist
		;;
	kernel-first-level-dirs-match-allowlist)
		assert_first_level_dirs_match_allowlist
		;;
	no-top-level-kernel-peer-files)
		assert_no_top_level_peer_files
		;;
	types-layer-contains-only-current-files)
		assert_types_layer_contains_only_current_files
		;;
	private-leaves-stay-under-owning-subsystem)
		assert_private_leaves_stay_under_owning_subsystem
		;;
	forbidden-leaf-imports-are-absent)
		assert_forbidden_leaf_imports_are_absent
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
