#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

declare -A EXPECTED_EXPORT_OWNER
EXPECTED_EXPORT_OWNER=(
	[kmain]="src/kernel/core/entry.rs"
	[kfs_strlen]="src/kernel/klib/string/mod.rs"
	[kfs_strcmp]="src/kernel/klib/string/mod.rs"
	[kfs_memcpy]="src/kernel/klib/memory/mod.rs"
	[kfs_memset]="src/kernel/klib/memory/mod.rs"
)

EXPECTED_EXPORT_SYMBOLS=(kmain kfs_strlen kfs_strcmp kfs_memcpy kfs_memset)

list_cases() {
	cat <<'EOF'
export-ownership-by-source-owner
export-ownership-artifact-traceability
EOF
}

describe_case() {
	case "$1" in
	export-ownership-by-source-owner)
		printf '%s\n' "export ownership is enforced on source declarations"
		;;
	export-ownership-artifact-traceability)
		printf '%s\n' "artifact-level exports are traceable to expected source owners"
		;;
	*)
		return 1
		;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

is_disallowed_export_file() {
	local path="$1"

	case "${path}" in
	src/kernel/types/*)
		return 0
		;;
	src/kernel/services/*)
		return 0
		;;
	src/kernel/drivers/*)
		return 0
		;;
	src/kernel/core/*)
		[[ "${path}" == "src/kernel/core/entry.rs" ]] && return 1
		return 0
		;;
	esac

	case "${path##*/}" in
	imp.rs | writer.rs | logic_impl.rs | string_impl.rs | memory_impl.rs | sse2_memcpy.rs | sse2_memset.rs | *_impl.rs)
		return 0
		;;
	esac

	return 1
}

extract_no_mangle_exports() {
	local file="$1"

	awk '
    BEGIN { pending = 0 }
    {
      gsub(/\r/, "", $0)
      line = $0

      if (line ~ /^[[:space:]]*#\[no_mangle\][[:space:]]*$/) {
        pending = 1
        next
      }

      if (match(line, /^[[:space:]]*#\[no_mangle\].*(fn|const|static)[[:space:]]+(mut[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)/, name)) {
        print name[3]
        pending = 0
        next
      }

      if (pending == 1) {
        if (match(line, /^[[:space:]]*pub[[:space:]]+(unsafe[[:space:]]+)?(extern[[:space:]]+"C"[[:space:]]+)?(fn|const|static)[[:space:]]+(mut[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)/, name)) {
          print name[5]
        }
        pending = 0
      }
    }
  ' "$file"
}

collect_source_exports() {
	local file
	local root="${REPO_ROOT}"

	if [[ ! -d "${root}/src/kernel" ]]; then
		return 0
	fi

	find "${root}/src/kernel" -type f -name '*.rs' -print0 |
		while IFS= read -r -d '' file; do
			while IFS= read -r symbol; do
				[[ -n "${symbol}" ]] || continue
				printf '%s\t%s\n' "${symbol}" "${file#${root}/}"
			done < <(extract_no_mangle_exports "${file}")
		done
}

collect_binary_exports() {
	local kernel="${REPO_ROOT}/build/kernel-${ARCH}.bin"
	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make test-artifacts arch=${ARCH})"
	nm -g --defined-only "${kernel}" | awk '{print $3}' | sed '/^$/d' | LC_ALL=C sort -u
}

assert_export_ownership_by_source() {
	local symbol file owner
	local -A actual_owner
	local -a errors=()
	local sym

	while IFS=$'\t' read -r symbol file; do
		[[ -z "${symbol}" ]] && continue
		if [[ -n "${actual_owner[${symbol}]:-}" && "${actual_owner[${symbol}]}" != "${file}" ]]; then
			errors+=("${symbol} exported from multiple files: ${actual_owner[${symbol}]}, ${file}")
			continue
		fi
		actual_owner["${symbol}"]="${file}"
	done < <(collect_source_exports)

	for sym in "${EXPECTED_EXPORT_SYMBOLS[@]}"; do
		owner="${EXPECTED_EXPORT_OWNER[${sym}]}"
		if [[ ! -f "${REPO_ROOT}/${owner}" ]]; then
			errors+=("missing expected owning file for ${sym}: ${owner}")
			continue
		fi
		if [[ -z "${actual_owner[${sym}]:-}" ]]; then
			errors+=("missing required exported symbol declaration: ${sym}")
			continue
		fi
		if [[ "${actual_owner[${sym}]}" != "${owner}" ]]; then
			errors+=("${sym} owned by ${actual_owner[${sym}]} instead of ${owner}")
			continue
		fi
	done

	for sym in "${!actual_owner[@]}"; do
		file="${actual_owner[${sym}]}"
		if [[ -z "${EXPECTED_EXPORT_OWNER[${sym}]:-}" ]]; then
			errors+=("unexpected exported symbol ${sym} from ${file}")
			continue
		fi
		if is_disallowed_export_file "${file}"; then
			errors+=("disallowed export ${sym} in ${file}")
		fi
	done

	if [[ ${#errors[@]} -gt 0 ]]; then
		echo "FAIL ${CASE}: export ownership violations"
		printf '%s\n' "${errors[@]}"
		return 1
	fi

	echo "PASS ${CASE}: export ownership declared from correct owners"
}

assert_artifact_traceability_for_owned_exports() {
	local binary_exports symbol
	local -a errors=()
	declare -A actual_owner

	while IFS=$'\t' read -r symbol file; do
		[[ -z "${symbol}" ]] && continue
		actual_owner["${symbol}"]="${file}"
	done < <(collect_source_exports)

	binary_exports="$(collect_binary_exports)"

	for symbol in "${EXPECTED_EXPORT_SYMBOLS[@]}"; do
		local source_owner="${actual_owner[${symbol}]:-}"
		local expected_owner="${EXPECTED_EXPORT_OWNER[${symbol}]}"
		if [[ -z "${source_owner}" ]]; then
			errors+=("missing source owner declaration for ${symbol}")
			continue
		fi
		if [[ "${source_owner}" != "${expected_owner}" ]]; then
			errors+=("${symbol} source owner mismatch in artifact trace: ${source_owner} != ${expected_owner}")
			continue
		fi
		if ! grep -qxF "${symbol}" <<<"${binary_exports}"; then
			errors+=("${symbol} not present in build exports")
			continue
		fi
	done

	if [[ ${#errors[@]} -gt 0 ]]; then
		echo "FAIL ${CASE}: artifact export ownership traceability failed"
		printf '%s\n' "${errors[@]}"
		return 1
	fi

	echo "PASS ${CASE}: artifact export ownership traceability passed"
}

run_case() {
	case "${CASE}" in
	export-ownership-by-source-owner)
		assert_export_ownership_by_source
		;;
	export-ownership-artifact-traceability)
		assert_artifact_traceability_for_owned_exports
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
