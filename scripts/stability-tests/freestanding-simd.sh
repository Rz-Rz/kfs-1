#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
MAKEFILE_SOURCE="Makefile"
KERNEL_PATH="build/kernel-${ARCH}.bin"
SSE_PATTERN='xmm[0-9]+|ymm[0-9]+|zmm[0-9]+|(^|[^[:alnum:]_])(xorps|movaps|movups|movdqa|movdqu|pxor|xorpd|movapd|movupd)([^[:alnum:]_]|$)'

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
default-freestanding-kernel-disables-simd-instructions
compact-freestanding-kernel-disables-simd-instructions
makefile-disables-simd-target-features
EOF
}

describe_case() {
	case "$1" in
	default-freestanding-kernel-disables-simd-instructions) printf '%s\n' "default freestanding kernel object code stays free of SIMD register and SSE instruction usage" ;;
	compact-freestanding-kernel-disables-simd-instructions) printf '%s\n' "compact freestanding kernel object code stays free of SIMD register and SSE instruction usage" ;;
	makefile-disables-simd-target-features) printf '%s\n' "Makefile disables SIMD target features for freestanding rustc builds" ;;
	*) return 1 ;;
	esac
}

ensure_tools() {
	command -v objdump >/dev/null 2>&1 || die "missing required tool: objdump"
	command -v rg >/dev/null 2>&1 || die "missing required tool: rg"
}

assert_makefile_wiring() {
	rg -n 'rust_target[[:space:]]*:=[[:space:]]*i686-unknown-linux-gnu' "${MAKEFILE_SOURCE}" >/dev/null ||
		die "Makefile does not define the freestanding Rust target"
	rg -n 'RUST_CODEGEN_FLAGS[[:space:]]*:=[[:space:]]*-C target-feature=-sse,-sse2' "${MAKEFILE_SOURCE}" >/dev/null ||
		die "Makefile does not disable freestanding SIMD codegen"
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

assert_kernel_has_no_simd() {
	local preset="$1"
	local disassembly

	build_kernel "${preset}"
	disassembly="$(objdump -d "${KERNEL_PATH}")"
	if grep -Eiq "${SSE_PATTERN}" <<<"${disassembly}"; then
		echo "FAIL ${KERNEL_PATH}: found SIMD/SSE instructions in freestanding build"
		grep -Ein "${SSE_PATTERN}" <<<"${disassembly}" | head -n 20
		return 1
	fi

	echo "PASS ${KERNEL_PATH}: freestanding build stayed free of SIMD/SSE instructions"
}

run_case() {
	ensure_tools

	case "${CASE}" in
	default-freestanding-kernel-disables-simd-instructions)
		assert_kernel_has_no_simd "vga80x25"
		;;
	compact-freestanding-kernel-disables-simd-instructions)
		assert_kernel_has_no_simd "compact40x10"
		;;
	makefile-disables-simd-target-features)
		assert_makefile_wiring
		echo "PASS Makefile: freestanding SIMD disabling flags are present"
		;;
	*)
		die "usage: $0 <arch> {default-freestanding-kernel-disables-simd-instructions|compact-freestanding-kernel-disables-simd-instructions|makefile-disables-simd-target-features}"
		;;
	esac
}

run_host_case() {
	case "${CASE}" in
	makefile-disables-simd-target-features)
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
