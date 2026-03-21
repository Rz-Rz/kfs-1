#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

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
drivers-export-ownership-fails
services-export-ownership-fails
leaf-export-ownership-fails
types-export-ownership-fails
core-nonentry-export-ownership-fails
EOF
}

describe_case() {
  case "$1" in
    drivers-export-ownership-fails)
      printf '%s\n' "rejects export declarations in drivers"
      ;;
    services-export-ownership-fails)
      printf '%s\n' "rejects export declarations in services"
      ;;
    leaf-export-ownership-fails)
      printf '%s\n' "rejects export declarations in private leaf files"
      ;;
    types-export-ownership-fails)
      printf '%s\n' "rejects export declarations in types"
      ;;
    core-nonentry-export-ownership-fails)
      printf '%s\n' "rejects export declarations in non-entry core"
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

cleanup() {
  if [[ -n "${TMPDIR}" ]]; then
    rm -rf "${TMPDIR}"
  fi
}

trap cleanup EXIT

is_disallowed_export_file() {
  local path="$1"

  case "${path}" in
    src/kernel/types/*|src/kernel/types.rs)
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
    imp.rs|writer.rs|logic_impl.rs|string_impl.rs|memory_impl.rs|*_impl.rs)
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
  ' "${file}"
}

collect_source_exports() {
  local file root="$1"

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

assert_no_disallowed_exports() {
  local line symbol file owner expected
  local root="$1"
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
  done < <(collect_source_exports "${root}")

  for sym in "${EXPECTED_EXPORT_SYMBOLS[@]}"; do
    owner="${EXPECTED_EXPORT_OWNER[${sym}]}"
    if [[ ! -f "${root}/${owner}" ]]; then
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
    return 1
  fi

  return 0
}

expect_failure() {
  local description="$1"
  shift

  if "$@"; then
    echo "FAIL ${CASE}: ${description} unexpectedly passed"
    return 1
  fi

  echo "PASS ${CASE}: ${description} rejected"
  return 0
}

make_target_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p "${TMPDIR}/src/kernel"/{core,services,drivers/vga_text,klib/string,klib/memory,types}

  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn kmain() -> ! {
  loop {}
}
EOF

  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF

  cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn kfs_strlen(_ptr: *const u8) -> usize {
  0
}

#[no_mangle]
pub extern "C" fn kfs_strcmp(_a: *const u8, _b: *const u8, _n: usize) -> i32 {
  let _ = (_a, _b, _n);
  0
}
EOF

  cat >"${TMPDIR}/src/kernel/klib/string/imp.rs" <<'EOF'
pub unsafe fn string_impl() {}
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
#[no_mangle]
pub unsafe extern "C" fn kfs_memcpy(_dst: *mut u8, _src: *const u8, _len: usize) -> *mut u8 {
  _dst
}

#[no_mangle]
pub unsafe extern "C" fn kfs_memset(_dst: *mut u8, _c: u8, _len: usize) -> *mut u8 {
  _dst
}
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/imp.rs" <<'EOF'
pub unsafe fn memory_impl() {}
EOF

  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn console_write() {}
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
pub fn write() {}
EOF

  cat >"${TMPDIR}/src/kernel/types/range.rs" <<'EOF'
#[repr(C)]
pub struct KernelRange {
  pub start: usize,
  pub end: usize,
}
EOF
}

run_case() {
  local root="${TMPDIR}"

  case "${CASE}" in
    drivers-export-ownership-fails)
      printf '\n#[no_mangle]\npub extern "C" fn leaked_driver() {}\n' >>"${root}/src/kernel/drivers/vga_text/writer.rs"
      expect_failure "drivers-export-ownership" assert_no_disallowed_exports "${root}"
      ;;
    services-export-ownership-fails)
      printf '\n#[no_mangle]\npub extern "C" fn leaked_service() {}\n' >>"${root}/src/kernel/services/console.rs"
      expect_failure "services-export-ownership" assert_no_disallowed_exports "${root}"
      ;;
    leaf-export-ownership-fails)
      printf '\n#[no_mangle]\npub extern "C" fn leaked_leaf() {}\n' >>"${root}/src/kernel/klib/string/imp.rs"
      expect_failure "leaf-export-ownership" assert_no_disallowed_exports "${root}"
      ;;
    types-export-ownership-fails)
      printf '\n#[no_mangle]\npub extern "C" fn leaked_types() {}\n' >>"${root}/src/kernel/types/range.rs"
      expect_failure "types-export-ownership" assert_no_disallowed_exports "${root}"
      ;;
    core-nonentry-export-ownership-fails)
      printf '\n#[no_mangle]\npub extern "C" fn leaked_core() {}\n' >>"${root}/src/kernel/core/init.rs"
      expect_failure "core-nonentry-export-ownership" assert_no_disallowed_exports "${root}"
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
  make_target_tree
  run_case
}

main "$@"
