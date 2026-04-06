#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

declare -Ag ABI_REPR_TYPES=()
declare -a ABI_EXPORTS=()

list_cases() {
	cat <<'EOF'
cross-abi-forbid-reference-types
cross-abi-forbid-slices-or-str
cross-abi-forbid-tuples-without-repr
cross-abi-forbid-unrepr-user-types
cross-abi-forbid-trait-objects
cross-abi-forbid-generics
cross-abi-forbid-option-result
cross-abi-forbid-allocator-types
EOF
}

describe_case() {
	case "$1" in
	cross-abi-forbid-reference-types) printf '%s\n' "reject exported ABI signatures with Rust references" ;;
	cross-abi-forbid-slices-or-str) printf '%s\n' "reject exported ABI signatures with slices or str" ;;
	cross-abi-forbid-tuples-without-repr) printf '%s\n' "reject exported ABI signatures with tuple data forms" ;;
	cross-abi-forbid-unrepr-user-types) printf '%s\n' "reject exported ABI signatures with unrepr-ed user structs/enums" ;;
	cross-abi-forbid-trait-objects) printf '%s\n' "reject exported ABI signatures with trait objects" ;;
	cross-abi-forbid-generics) printf '%s\n' "reject exported ABI generic functions" ;;
	cross-abi-forbid-option-result) printf '%s\n' "reject Option and Result crossing ABI signatures" ;;
	cross-abi-forbid-allocator-types) printf '%s\n' "reject allocator-backed types crossing ABI signatures" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

collect_exported_abi_functions() {
	find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
		xargs -0 -r perl -ne '
        if (/^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)(\s*<[^>]+)?\s*\(([^)]*)\)\s*(?:->\s*([^;{]+))?\s*\{/) {
          my $name = $1;
          my $generics = $2 // "";
          my $params = $3 // "";
          my $ret = $4 // "";
          print "$ARGV:$.:|$name|$generics|$params|$ret\n";
        }' 2>/dev/null
}

collect_repr_types() {
	find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
		xargs -0 -r perl -ne '
        my $pending = 0;
        my $pending_allowed = 0;
        if (/^\s*#\[repr\(([^)]*)\)\]\s*(?:#\[.*\]\s*)*(?:pub\s+)?(?:unsafe\s+)?(struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)/) {
          my $repr = $1;
          if ($repr =~ /^\s*(C|transparent|u8|u16|u32|u64|i8|i16|i32|i64)\s*$/) {
            print "$3\n";
          }
          next;
        }
        if (/^\s*#\[repr\(([^)]*)\)\]\s*$/) {
          $pending = 1;
          my $repr = $1;
          $pending_allowed = ($repr =~ /^\s*(C|transparent|u8|u16|u32|u64|i8|i16|i32|i64)\s*$/);
          next;
        }
        if (/^\s*#\[/) {
          next;
        }
        if ($pending && /^\s*(?:pub\s+)?(?:unsafe\s+)?(?:struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)/) {
          print "$1\n" if $pending_allowed;
          $pending = 0;
          $pending_allowed = 0;
          next;
        }
        if (/^\S/) {
          $pending = 0;
          $pending_allowed = 0;
        }
      }' 2>/dev/null
}

load_metadata() {
	local type_item

	mapfile -t ABI_EXPORTS < <(collect_exported_abi_functions || true)
	if [[ "${#ABI_EXPORTS[@]}" -eq 0 ]]; then
		echo "FAIL ${CASE}: no exported extern \"C\" functions found"
		return 1
	fi

	ABI_REPR_TYPES=()
	while IFS= read -r type_item; do
		[[ -n "${type_item}" ]] || continue
		ABI_REPR_TYPES["${type_item}"]=1
	done < <(collect_repr_types || true)
}

assert_no_reference_types() {
	local file_line function_name generics params ret entry sig
	local offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		if [[ "${sig}" == *"&"* ]]; then
			offenders+=("${file_line} ${function_name} has reference type")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: references cross ABI boundary"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI signatures avoid references"
}

assert_no_slice_or_str_types() {
	local file_line function_name generics params ret entry sig offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		if grep -qE '\bstr\b' <<<"${sig}"; then
			offenders+=("${file_line} ${function_name} uses str")
			continue
		fi
		if grep -qE '\[[^\];]+\]' <<<"${sig}"; then
			offenders+=("${file_line} ${function_name} uses slice")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: slices or str cross ABI boundary"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI signatures avoid slices and str"
}

