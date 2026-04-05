#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

list_cases() {
	cat <<'EOF'
layer-roots-exist-as-mod-rs
boot-start-hands-off-only-to-kmain
core-init-surface-exists
console-runtime-path-files-exist
core-init-avoids-raw-hw-and-asm
services-avoid-raw-hw-and-asm
inline-asm-stays-in-arch-or-machine
simd-intrinsics-stay-in-approved-files
types-have-no-side-effects
EOF
}

describe_case() {
	case "$1" in
	layer-roots-exist-as-mod-rs) printf '%s\n' "each kernel layer has a mod.rs root" ;;
	boot-start-hands-off-only-to-kmain) printf '%s\n' "start hands off only to kmain" ;;
	core-init-surface-exists) printf '%s\n' "core init plus freestanding panic surfaces exist" ;;
	console-runtime-path-files-exist) printf '%s\n' "console runtime path files exist through services and drivers" ;;
	core-init-avoids-raw-hw-and-asm) printf '%s\n' "core entry and init avoid raw hardware access and inline asm" ;;
	services-avoid-raw-hw-and-asm) printf '%s\n' "services avoid raw hardware access and inline asm" ;;
	inline-asm-stays-in-arch-or-machine) printf '%s\n' "inline asm stays in arch or machine only" ;;
	simd-intrinsics-stay-in-approved-files) printf '%s\n' "typed x86 SIMD intrinsics stay in approved CPU-probe and private klib leaf files" ;;
	types-have-no-side-effects) printf '%s\n' "types layer stays free of side effects and hardware primitives" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_layer_roots_exist() {
	local missing=()
	local layer

	for layer in core machine types klib drivers services; do
		[[ -f "${REPO_ROOT}/src/kernel/${layer}/mod.rs" ]] || missing+=("src/kernel/${layer}/mod.rs")
	done

	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: missing layer root files"
		printf '%s\n' "${missing[@]}"
		return 1
	fi

	echo "PASS ${CASE}: all layer root files exist"
}

assert_boot_hands_off_only_to_kmain() {
	local boot="${REPO_ROOT}/src/arch/${ARCH}/boot.asm"
	[[ -f "${boot}" ]] || die "missing boot asm: ${boot}"

	rg -n '^extern kmain$' "${boot}" >/dev/null || {
		echo "FAIL ${CASE}: boot asm does not declare extern kmain"
		return 1
	}

	if rg -n '^extern (vga_|kfs_strlen|kfs_strcmp|kfs_memcpy|kfs_memset)' "${boot}" >/dev/null; then
		echo "FAIL ${CASE}: boot asm declares helper or driver externs directly"
		rg -n '^extern (vga_|kfs_strlen|kfs_strcmp|kfs_memcpy|kfs_memset)' "${boot}" || true
		return 1
	fi

	if rg -n 'call (?!kmain\b)[A-Za-z_][A-Za-z0-9_]*' -P "${boot}" >/dev/null; then
		echo "FAIL ${CASE}: boot asm calls a non-kmain symbol"
		rg -n 'call (?!kmain\b)[A-Za-z_][A-Za-z0-9_]*' -P "${boot}" || true
		return 1
	fi

	echo "PASS ${CASE}: boot asm hands off only to kmain"
}

assert_core_init_surfaces_exist() {
	local missing=()
	local path

	for path in src/kernel/core/entry.rs src/kernel/core/init.rs src/freestanding/panic.rs; do
		[[ -f "${REPO_ROOT}/${path}" ]] || missing+=("${path}")
	done

	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: missing core surfaces"
		printf '%s\n' "${missing[@]}"
		return 1
	fi

	echo "PASS ${CASE}: core surfaces exist"
}

assert_console_runtime_path_files_exist() {
	local missing=()
	local path

	for path in \
		src/kernel/services/console.rs \
		src/kernel/drivers/vga_text/mod.rs \
		src/kernel/drivers/vga_text/writer.rs; do
		[[ -f "${REPO_ROOT}/${path}" ]] || missing+=("${path}")
	done

	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: missing runtime path files"
		printf '%s\n' "${missing[@]}"
		return 1
	fi

	echo "PASS ${CASE}: runtime path files exist"
}

