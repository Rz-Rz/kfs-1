#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-core-init-uses-services-console}"
KERNEL="build/kernel-${ARCH}.bin"
DRIVER_SOURCE="src/kernel/drivers/vga_text/mod.rs"
WRITER_SOURCE="src/kernel/drivers/vga_text/writer.rs"
CONSOLE_SOURCE="src/kernel/services/console.rs"
INIT_SOURCE="src/kernel/core/init.rs"

list_cases() {
	cat <<'EOF'
release-kernel-omits-vga-abi-exports
driver-vga-writer-exists
services-console-uses-driver
core-init-uses-services-console
EOF
}

describe_case() {
	case "$1" in
	release-kernel-omits-vga-abi-exports) printf '%s\n' "release kernel does not export removed VGA ABI symbols" ;;
	driver-vga-writer-exists) printf '%s\n' "driver VGA writer files exist and define writer helpers" ;;
	services-console-uses-driver) printf '%s\n' "services console uses the VGA driver facade" ;;
	core-init-uses-services-console) printf '%s\n' "core init uses services console instead of driver ABI" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_source_pattern() {
	local pattern="$1"
	local description="$2"
	local file="$3"

	[[ -r "${file}" ]] || die "missing source file: ${file}"

	if command -v rg >/dev/null 2>&1; then
		if ! rg -n "${pattern}" -S "${file}" >/dev/null; then
			echo "FAIL ${file}: missing ${description}"
			return 1
		fi
	else
		if ! grep -En "${pattern}" "${file}" >/dev/null; then
			echo "FAIL ${file}: missing ${description}"
			return 1
		fi
	fi
}

assert_release_symbol() {
	local symbol="$1"

	[[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"

	if ! nm -n "${KERNEL}" | grep -qE "[[:space:]]T[[:space:]]+${symbol}$"; then
		echo "FAIL ${KERNEL}: missing symbol ${symbol}"
		return 1
	fi
}

run_direct_case() {
	case "${CASE}" in
	release-kernel-omits-vga-abi-exports)
		[[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"
		if nm -n "${KERNEL}" | grep -qE '[[:space:]]T[[:space:]]+vga_(init|putc|puts)$'; then
			echo "FAIL ${KERNEL}: removed VGA ABI export still present"
			return 1
		fi
		;;
	driver-vga-writer-exists)
		assert_source_pattern '\bfn[[:space:]]+write_bytes\b' 'driver write_bytes helper' "${WRITER_SOURCE}"
		assert_source_pattern '\bfn[[:space:]]+vga_text_cell\b' 'driver cell encoding helper' "${DRIVER_SOURCE}"
		;;
	services-console-uses-driver)
		assert_source_pattern '\bdrivers::vga_text\b' 'services console driver import' "${CONSOLE_SOURCE}"
		;;
	core-init-uses-services-console)
		assert_source_pattern '\bservices::console\b' 'core init console call' "${INIT_SOURCE}"
		;;
	*)
		die "unknown case: ${CASE}"
		;;
	esac
}

run_host_case() {
	bash scripts/with-build-lock.sh \
		bash scripts/container.sh run -- \
		bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/vga-writer.sh '${ARCH}' '${CASE}'"
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
	[[ -r "${DRIVER_SOURCE}" ]] || die "missing VGA driver source: ${DRIVER_SOURCE}"

	if describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
		run_host_case
		return 0
	fi

	run_direct_case
}

main "$@"