assert_no_tuple_data_without_repr() {
	local file_line function_name generics params ret entry sig offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		if grep -Eq '\([^)]*,\s*[^)]*\)' <<<"${params}"; then
			offenders+=("${file_line} ${function_name} uses tuple parameter")
			continue
		fi
		if grep -Eq '\([^)]*,\s*[^)]*\)' <<<"${ret}"; then
			offenders+=("${file_line} ${function_name} uses tuple return")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: tuple-form ABI data detected"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI signatures avoid tuple-form data"
}

assert_unrepr_user_types_not_exported() {
	local file_line function_name generics params ret entry sig
	local token type
	local -a offenders
	local -a seen

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		while IFS= read -r token; do
			[[ -n "${token}" ]] || continue
			case "${token}" in
			Self | Option | Result | Some | None | Ok | Err) continue ;;
			esac
			if [[ -n "${ABI_REPR_TYPES[${token}]:-}" ]]; then
				continue
			fi
			if grep -qE '^(Option|Result|Vec|String|Box|Rc|Arc|RefCell|Cell|VecDeque|HashMap|HashSet|BTreeMap|BTreeSet)$' <<<"${token}"; then
				continue
			fi
			offenders+=("${file_line} ${function_name} uses unrepr user type ${token}")
		done < <(printf '%s\n' "${sig}" | perl -ne 'while (/([A-Z][A-Za-z0-9_]*)/g) { print "$1\n"; }')
	done

	seen=()
	for type in "${offenders[@]}"; do
		[[ -n "${type}" ]] || continue
		seen+=("${type}")
	done
	offenders=("${seen[@]}")

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: unrepr user types cross ABI boundary"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI user types have explicit stable repr"
}

assert_no_trait_objects() {
	local file_line function_name generics params ret entry sig offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		if grep -qE '\bdyn[[:space:]]' <<<"${sig}"; then
			offenders+=("${file_line} ${function_name} uses trait object")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: trait objects cross ABI boundary"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI signatures avoid trait objects"
}

assert_no_generic_exports() {
	local file_line function_name generics params ret entry clean
	local -a offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		clean="${generics//[[:space:]]/}"
		if [[ -n "${clean}" ]]; then
			offenders+=("${file_line} ${function_name} is generic")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: generic exported ABI functions"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI functions are nongeneric"
}

assert_no_option_result() {
	local file_line function_name generics params ret entry sig
	local -a offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		if grep -Eq '(^|[^A-Za-z0-9_])([A-Za-z0-9_]+::)*(Option|Result)[[:space:]]*<' <<<"${sig}"; then
			offenders+=("${file_line} ${function_name} uses Option/Result")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: Option/Result cross ABI boundary"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI signatures avoid Option and Result"
}

assert_no_allocator_backed_types() {
	local file_line function_name generics params ret entry sig
	local -a offenders=()

	for entry in "${ABI_EXPORTS[@]}"; do
		IFS='|' read -r file_line function_name generics params ret <<<"${entry}"
		sig="${params}|${ret}"
		if grep -Eq '(^|[^A-Za-z0-9_])((alloc::[A-Za-z0-9_]+::)?)(Vec|String|VecDeque|Box|Rc|Arc|RefCell|Cell|HashMap|HashSet|BTreeMap|BTreeSet|Mutex|RwLock)[[:space:]]*<' <<<"${sig}"; then
			offenders+=("${file_line} ${function_name} uses allocator-backed type")
		fi
	done

	if [[ "${#offenders[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: allocator-backed types cross ABI boundary"
		printf '%s\n' "${offenders[@]}"
		return 1
	fi

	echo "PASS ${CASE}: exported ABI signatures avoid allocator-backed types"
}

run_case() {
	load_metadata || return 1

	case "${CASE}" in
	cross-abi-forbid-reference-types) assert_no_reference_types ;;
	cross-abi-forbid-slices-or-str) assert_no_slice_or_str_types ;;
	cross-abi-forbid-tuples-without-repr) assert_no_tuple_data_without_repr ;;
	cross-abi-forbid-unrepr-user-types) assert_unrepr_user_types_not_exported ;;
	cross-abi-forbid-trait-objects) assert_no_trait_objects ;;
	cross-abi-forbid-generics) assert_no_generic_exports ;;
	cross-abi-forbid-option-result) assert_no_option_result ;;
	cross-abi-forbid-allocator-types) assert_no_allocator_backed_types ;;
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
