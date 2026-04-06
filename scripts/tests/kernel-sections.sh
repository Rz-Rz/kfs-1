#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SINGLE_KERNEL="${KFS_M3_2_KERNEL:-}"

list_cases() {
	cat <<'EOF'
release-iso-bootable
release-img-bootable
release-iso-is-within-10mb
release-img-is-within-10mb
linker-script-defines-rodata-section
linker-script-defines-data-section
linker-script-defines-bss-section
release-kernel-contains-text-section
release-kernel-contains-rodata-section
release-kernel-contains-data-section
release-kernel-contains-bss-section
release-rodata-marker
release-data-marker
release-bss-marker
release-bss-is-nobits
EOF
}

describe_case() {
	case "$1" in
	release-iso-bootable) printf '%s\n' "release ISO is bootable" ;;
	release-img-bootable) printf '%s\n' "release IMG is bootable" ;;
	release-iso-is-within-10mb) printf '%s\n' "release ISO stays within the 10 MB upper bound" ;;
	release-img-is-within-10mb) printf '%s\n' "release IMG stays within the 10 MB upper bound" ;;
	linker-script-defines-rodata-section) printf '%s\n' "linker script defines .rodata" ;;
	linker-script-defines-data-section) printf '%s\n' "linker script defines .data" ;;
	linker-script-defines-bss-section) printf '%s\n' "linker script defines .bss" ;;
	release-kernel-contains-text-section) printf '%s\n' "release kernel contains .text" ;;
	release-kernel-contains-rodata-section) printf '%s\n' "release kernel contains .rodata" ;;
	release-kernel-contains-data-section) printf '%s\n' "release kernel contains .data" ;;
	release-kernel-contains-bss-section) printf '%s\n' "release kernel contains .bss" ;;
	release-rodata-marker) printf '%s\n' "release rodata marker lands in .rodata" ;;
	release-data-marker) printf '%s\n' "release data marker lands in .data" ;;
	release-bss-marker) printf '%s\n' "release bss marker lands in .bss" ;;
	release-bss-is-nobits) printf '%s\n' "release .bss is emitted as NOBITS" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

verify_required_kernel_layout() {
	local kernel="$1"
	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

	local missing=0
	local expected_type

	for section in .text .rodata .data .bss; do
		expected_type='PROGBITS'
		if [[ "${section}" == ".bss" ]]; then
			expected_type='NOBITS'
		fi

		if ! readelf -SW "${kernel}" | grep -qE "[[:space:]]${section}[[:space:]]"; then
			echo "FAIL ${kernel}: missing section ${section}"
			missing=1
		elif ! readelf -SW "${kernel}" | grep -qE "[[:space:]]${section}[[:space:]].*[[:space:]]${expected_type}[[:space:]]"; then
			echo "FAIL ${kernel}: ${section} exists but is not ${expected_type}"
			missing=1
		fi
	done

	if ! nm -n "${kernel}" | grep -qE '[[:space:]]R[[:space:]]+KFS_RODATA_MARKER$'; then
		echo "FAIL ${kernel}: expected read-only marker missing or not in rodata (nm type R): KFS_RODATA_MARKER"
		missing=1
	fi

	if ! nm -n "${kernel}" | grep -qE '[[:space:]]D[[:space:]]+KFS_DATA_MARKER$'; then
		echo "FAIL ${kernel}: expected writable marker missing or not in data (nm type D): KFS_DATA_MARKER"
		missing=1
	fi

	if ! nm -n "${kernel}" | grep -qE '[[:space:]][Bb][[:space:]]+KFS_BSS_MARKER$'; then
		echo "FAIL ${kernel}: expected zero-initialized marker missing or not in bss (nm type B/b): KFS_BSS_MARKER"
		missing=1
	fi

	if [[ "${missing}" -ne 0 ]]; then
		echo "hint: Feature M3.2 expects linker output sections (.text/.rodata/.data/.bss) and the Rust canary symbols from src/freestanding/section_markers.rs"
		return 1
	fi

	echo "PASS ${kernel}"
	return 0
}

run_host_case() {
	case "${CASE}" in
	release-iso-bootable)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B iso arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.iso && test \$(wc -c < build/os-${ARCH}.iso) -le 10485760 && file build/os-${ARCH}.iso | grep -q 'ISO 9660'"
		;;
	release-img-bootable)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B img arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.img && test \$(wc -c < build/os-${ARCH}.img) -le 10485760 && file build/os-${ARCH}.img | grep -q 'ISO 9660' && cmp -s build/os-${ARCH}.iso build/os-${ARCH}.img"
		;;
	release-iso-is-within-10mb)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B iso arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.iso && test \$(wc -c < build/os-${ARCH}.iso) -le 10485760"
		;;
	release-img-is-within-10mb)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B img arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.img && test \$(wc -c < build/os-${ARCH}.img) -le 10485760"
		;;
	linker-script-defines-rodata-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "grep -nE '^\\s*\\.rodata\\b' src/arch/${ARCH}/linker.ld >/dev/null"
		;;
	linker-script-defines-data-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "grep -nE '^\\s*\\.data\\b' src/arch/${ARCH}/linker.ld >/dev/null"
		;;
	linker-script-defines-bss-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "grep -nE '^\\s*\\.bss\\b' src/arch/${ARCH}/linker.ld >/dev/null"
		;;
	release-kernel-contains-text-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && readelf -SW 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]\\.text[[:space:]]'"
		;;
	release-kernel-contains-rodata-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && readelf -SW 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]\\.rodata[[:space:]]'"
		;;
	release-kernel-contains-data-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && readelf -SW 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]\\.data[[:space:]]'"
		;;
	release-kernel-contains-bss-section)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && readelf -SW 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]\\.bss[[:space:]]'"
		;;
	release-rodata-marker)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]R[[:space:]]+KFS_RODATA_MARKER$'"
		;;
	release-data-marker)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]D[[:space:]]+KFS_DATA_MARKER$'"
		;;
	release-bss-marker)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]][Bb][[:space:]]+KFS_BSS_MARKER$'"
		;;
	release-bss-is-nobits)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null && readelf -SW 'build/kernel-${ARCH}.bin' | grep -qE '\\.bss\\b.*NOBITS'"
		;;
	*)
		return 1
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

	if [[ -n "${CASE}" ]] && describe_case "${CASE}" >/dev/null 2>&1; then
		run_host_case
		return 0
	fi

	if [[ -n "${SINGLE_KERNEL}" ]]; then
		verify_required_kernel_layout "${SINGLE_KERNEL}"
		return 0
	fi

	local failures=0

	[[ -r "build/kernel-${ARCH}-test.bin" ]] || die "missing test kernel: build/kernel-${ARCH}-test.bin (build it with make iso-test arch=${ARCH})"
	verify_required_kernel_layout "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))

	if [[ "${KFS_M3_2_INCLUDE_RELEASE:-0}" == "1" ]]; then
		[[ -r "build/kernel-${ARCH}.bin" ]] || die "missing release kernel: build/kernel-${ARCH}.bin (build it with make all arch=${ARCH})"
		verify_required_kernel_layout "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
	fi

	if [[ "${failures}" -ne 0 ]]; then
		exit 1
	fi
}

main "$@"
