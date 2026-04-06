#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

list_cases() {
	cat <<'EOF'
internal-extern-c-blocks-live-only-in-core-entry
services-and-nonentry-core-have-no-abi-markers
drivers-have-no-abi-markers
leaf-files-have-no-abi-markers
target-abi-facades-use-stable-low-level-signatures
EOF
}

describe_case() {
	case "$1" in
	internal-extern-c-blocks-live-only-in-core-entry) printf '%s\n' "ABI markers only live in approved kernel ABI boundaries" ;;
	services-and-nonentry-core-have-no-abi-markers) printf '%s\n' "services and non-entry core files have no ABI markers" ;;
	drivers-have-no-abi-markers) printf '%s\n' "drivers have no ABI markers in the target architecture" ;;
	leaf-files-have-no-abi-markers) printf '%s\n' "leaf files have no ABI markers" ;;
	target-abi-facades-use-stable-low-level-signatures) printf '%s\n' "target ABI facades use only stable low-level data forms" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_internal_extern_blocks_only_in_core_entry() {
	local offenders
	local roots=()
	local disallowed

	[[ -d "${REPO_ROOT}/src/kernel" ]] && roots+=("${REPO_ROOT}/src/kernel")
	[[ -d "${REPO_ROOT}/src/arch" ]] && roots+=("${REPO_ROOT}/src/arch")

	if [[ "${#roots[@]}" -gt 0 ]]; then
		offenders="$(rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S "${roots[@]}" || true)"
	fi

	disallowed="$(printf '%s\n' "${offenders}" | grep -vE '^.*/src/kernel/core/entry\.rs:|^.*/src/kernel/klib/(string|memory)/mod\.rs:|^.*/src/arch/.+/.+\.rs:' || true)"
	if [[ -n "${disallowed}" ]]; then
		echo "FAIL ${CASE}: found ABI marker outside approved boundaries"
		printf '%s\n' "${disallowed}"
		return 1
	fi
	echo "PASS ${CASE}: ABI markers are restricted to approved boundaries"
}

assert_no_abi_markers_in_paths() {
	local label="$1"
	shift
	local roots=("$@")
	local offenders

	[[ "${#roots[@]}" -gt 0 ]] || {
		echo "PASS ${CASE}: no ${label} paths exist yet"
		return 0
	}

	offenders="$(rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S "${roots[@]}" || true)"
	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found ABI markers in ${label}"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: ${label} have no ABI markers"
}

assert_services_and_nonentry_core_no_abi() {
	local roots=()
	[[ -d "${REPO_ROOT}/src/kernel/services" ]] && roots+=("${REPO_ROOT}/src/kernel/services")
	[[ -d "${REPO_ROOT}/src/kernel/core" ]] && roots+=("${REPO_ROOT}/src/kernel/core")
	if [[ -f "${REPO_ROOT}/src/kernel/core/entry.rs" ]]; then
		# Search then subtract the allowed entry file.
		local offenders
		offenders="$(
			rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S "${roots[@]}" 2>/dev/null |
				grep -vE '^.*/src/kernel/core/entry\.rs:' || true
		)"
		if [[ -n "${offenders}" ]]; then
			echo "FAIL ${CASE}: found ABI markers in services or non-entry core"
			printf '%s\n' "${offenders}"
			return 1
		fi
		echo "PASS ${CASE}: services and non-entry core have no ABI markers"
		return 0
	fi

	assert_no_abi_markers_in_paths "services and non-entry core" "${roots[@]}"
}

assert_drivers_no_abi() {
	local roots=()
	[[ -d "${REPO_ROOT}/src/kernel/drivers" ]] && roots+=("${REPO_ROOT}/src/kernel/drivers")
	assert_no_abi_markers_in_paths "drivers" "${roots[@]}"
}

assert_leaves_no_abi() {
	local offenders
	offenders="$(
		find "${REPO_ROOT}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' -o -name '*_impl.rs' -o -name 'logic_impl.rs' -o -name 'sse2_*.rs' \) -print0 |
			xargs -0 rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S 2>/dev/null || true
	)"
	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: found ABI markers in leaf files"
		printf '%s\n' "${offenders}"
		return 1
	fi
	echo "PASS ${CASE}: leaf files have no ABI markers"
}

assert_target_abi_facade_signatures() {
	local files=(
		"${REPO_ROOT}/src/kernel/core/entry.rs"
		"${REPO_ROOT}/src/kernel/klib/string/mod.rs"
		"${REPO_ROOT}/src/kernel/klib/memory/mod.rs"
	)
	local missing=()
	local file
	for file in "${files[@]}"; do
		[[ -f "${file}" ]] || missing+=("${file#${REPO_ROOT}/}")
	done
	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: missing target ABI facade files"
		printf '%s\n' "${missing[@]}"
		return 1
	fi

	if rg -n 'pub[[:space:]]+.*extern[[:space:]]+"C"[[:space:]]+fn.*(&[^,)]*|\[[^]]*\]|str\b|Option<|Result<|dyn[[:space:]]|Vec<|String\b|impl[[:space:]])' -S "${files[@]}" >/dev/null; then
		echo "FAIL ${CASE}: found forbidden ABI data form in target facade signature"
		rg -n 'pub[[:space:]]+.*extern[[:space:]]+"C"[[:space:]]+fn.*(&[^,)]*|\[[^]]*\]|str\b|Option<|Result<|dyn[[:space:]]|Vec<|String\b|impl[[:space:]])' -S "${files[@]}" || true
		return 1
	fi

	echo "PASS ${CASE}: target ABI facades use stable low-level signatures"
}

run_case() {
	case "${CASE}" in
	internal-extern-c-blocks-live-only-in-core-entry) assert_internal_extern_blocks_only_in_core_entry ;;
	services-and-nonentry-core-have-no-abi-markers) assert_services_and_nonentry_core_no_abi ;;
	drivers-have-no-abi-markers) assert_drivers_no_abi ;;
	leaf-files-have-no-abi-markers) assert_leaves_no_abi ;;
	target-abi-facades-use-stable-low-level-signatures) assert_target_abi_facade_signatures ;;
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