assert_core_avoids_raw_hw_and_asm() {
	local search_roots=()
	local offenders

	[[ -d "${REPO_ROOT}/src/kernel/core" ]] && search_roots+=("${REPO_ROOT}/src/kernel/core")

	[[ "${#search_roots[@]}" -gt 0 ]] || {
		echo "PASS ${CASE}: no core sources exist yet"
		return 0
	}

	offenders="$(rg -n '\bvga_(init|putc|puts)\b|0x[bB]8000|\b(inb|outb)\b|core::arch::asm!' -S "${search_roots[@]}" || true)"
	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found raw hardware access or inline asm in core"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: core avoids raw hardware access and inline asm"
}

assert_services_avoid_raw_hw_and_asm() {
	local root="${REPO_ROOT}/src/kernel/services"
	[[ -d "${root}" ]] || {
		echo "FAIL ${CASE}: missing src/kernel/services"
		return 1
	}

	if rg -n '0x[bB]8000|write_volatile|read_volatile|\b(inb|outb)\b|core::arch::asm!' -S "${root}" >/dev/null; then
		echo "FAIL ${CASE}: found raw hardware access or inline asm in services"
		rg -n '0x[bB]8000|write_volatile|read_volatile|\b(inb|outb)\b|core::arch::asm!' -S "${root}" || true
		return 1
	fi

	echo "PASS ${CASE}: services avoid raw hardware access and inline asm"
}

assert_inline_asm_stays_in_arch_or_machine() {
	local offenders
	offenders="$(
		find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
			xargs -0 rg -n 'core::arch::asm!' -S 2>/dev/null |
			grep -vE '^.*/src/kernel/machine/' || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found inline asm outside machine layer"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: inline asm stays in machine layer"
}

assert_simd_intrinsics_stay_in_approved_files() {
	local offenders
	local allowlist='^.*/src/kernel/(machine/cpu\.rs|klib/memory/sse2_memcpy\.rs|klib/memory/sse2_memset\.rs):'

	offenders="$(
		find "${REPO_ROOT}/src" -type f \( -name '*.rs' -o -name '*.S' -o -name '*.asm' \) -print0 |
			xargs -0 rg -n 'core::arch::x86(::|_64::|$)|core::arch::x86_64(::|$)|#\[target_feature\(enable = "sse2"\)\]' -S 2>/dev/null |
			grep -vE "${allowlist}" || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found typed SIMD intrinsics outside approved files"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: typed SIMD intrinsics stay in approved files"
}

assert_types_have_no_side_effects() {
	local roots=()
	local offenders

	[[ -d "${REPO_ROOT}/src/kernel/types" ]] && roots+=("${REPO_ROOT}/src/kernel/types")

	[[ "${#roots[@]}" -gt 0 ]] || {
		echo "PASS ${CASE}: no types sources exist yet"
		return 0
	}

	offenders="$(rg -n 'write_volatile|read_volatile|\b(inb|outb)\b|core::arch::asm!|extern[[:space:]]+"C"|#\[no_mangle\]' -S "${roots[@]}" || true)"
	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found side effects or ABI markers in types"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: types stay free of side effects"
}

run_case() {
	case "${CASE}" in
	layer-roots-exist-as-mod-rs) assert_layer_roots_exist ;;
	boot-start-hands-off-only-to-kmain) assert_boot_hands_off_only_to_kmain ;;
	core-init-surface-exists) assert_core_init_surfaces_exist ;;
	console-runtime-path-files-exist) assert_console_runtime_path_files_exist ;;
	core-init-avoids-raw-hw-and-asm) assert_core_avoids_raw_hw_and_asm ;;
	services-avoid-raw-hw-and-asm) assert_services_avoid_raw_hw_and_asm ;;
	inline-asm-stays-in-arch-or-machine) assert_inline_asm_stays_in_arch_or_machine ;;
	simd-intrinsics-stay-in-approved-files) assert_simd_intrinsics_stay_in_approved_files ;;
	types-have-no-side-effects) assert_types_have_no_side_effects ;;
	*) die "unknown case: ${CASE}" ;;
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
