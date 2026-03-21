#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

POSITIVE_CASE_SCRIPTS=(
  "scripts/architecture-tests/kernel-architecture.sh"
  "scripts/architecture-tests/file-roles.sh"
  "scripts/architecture-tests/layer-dependencies.sh"
  "scripts/architecture-tests/layer-contracts.sh"
  "scripts/architecture-tests/abi-contracts.sh"
  "scripts/architecture-tests/abi-data-contracts.sh"
  "scripts/architecture-tests/export-ownership.sh"
  "scripts/architecture-tests/runtime-ownership.sh"
  "scripts/architecture-tests/build-graph.sh"
  "scripts/architecture-tests/tree-migration.sh"
  "scripts/architecture-tests/type-contracts.sh"
  "scripts/tests/unit/type-architecture.sh"
)

NEGATIVE_CASE_SCRIPTS=(
  "scripts/rejection-tests/architecture-rejections.sh"
  "scripts/rejection-tests/architecture-abi-rejections.sh"
  "scripts/rejection-tests/architecture-layer-rejections.sh"
  "scripts/rejection-tests/file-role-rejections.sh"
  "scripts/rejection-tests/layer-dependency-rejections.sh"
  "scripts/rejection-tests/export-ownership-rejections.sh"
  "scripts/rejection-tests/runtime-ownership-rejections.sh"
  "scripts/rejection-tests/build-graph-rejections.sh"
  "scripts/rejection-tests/tree-migration-rejections.sh"
  "scripts/rejection-tests/type-architecture-rejections.sh"
  "scripts/rejection-tests/abi-data-contract-rejections.sh"
)

list_cases() {
  cat <<'EOF'
rejection-invariant-coverage-matrix
EOF
}

describe_case() {
  case "$1" in
    rejection-invariant-coverage-matrix)
      printf '%s\n' "checks that every architecture invariant has both positive and rejection coverage"
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

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

collect_cases() {
  local -a scripts=("$@")
  local script
  local case_id

  for script in "${scripts[@]}"; do
    [[ -r "${script}" ]] || {
      echo "FAIL ${CASE}: script missing: ${script}" >&2
      return 1
    }

    while IFS= read -r case_id; do
      [[ -z "${case_id}" ]] && continue
      printf '%s::%s\n' "${script}" "${case_id}"
    done < <(bash "${script}" --list)
  done
}

match_any_pattern() {
  local value="$1"
  local patterns="$2"
  local pattern

  while IFS= read -r pattern; do
    [[ -z "${pattern}" ]] && continue
    if [[ "${value}" == "${pattern}" ]]; then
      return 0
    fi
  done <<<"${patterns}"
  return 1
}

collect_matching_cases() {
  local patterns="$1"
  local source_lines="$2"
  local line case_id
  local -A seen
  local -a output

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    case_id="${line##*::}"
    if match_any_pattern "${case_id}" "${patterns}"; then
      if [[ -z "${seen[${line}]:-}" ]]; then
        seen["${line}"]=1
        output+=("${line}")
      fi
    fi
  done <<<"${source_lines}"

  printf '%s\n' "${output[@]}"
}

emit_case_array_json() {
  local input="$1"
  local first=1
  local line

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    if (( first == 0 )); then
      printf ', '
    fi
    printf '\"%s\"' "$(json_escape "${line}")"
    first=0
  done <<<"${input}"
}

