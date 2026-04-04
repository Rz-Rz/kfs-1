#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

list_cases() {
	cat <<'EOF'
core-depends-only-on-services-types-klib
services-do-not-import-driver-leaves-or-raw-hw
drivers-do-not-own-boot-policy
klib-does-not-depend-on-device-code
types-do-not-depend-on-io-or-policy
machine-stays-primitive-only
EOF
}

describe_case() {
	case "$1" in
	core-depends-only-on-services-types-klib) printf '%s\n' "core may depend only on services, types, and klib" ;;
	services-do-not-import-driver-leaves-or-raw-hw) printf '%s\n' "services do not depend on driver leaves or raw hardware I/O" ;;
	drivers-do-not-own-boot-policy) printf '%s\n' "drivers do not own boot policy or import core/services" ;;
	klib-does-not-depend-on-device-code) printf '%s\n' "klib does not depend on drivers, services, core, machine, or policy code" ;;
	types-do-not-depend-on-io-or-policy) printf '%s\n' "types do not depend on I/O/policy or higher-layer orchestration modules" ;;
	machine-stays-primitive-only) printf '%s\n' "machine stays primitive-only and avoids higher-layer policy dependencies" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

check_roots_exist() {
	local root="$1"
	[[ -d "${root}" ]] || {
		echo "FAIL ${CASE}: missing ${root#${REPO_ROOT}/}"
		return 1
	}
}

collect_rs_files() {
	local root="$1"
	local __out_var="$2"
	local __file
	local -n __out_files="${__out_var}"

	while IFS= read -r -d '' __file; do
		__out_files+=("${__file}")
	done < <(find "${root}" -type f -name '*.rs' -print0)
}

assert_no_matches() {
	local label="$1"
	local pattern="$2"
	shift 2
	local offenders

	offenders="$(rg -n "${pattern}" -S "$@" || true)"
	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found ${label}"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: ${label} absent"
}

assert_core_sources() {
	local -n out_files="$1"
	if [[ -d "${REPO_ROOT}/src/kernel/core" ]]; then
		collect_rs_files "${REPO_ROOT}/src/kernel/core" out_files
	fi

	[[ "${#out_files[@]}" -gt 0 ]] || {
		echo "FAIL ${CASE}: missing core sources"
		return 1
	}
}

assert_services_sources() {
	local -n out_files="$1"
	local path="${REPO_ROOT}/src/kernel/services"
	check_roots_exist "${path}" || return 1
	collect_rs_files "${path}" out_files
	[[ "${#out_files[@]}" -gt 0 ]] || {
		echo "FAIL ${CASE}: no services source files"
		return 1
	}
}

assert_drivers_sources() {
	local -n out_files="$1"
	local path="${REPO_ROOT}/src/kernel/drivers"
	check_roots_exist "${path}" || return 1
	collect_rs_files "${path}" out_files
	[[ "${#out_files[@]}" -gt 0 ]] || {
		echo "FAIL ${CASE}: no drivers source files"
		return 1
	}
}

assert_klib_sources() {
	local -n out_files="$1"
	local path="${REPO_ROOT}/src/kernel/klib"
	check_roots_exist "${path}" || return 1
	collect_rs_files "${path}" out_files
	[[ "${#out_files[@]}" -gt 0 ]] || {
		echo "FAIL ${CASE}: no klib source files"
		return 1
	}
}

assert_types_sources() {
	local -n out_files="$1"
	[[ -d "${REPO_ROOT}/src/kernel/types" ]] && collect_rs_files "${REPO_ROOT}/src/kernel/types" out_files
	[[ "${#out_files[@]}" -gt 0 ]] || {
		echo "FAIL ${CASE}: missing types sources"
		return 1
	}
}

assert_machine_sources() {
	local -n out_files="$1"
	local path="${REPO_ROOT}/src/kernel/machine"
	check_roots_exist "${path}" || return 1
	collect_rs_files "${path}" out_files
	[[ "${#out_files[@]}" -gt 0 ]] || {
		echo "FAIL ${CASE}: no machine source files"
		return 1
	}
}

assert_core_depends_downward_only() {
	local core_sources=()
	assert_core_sources core_sources || return 1
	assert_no_matches \
		'forbidden layer imports in core (drivers/machine/arch)' \
		'(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\b(crate::kernel::|super::|crate::)?(drivers|machine|arch)::' \
		"${core_sources[@]}"

	assert_no_matches \
		'forbidden raw I/O in core' \
		'([[:space:]])(vga_(init|putc|puts)|\bPort\b|\b(inb|outb)\(|0x[bB]8000)([[:space:]]|;|\)|\(|,|$)' \
		"${core_sources[@]}"

	assert_no_matches \
		'forbidden volatile/asm in core' \
		'\b(write_volatile|read_volatile|core::arch::asm!|#\[naked\])\b' \
		"${core_sources[@]}"
}

