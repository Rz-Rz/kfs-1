#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TYPES_SOURCE="src/kernel/types/mod.rs"
MACHINE_PORT_SOURCE="src/kernel/machine/port.rs"
PORT_SOURCE="src/kernel/machine/port.rs"
RANGE_SOURCE="src/kernel/types/range.rs"
SCREEN_SOURCE="src/kernel/types/screen.rs"
ENTRY_SOURCE="src/kernel/core/entry.rs"
INIT_SOURCE="src/kernel/core/init.rs"
STRING_SOURCE="src/kernel/klib/string/mod.rs"
MEMORY_SOURCE="src/kernel/klib/memory/mod.rs"

list_cases() {
	cat <<'EOF'
helper-boundary-files-exist
helper-abi-uses-primitive-core-types
kernel-helper-code-avoids-std
no-alias-only-primitive-layer
port-uses-repr-transparent
kernel-range-uses-repr-c
screen-types-exist
color-code-uses-repr-transparent
screen-cell-uses-repr-c
cursor-pos-uses-repr-c
helper-wrappers-use-extern-c-and-no-mangle
helper-private-impl-not-imported-directly
serial-path-uses-port-type
layout-path-uses-kernel-range-type
future-port-owner-and-repr
future-kernel-range-owner-and-repr
future-screen-types-owner-and-repr
EOF
}

describe_case() {
	case "$1" in
	helper-boundary-files-exist) printf '%s\n' "helper boundary and type facade files exist" ;;
	helper-abi-uses-primitive-core-types) printf '%s\n' "helper ABI uses primitive/core-compatible types only" ;;
	kernel-helper-code-avoids-std) printf '%s\n' "helper and type code avoids std" ;;
	no-alias-only-primitive-layer) printf '%s\n' "type layer avoids alias-only primitive wrappers" ;;
	port-uses-repr-transparent) printf '%s\n' "Port uses repr(transparent)" ;;
	kernel-range-uses-repr-c) printf '%s\n' "KernelRange uses repr(C)" ;;
	screen-types-exist) printf '%s\n' "future screen type file exists" ;;
	color-code-uses-repr-transparent) printf '%s\n' "ColorCode uses repr(transparent)" ;;
	screen-cell-uses-repr-c) printf '%s\n' "ScreenCell uses repr(C)" ;;
	cursor-pos-uses-repr-c) printf '%s\n' "CursorPos uses repr(C)" ;;
	helper-wrappers-use-extern-c-and-no-mangle) printf '%s\n' "helper wrappers keep extern C and no_mangle" ;;
	helper-private-impl-not-imported-directly) printf '%s\n' "private helper impl files are not imported directly outside boundary files" ;;
	serial-path-uses-port-type) printf '%s\n' "serial runtime path uses Port through machine and driver layers" ;;
	layout-path-uses-kernel-range-type) printf '%s\n' "layout path uses KernelRange instead of naked pairs" ;;
	future-port-owner-and-repr) printf '%s\n' "Port is owned by src/kernel/machine/port.rs with repr(transparent)" ;;
	future-kernel-range-owner-and-repr) printf '%s\n' "KernelRange is owned by src/kernel/types/range.rs with repr(C)" ;;
	future-screen-types-owner-and-repr) printf '%s\n' "ColorCode/ScreenCell/CursorPos are owned by src/kernel/types/screen.rs and have required repr" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

ensure_sources_exist() {
	local path
	for path in "$@"; do
		[[ -r "${path}" ]] || die "missing required source: ${path}"
	done
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

assert_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2
	if ! find_pattern "${pattern}" "$@"; then
		echo "FAIL src: missing ${label}"
		return 1
	fi
	echo "PASS src: ${label}"
}

assert_no_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2
	if find_pattern "${pattern}" "$@"; then
		echo "FAIL src: found ${label}"
		if command -v rg >/dev/null 2>&1; then
			rg -n "${pattern}" -S "$@" || true
		else
			grep -En "${pattern}" "$@" || true
		fi
		return 1
	fi
	echo "PASS src: ${label}"
}

assert_struct_has_repr() {
	local repr="$1"
	local struct_name="$2"
	local label="$3"
	local file="$4"
	if awk -v repr="${repr}" -v name="${struct_name}" '
    $0 ~ ("#\\[repr\\(" repr "\\)\\]") { seen_repr = 1; next }
    seen_repr && $0 ~ /^#\[/ { next }
    seen_repr && $0 ~ ("pub struct " name "([^A-Za-z0-9_]|$)") { found = 1; exit }
    { seen_repr = 0 }
    END { exit(found ? 0 : 1) }
  ' "${file}"; then
		echo "PASS src: ${label}"
		return 0
	fi
	echo "FAIL src: missing ${label}"
	return 1
}