run_coverage_matrix() {
  local positive_cases
  local negative_cases
  local invariant_count=0
  local covered_count=0
  local -a missing=()
  local invariant_id
  local -a names
  local pos_patterns
  local neg_patterns
  local pos_matches
  local neg_matches
  local pos_count
  local neg_count

  positive_cases="$(collect_cases "${POSITIVE_CASE_SCRIPTS[@]}")"
  negative_cases="$(collect_cases "${NEGATIVE_CASE_SCRIPTS[@]}")"

  declare -A INVARIANT_TITLES=(
    [tree-migration]="Tree migration and path cleanup"
    [file-roles]="Kernel file roles and facade boundaries"
    [layer-dependencies]="Layer dependency direction and ownership"
    [layer-contracts]="Layer contracts and raw hardware policy"
    [abi-markers]="ABI marker ownership and allowed boundaries"
    [abi-contracts]="Cross-ABI data type restrictions"
    [export-ownership]="ABI symbol ownership by owning layer/file"
    [runtime-path]="Runtime ownership handoff path"
    [build-graph]="Kernel build graph is single-rooted"
    [type-contracts]="Required façade types and repr ownership"
  )

  declare -A POSITIVE_PATTERNS=(
    [tree-migration]=$'target-tree-has-kernel-root
required-architecture-artifacts-exist
kernel-first-level-dirs-match-allowlist
no-top-level-kernel-peer-files
types-layer-contains-only-current-files
future-architecture-tree-artifacts-exist'
    [file-roles]=$'crate-root-is-lone-top-level-rs
kernel-top-level-directories-are-layers-only
kernel-files-have-recognized-roles
layer-roots-are-mod-rs
subsystem-facade-shapes-are-valid
private-leaves-are-owned-and-located
private-leaf-imports-are-local'
    [layer-dependencies]=$'core-depends-only-on-services-types-klib
services-do-not-import-driver-leaves-or-raw-hw
drivers-do-not-own-boot-policy
klib-does-not-depend-on-device-code
types-do-not-depend-on-io-or-policy
machine-stays-primitive-only'
    [layer-contracts]=$'layer-roots-exist-as-mod-rs
boot-start-hands-off-only-to-kmain
core-init-surface-exists
console-runtime-path-files-exist
core-init-avoids-raw-hw-and-asm
services-avoid-raw-hw-and-asm
inline-asm-stays-in-arch-or-machine
types-have-no-side-effects'
    [abi-markers]=$'internal-extern-c-blocks-live-only-in-core-entry
services-and-nonentry-core-have-no-abi-markers
drivers-have-no-abi-markers
leaf-files-have-no-abi-markers
target-abi-facades-use-stable-low-level-signatures'
    [abi-contracts]=$'cross-abi-forbid-reference-types
cross-abi-forbid-slices-or-str
cross-abi-forbid-tuples-without-repr
cross-abi-forbid-unrepr-user-types
cross-abi-forbid-trait-objects
cross-abi-forbid-generics
cross-abi-forbid-option-result
cross-abi-forbid-allocator-types'
    [export-ownership]=$'export-ownership-by-source-owner
export-ownership-artifact-traceability'
    [runtime-path]=$'runtime-path-artifacts-exist
boot-start-hand-off-only-to-kmain
start-not-direct-to-driver-or-helper
entry-calls-core-init-sequence
core-init-calls-services-console
services-console-calls-driver-facade
entry-no-direct-driver-abi-calls'
    [build-graph]=$'kernel-rust-root-is-single-entry
makefile-does-not-glob-src-kernel-peers
build-produces-single-kernel-rust-unit
no-kernel-subsystem-rust-objects'
    [type-contracts]=$'future-port-owner-and-repr
future-kernel-range-owner-and-repr
future-screen-types-owner-and-repr
helper-boundary-files-exist
helper-abi-uses-primitive-core-types
serial-path-uses-port-type
layout-path-uses-kernel-range-type
helper-wrappers-use-extern-c-and-no-mangle
no-alias-only-primitive-layer
kernel-helper-code-avoids-std
helper-private-impl-not-imported-directly
port-uses-repr-transparent
kernel-range-uses-repr-c
screen-types-exist
color-code-uses-repr-transparent
screen-cell-uses-repr-c
cursor-pos-uses-repr-c'
  )

  declare -A NEGATIVE_PATTERNS=(
    [tree-migration]=$'missing-required-tree-artifact-fails
new-top-level-kernel-peer-file-fails
disallowed-first-level-layer-fails'
    [file-roles]=$'top-level-peer-file-fails
orphan-leaf-location-fails
cross-facade-leaf-import-fails
unknown-role-file-fails'
    [layer-dependencies]=$'core-imports-machine-fails
services-import-driver-leaf-fails
drivers-own-boot-policy-fails
klib-depends-on-device-code-fails
types-depend-on-policy-fails
machine-depends-on-drivers-fails'
    [layer-contracts]=$'layer-root-modrs-missing-fails
boot-calls-driver-directly-fails
core-inline-asm-fails
services-raw-hardware-fails
types-side-effect-fails'
    [abi-markers]=$'extern-block-outside-core-entry-fails
services-abi-marker-fails
driver-abi-marker-fails
leaf-abi-marker-fails
allowed-toolchain-boundary-marker-pass
forbidden-abi-signature-form-fails'
    [abi-contracts]=$'abi-export-reference-types-fails
abi-export-slice-or-str-fails
abi-export-tuple-fails
abi-export-unrepr-user-type-fails
abi-export-trait-object-fails
abi-export-generic-fn-fails
abi-export-option-result-fails
abi-export-allocator-type-fails'
    [export-ownership]=$'drivers-export-ownership-fails
services-export-ownership-fails
leaf-export-ownership-fails
types-export-ownership-fails
core-nonentry-export-ownership-fails'
    [runtime-path]=$'boot-calls-driver-directly-fails
entry-skips-core-init-fails
kmain-calls-vga-directly-fails
core-init-skips-services-fails
services-console-skips-driver-facade-fails'
    [build-graph]=$'kernel-sources-glob-fails
kernel-entrypoint-not-root-fails
kernel-sources-not-single-fails
kernel-subsystem-objects-fail
per-file-kernel-build-fails'
    [type-contracts]=$'std-in-helper-layer-fails
alias-only-primitive-layer-fails
port-missing-repr-transparent-fails
kernel-range-missing-repr-c-fails
port-owner-path-fails
kernel-range-owner-path-fails
screen-types-owner-path-fails
screen-types-missing-fail
color-code-missing-repr-transparent-fails
screen-cell-missing-repr-c-fails
cursor-pos-missing-repr-c-fails
helper-wrapper-missing-extern-c-fails
private-helper-import-fails'
  )

  names=(tree-migration file-roles layer-dependencies layer-contracts abi-markers abi-contracts export-ownership runtime-path build-graph type-contracts)

  printf '{\n'
  printf '  \"arch\": \"%s\",\n' "$(json_escape "${ARCH}")"
  printf '  \"total_invariants\": %d,\n' "${#names[@]}"
  printf '  \"invariants\": [\n'

  for invariant_id in "${names[@]}"; do
    ((invariant_count += 1))

    pos_patterns="${POSITIVE_PATTERNS[${invariant_id}]}"
    neg_patterns="${NEGATIVE_PATTERNS[${invariant_id}]}"
    pos_matches="$(collect_matching_cases "${pos_patterns}" "${positive_cases}")"
    neg_matches="$(collect_matching_cases "${neg_patterns}" "${negative_cases}")"

    pos_count="$(printf '%s\n' "${pos_matches}" | wc -l | tr -d ' ')"
    neg_count="$(printf '%s\n' "${neg_matches}" | wc -l | tr -d ' ')"

    if [[ "${pos_matches}" == "" ]]; then
      pos_count=0
    fi
    if [[ "${neg_matches}" == "" ]]; then
      neg_count=0
    fi

    if (( pos_count == 0 || neg_count == 0 )); then
      missing+=("${invariant_id}")
      echo "FAIL ${CASE}: invariant '${invariant_id}' missing coverage (positive=${pos_count}, rejection=${neg_count})" >&2
    else
      covered_count=$((covered_count + 1))
    fi

    printf '    {\n'
    printf '      \"id\": \"%s\",\n' "$(json_escape "${invariant_id}")"
    printf '      \"title\": \"%s\",\n' "$(json_escape "${INVARIANT_TITLES[${invariant_id}]}")"
    printf '      \"positive\": { \"count\": %s, \"cases\": [' "${pos_count}"
    if (( pos_count > 0 )); then
      printf ' '
      emit_case_array_json "${pos_matches}"
    fi
    printf ' ] },\n'
    printf '      \"rejection\": { \"count\": %s, \"cases\": [' "${neg_count}"
    if (( neg_count > 0 )); then
      printf ' '
      emit_case_array_json "${neg_matches}"
    fi
    printf ' ] },\n'
    printf '      \"covered\": %s\n' "$([[ ${pos_count} -gt 0 && ${neg_count} -gt 0 ]] && echo true || echo false)"
    if (( invariant_count < ${#names[@]} )); then
      printf '    },\n'
    else
      printf '    }\n'
    fi
  done

  printf '  ],\n'
  printf '  \"covered_count\": %d,\n' "${covered_count}"
  printf '  \"missing_count\": %d,\n' "${#missing[@]}"
  printf '  \"missing_invariants\": ['
  if (( ${#missing[@]} > 0 )); then
    local first=1
    for invariant_id in "${missing[@]}"; do
      if (( first == 0 )); then
        printf ', '
      fi
      printf '"%s"' "$(json_escape "${invariant_id}")"
      first=0
    done
  fi
  printf ']\n'
  printf '}\n'

  if (( ${#missing[@]} > 0 )); then
    return 1
  fi
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

  if [[ "${ARCH}" != "i386" ]]; then
    die "unsupported arch: ${ARCH}"
  fi

  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_coverage_matrix
}

main "$@"