assert_services_do_not_import_driver_leaves_or_raw_hw() {
	local services_sources=()
	assert_services_sources services_sources || return 1

	assert_no_matches \
		'importing private driver leaves in services' \
		'(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::drivers::[A-Za-z0-9_]+::(writer|imp|_impl|logic_impl|memory_impl|string_impl)\b|#\[path[[:space:]]*=[[:space:]]*\"[^\"]*(writer|imp|_impl|logic_impl|memory_impl|string_impl)\.rs\"\]' \
		"${services_sources[@]}"

	assert_no_matches \
		'raw MMIO/port/raw asm in services' \
		'\b(0x[bB]8000|write_volatile|read_volatile|\b(inb|outb)\(|core::arch::asm!)\b' \
		"${services_sources[@]}"
}

assert_drivers_no_boot_policy() {
	local drivers_sources=()
	assert_drivers_sources drivers_sources || return 1

	assert_no_matches \
		'upward dependencies from drivers into core/services' \
		'(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\b(crate::kernel::)?(core|services)::' \
		"${drivers_sources[@]}"

	assert_no_matches \
		'boot policy surface owned in drivers' \
		'\bfn[[:space:]]+(kmain|run_early_init|serial_init|halt_forever|qemu_exit|panic_init|panic_startup|boot_loop)[[:space:]]*\(|#[[:space:]]*\[panic_handler\]' \
		"${drivers_sources[@]}"
}

assert_klib_no_device_deps() {
	local klib_sources=()
	assert_klib_sources klib_sources || return 1

	assert_no_matches \
		'forbidden cross-layer imports in klib' \
		'(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::(drivers|services|core|machine|types)::|\buse[[:space:]]+[^;\n]*\b(core|services|drivers|machine|types)::' \
		"${klib_sources[@]}"

	assert_no_matches \
		'raw hardware/policy usage in klib' \
		'\b(vga_|\bPort\b|\b(inb|outb)\(|0x[bB]8000|write_volatile|read_volatile|core::arch::asm!)\b' \
		"${klib_sources[@]}"
}

assert_types_no_io_or_policy() {
	local types_sources=()
	assert_types_sources types_sources || return 1

	assert_no_matches \
		'imports from higher orchestration layers in types' \
		'(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::(core|services|drivers|klib)::' \
		"${types_sources[@]}"

	assert_no_matches \
		'I/O side effects or policy in types' \
		'\b(inb|outb)\(|0x[bB]8000|write_volatile|read_volatile|core::arch::asm!|extern[[:space:]]+\"C\"|#\[no_mangle\]' \
		"${types_sources[@]}"

	assert_no_matches \
		'policy function ownership in types' \
		'\bfn[[:space:]]+(kmain|run_early_init|serial_init|halt_forever|qemu_exit|panic_init|boot_init)[[:space:]]*\(' \
		"${types_sources[@]}"
}

assert_machine_primitive_only() {
	local machine_sources=()
	assert_machine_sources machine_sources || return 1

	assert_no_matches \
		'forbidden layer imports in machine' \
		'(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::(core|services|drivers|types|klib)::|\bcrate::kernel::(core|services|drivers|types|klib)::' \
		"${machine_sources[@]}"

	assert_no_matches \
		'policy ownership in machine' \
		'\bfn[[:space:]]+(kmain|run_early_init|serial_init|halt_forever|qemu_exit)[[:space:]]*\(|#[[:space:]]*\[panic_handler\]' \
		"${machine_sources[@]}"
}

run_case() {
	case "${CASE}" in
	core-depends-only-on-services-types-klib) assert_core_depends_downward_only ;;
	services-do-not-import-driver-leaves-or-raw-hw) assert_services_do_not_import_driver_leaves_or_raw_hw ;;
	drivers-do-not-own-boot-policy) assert_drivers_no_boot_policy ;;
	klib-does-not-depend-on-device-code) assert_klib_no_device_deps ;;
	types-do-not-depend-on-io-or-policy) assert_types_no_io_or_policy ;;
	machine-stays-primitive-only) assert_machine_primitive_only ;;
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