assert_struct_owned_only_in_file() {
	local type_name="$1"
	local owner_file="$2"
	local label="$3"
	local pattern="pub[[:space:]]+struct[[:space:]]+${type_name}\\b"
	local offenders

	assert_pattern "${pattern}" "${label}" "${owner_file}" || return 1

	if command -v rg >/dev/null 2>&1; then
		offenders="$(find src/kernel -type f -name '*.rs' -print0 | xargs -0 rg -n "${pattern}" -S 2>/dev/null || true)"
	else
		offenders="$(find src/kernel -type f -name '*.rs' -print0 | xargs -0 grep -EnE "${pattern}" 2>/dev/null || true)"
	fi

	offenders="$(printf '%s\n' "${offenders}" | awk -F: -v owner="${owner_file}" '$1 != owner {print}')"
	if [[ -n "${offenders}" ]]; then
		echo "FAIL src: ${label} defined outside ${owner_file}"
		printf '%s\n' "${offenders}"
		return 1
	fi
	echo "PASS src: ${label} owned only by ${owner_file}"
}

assert_private_impl_boundary() {
	local offenders
	if command -v rg >/dev/null 2>&1; then
		offenders="$(find src/kernel -type f -name '*.rs' -print0 | xargs -0 rg -n 'klib/(string|memory)/(imp|sse2_[A-Za-z0-9_]+)\.rs' -S 2>/dev/null | grep -vE '^src/kernel/klib/(string|memory)/mod\.rs:' || true)"
	else
		offenders="$(find src/kernel -type f -name '*.rs' -print0 | xargs -0 grep -En 'klib/(string|memory)/(imp|sse2_[A-Za-z0-9_]+)\.rs' 2>/dev/null | grep -vE '^src/kernel/klib/(string|memory)/mod\.rs:' || true)"
	fi
	if [[ -n "${offenders}" ]]; then
		echo "FAIL src: found private helper import outside public boundary file"
		printf '%s\n' "${offenders}"
		return 1
	fi
	echo "PASS src: private helper imports stay in boundary files"
}

