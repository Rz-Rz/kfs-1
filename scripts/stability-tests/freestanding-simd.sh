#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
MAKEFILE_SOURCE="Makefile"
KERNEL_PATH="build/kernel-${ARCH}.bin"
SIMD_PATTERN='xmm[0-9]+|ymm[0-9]+|zmm[0-9]+|mm[0-7]+|(^|[^[:alnum:]_])(xorps|movaps|movups|movdqa|movdqu|pxor|xorpd|movapd|movupd|movq|movd|movntdq|movntps|movntpd|paddb|paddw|paddd|pand|pandn|por|ldmxcsr|stmxcsr|fxsave|fxrstor|maskmovq|emms)([^[:alnum:]_]|$)'
APPROVED_STATE_PATTERN='(^|[^[:alnum:]_])(ldmxcsr)([^[:alnum:]_]|$)'
APPROVED_MEMORY_SYMBOL_PATTERN='main::kernel::klib::memory::sse2_memcpy::memcpy_sse2|main::kernel::klib::memory::sse2_memset::memset'

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
default-freestanding-kernel-limits-approved-simd-state-instructions
compact-freestanding-kernel-limits-approved-simd-state-instructions
makefile-uses-non-simd-rust-target
EOF
}

describe_case() {
	case "$1" in
	default-freestanding-kernel-limits-approved-simd-state-instructions) printf '%s\n' "default freestanding kernel only permits approved SIMD control-state instructions" ;;
	compact-freestanding-kernel-limits-approved-simd-state-instructions) printf '%s\n' "compact freestanding kernel only permits approved SIMD control-state instructions" ;;
	makefile-uses-non-simd-rust-target) printf '%s\n' "Makefile uses a non-SIMD x86 Rust target for freestanding builds" ;;
	*) return 1 ;;
	esac
}

ensure_tools() {
	command -v objdump >/dev/null 2>&1 || die "missing required tool: objdump"
	command -v rg >/dev/null 2>&1 || die "missing required tool: rg"
}

assert_makefile_wiring() {
	rg -n 'rust_target[[:space:]]*:=[[:space:]]*i586-unknown-linux-gnu' "${MAKEFILE_SOURCE}" >/dev/null ||
		die "Makefile does not define the freestanding Rust target"
}

build_kernel() {
	local preset="$1"
	local build_log

	rm -f "${KERNEL_PATH}"
	build_log="$(mktemp -t kfs-simd-build.XXXXXX)"
	if ! KFS_SCREEN_GEOMETRY_PRESET="${preset}" make -B "${KERNEL_PATH}" arch="${ARCH}" >"${build_log}" 2>&1; then
		cat "${build_log}" >&2
		rm -f "${build_log}"
		die "failed to build ${KERNEL_PATH} for preset ${preset}"
	fi
	rm -f "${build_log}"
	[[ -r "${KERNEL_PATH}" ]] || die "missing artifact: ${KERNEL_PATH}"
}

assert_kernel_has_only_approved_simd() {
	local preset="$1"
	local disassembly
	local current_symbol=""
	local failures=()
	local line

	build_kernel "${preset}"
	disassembly="$(objdump -Cd "${KERNEL_PATH}")"

	while IFS= read -r line; do
		if [[ "${line}" =~ ^[[:xdigit:]]+[[:space:]]+\<(.+)\>\:$ ]]; then
			current_symbol="${BASH_REMATCH[1]}"
			continue
		fi

		if ! grep -Eiq "${SIMD_PATTERN}" <<<"${line}"; then
			continue
		fi

		if grep -Eiq "${APPROVED_STATE_PATTERN}" <<<"${line}"; then
			continue
		fi

		if [[ -n "${current_symbol}" ]] && grep -Eq "${APPROVED_MEMORY_SYMBOL_PATTERN}" <<<"${current_symbol}"; then
			continue
		fi

		failures+=("${current_symbol}: ${line}")
	done <<<"${disassembly}"

	if ((${#failures[@]} > 0)); then
		echo "FAIL ${KERNEL_PATH}: found SIMD/MMX/SSE instructions outside approved memory backends"
		printf '%s\n' "${failures[@]:0:20}"
		return 1
	fi

	echo "PASS ${KERNEL_PATH}: freestanding build limited SIMD usage to approved state-management instructions and owned memory backends"
}

run_case() {
	ensure_tools

	case "${CASE}" in
	default-freestanding-kernel-limits-approved-simd-state-instructions)
		assert_kernel_has_only_approved_simd "vga80x25"
		;;
	compact-freestanding-kernel-limits-approved-simd-state-instructions)
		assert_kernel_has_only_approved_simd "compact40x10"
		;;
	makefile-uses-non-simd-rust-target)
		assert_makefile_wiring
		echo "PASS Makefile: freestanding Rust target avoids the i686 SIMD ABI requirement"
		;;
	*)
		die "usage: $0 <arch> {default-freestanding-kernel-limits-approved-simd-state-instructions|compact-freestanding-kernel-limits-approved-simd-state-instructions|makefile-uses-non-simd-rust-target}"
		;;
	esac
}

run_host_case() {
	case "${CASE}" in
	makefile-uses-non-simd-rust-target)
		run_case
		return 0
		;;
	esac

	bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
		bash -lc "KFS_HOST_TEST_DIRECT=1 bash scripts/stability-tests/freestanding-simd.sh '${ARCH}' '${CASE}'"
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

	if [[ -n "${CASE}" ]] && describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
		run_host_case
		return 0
	fi

	run_case
}

main "$@"