run_direct_case() {
	case "${CASE}" in
	helper-boundary-files-exist)
		ensure_sources_exist "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}" "${SCREEN_SOURCE}" "${ENTRY_SOURCE}" "${INIT_SOURCE}" "${STRING_SOURCE}" "${MEMORY_SOURCE}"
		echo "PASS files: helper boundary and type facade files exist"
		;;
	helper-abi-uses-primitive-core-types)
		ensure_sources_exist "${STRING_SOURCE}" "${MEMORY_SOURCE}"
		assert_pattern '#\[no_mangle\]' 'no_mangle helper export' "${STRING_SOURCE}"
		assert_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' 'extern C helper export' "${STRING_SOURCE}"
		assert_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' 'extern C memory helper export' "${MEMORY_SOURCE}"
		assert_no_pattern 'fn[[:space:]]+kfs_[A-Za-z0-9_]+\([^)]*(String|Vec|Option|Result|&|\[[^]]*\])' 'forbidden ABI types in helper exports' "${STRING_SOURCE}"
		;;
	kernel-helper-code-avoids-std)
		ensure_sources_exist "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}" "${SCREEN_SOURCE}" "${STRING_SOURCE}" "${MEMORY_SOURCE}" "${ENTRY_SOURCE}" "${INIT_SOURCE}"
		assert_no_pattern '\bstd::|extern[[:space:]]+crate[[:space:]]+std\b' 'std usage in helper/type layer' "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}" "${SCREEN_SOURCE}" "${STRING_SOURCE}" "${MEMORY_SOURCE}" "${ENTRY_SOURCE}" "${INIT_SOURCE}"
		;;
	no-alias-only-primitive-layer)
		ensure_sources_exist "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}" "${SCREEN_SOURCE}"
		assert_no_pattern 'type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(u8|u16|u32|usize|i32|isize)\b' 'alias-only primitive type wrapper' "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}" "${SCREEN_SOURCE}"
		;;
	port-uses-repr-transparent)
		ensure_sources_exist "${PORT_SOURCE}"
		assert_pattern '#\[repr\(transparent\)\]' 'Port repr(transparent)' "${PORT_SOURCE}"
		;;
	kernel-range-uses-repr-c)
		ensure_sources_exist "${RANGE_SOURCE}"
		assert_pattern '#\[repr\(C\)\]' 'KernelRange repr(C)' "${RANGE_SOURCE}"
		;;
	screen-types-exist)
		ensure_sources_exist "${SCREEN_SOURCE}"
		assert_pattern '\bstruct[[:space:]]+ColorCode\b' 'ColorCode type' "${SCREEN_SOURCE}"
		assert_pattern '\bstruct[[:space:]]+ScreenCell\b' 'ScreenCell type' "${SCREEN_SOURCE}"
		assert_pattern '\bstruct[[:space:]]+CursorPos\b' 'CursorPos type' "${SCREEN_SOURCE}"
		;;
	color-code-uses-repr-transparent)
		ensure_sources_exist "${SCREEN_SOURCE}"
		assert_struct_has_repr 'transparent' 'ColorCode' 'ColorCode repr(transparent)' "${SCREEN_SOURCE}"
		;;
	screen-cell-uses-repr-c)
		ensure_sources_exist "${SCREEN_SOURCE}"
		assert_struct_has_repr 'C' 'ScreenCell' 'ScreenCell repr(C)' "${SCREEN_SOURCE}"
		;;
	cursor-pos-uses-repr-c)
		ensure_sources_exist "${SCREEN_SOURCE}"
		assert_struct_has_repr 'C' 'CursorPos' 'CursorPos repr(C)' "${SCREEN_SOURCE}"
		;;
	helper-wrappers-use-extern-c-and-no-mangle)
		ensure_sources_exist "${STRING_SOURCE}"
		assert_pattern '#\[no_mangle\]' 'no_mangle helper wrapper' "${STRING_SOURCE}"
		assert_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' 'extern C helper wrapper' "${STRING_SOURCE}"
		;;
	helper-private-impl-not-imported-directly)
		ensure_sources_exist "${INIT_SOURCE}" "${STRING_SOURCE}" "${MEMORY_SOURCE}"
		assert_private_impl_boundary
		;;
	serial-path-uses-port-type)
		ensure_sources_exist "${MACHINE_PORT_SOURCE}" "${ENTRY_SOURCE}" "src/kernel/drivers/serial/mod.rs" "src/kernel/services/diagnostics.rs"
		assert_pattern '\bstruct[[:space:]]+Port\b' 'Port machine primitive exists' "${MACHINE_PORT_SOURCE}"
		assert_pattern '\bcrate::kernel::machine::port::Port\b' 'serial driver imports Port' "src/kernel/drivers/serial/mod.rs"
		assert_pattern '\bPort::new\(' 'serial driver constructs machine Port values' "src/kernel/drivers/serial/mod.rs"
		assert_pattern '\bdrivers::serial\b' 'diagnostics service reaches serial driver facade' "src/kernel/services/diagnostics.rs"
		assert_no_pattern '\bPort\b' 'Port leaking into core entry' "${ENTRY_SOURCE}"
		;;
	layout-path-uses-kernel-range-type)
		ensure_sources_exist "${ENTRY_SOURCE}" "${INIT_SOURCE}" "${RANGE_SOURCE}"
		assert_pattern 'KernelRange::new\(' 'KernelRange construction in core entry' "${ENTRY_SOURCE}"
		assert_pattern 'layout_order_is_sane\(' 'KernelRange-based layout helper call from core init' "${INIT_SOURCE}"
		;;
	future-port-owner-and-repr)
		ensure_sources_exist "${MACHINE_PORT_SOURCE}"
		assert_struct_owned_only_in_file 'Port' "${MACHINE_PORT_SOURCE}" 'Port owned by src/kernel/machine/port.rs'
		assert_pattern '#\[repr\(transparent\)\]' 'Port repr(transparent)' "${MACHINE_PORT_SOURCE}"
		;;
	future-kernel-range-owner-and-repr)
		ensure_sources_exist "${RANGE_SOURCE}"
		assert_struct_owned_only_in_file 'KernelRange' "${RANGE_SOURCE}" 'KernelRange owned by src/kernel/types/range.rs'
		assert_pattern '#\[repr\(C\)\]' 'KernelRange repr(C)' "${RANGE_SOURCE}"
		;;
	future-screen-types-owner-and-repr)
		ensure_sources_exist "${SCREEN_SOURCE}"
		assert_struct_owned_only_in_file 'ColorCode' "${SCREEN_SOURCE}" 'ColorCode owned by src/kernel/types/screen.rs'
		assert_struct_owned_only_in_file 'ScreenCell' "${SCREEN_SOURCE}" 'ScreenCell owned by src/kernel/types/screen.rs'
		assert_struct_owned_only_in_file 'CursorPos' "${SCREEN_SOURCE}" 'CursorPos owned by src/kernel/types/screen.rs'
		assert_struct_has_repr 'transparent' 'ColorCode' 'ColorCode repr(transparent)' "${SCREEN_SOURCE}"
		assert_struct_has_repr 'C' 'ScreenCell' 'ScreenCell repr(C)' "${SCREEN_SOURCE}"
		assert_struct_has_repr 'C' 'CursorPos' 'CursorPos repr(C)' "${SCREEN_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {helper-boundary-files-exist|helper-abi-uses-primitive-core-types|kernel-helper-code-avoids-std|no-alias-only-primitive-layer|port-uses-repr-transparent|kernel-range-uses-repr-c|screen-types-exist|color-code-uses-repr-transparent|screen-cell-uses-repr-c|cursor-pos-uses-repr-c|helper-wrappers-use-extern-c-and-no-mangle|helper-private-impl-not-imported-directly|serial-path-uses-port-type|layout-path-uses-kernel-range-type|future-port-owner-and-repr|future-kernel-range-owner-and-repr|future-screen-types-owner-and-repr}"
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
	run_direct_case
}

main "$@"
