#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
	cat <<'EOF'
top-level-peer-file-fails
missing-host-library-root-fails
orphan-leaf-location-fails
cross-facade-leaf-import-fails
host-test-source-mount-fails
test-only-path-switching-fails
EOF
}

describe_case() {
	case "$1" in
	top-level-peer-file-fails) printf '%s\n' "rejects top-level Rust peer files under src/kernel" ;;
	missing-host-library-root-fails) printf '%s\n' "rejects missing src/lib.rs for host-linked tests" ;;
	orphan-leaf-location-fails) printf '%s\n' "rejects private leaves outside owning subsystem paths" ;;
	cross-facade-leaf-import-fails) printf '%s\n' "rejects facade importing another subsystem's private leaf" ;;
	host-test-source-mount-fails) printf '%s\n' "rejects host tests mounting production source directly" ;;
	test-only-path-switching-fails) printf '%s\n' "rejects cfg(test) path switching in kernel source" ;;
	*) return 1 ;;
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

make_tree() {
	TMPDIR="$(mktemp -d)"

	mkdir -p "${TMPDIR}/src/kernel"/{core,drivers/vga_text,drivers/serial,klib/string,klib/memory,machine,services,types}
	mkdir -p "${TMPDIR}/tests" "${TMPDIR}/scripts/tests/unit"

	cat >"${TMPDIR}/src/main.rs" <<'EOF'
pub mod kernel;
EOF
	cat >"${TMPDIR}/src/lib.rs" <<'EOF'
pub mod kernel;
EOF
	cat >"${TMPDIR}/src/kernel/mod.rs" <<'EOF'
pub mod core;
pub mod drivers;
pub mod klib;
pub mod machine;
pub mod services;
pub mod types;
EOF
	for layer in core drivers klib machine services types; do
		printf 'pub mod placeholder;\n' >"${TMPDIR}/src/kernel/${layer}/mod.rs"
	done

	cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn kmain() {}
EOF
	cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF
	cat >"${TMPDIR}/src/kernel/machine/port.rs" <<'EOF'
#[repr(transparent)]
pub struct Port(u16);
EOF
	cat >"${TMPDIR}/src/kernel/types/range.rs" <<'EOF'
#[repr(C)]
pub struct KernelRange {
    pub start: usize,
    pub end: usize,
}
EOF
	cat >"${TMPDIR}/src/kernel/types/screen.rs" <<'EOF'
#[repr(transparent)]
pub struct ColorCode(pub u8);

#[repr(C)]
pub struct ScreenCell {
    pub ascii: u8,
    pub color: ColorCode,
}

#[repr(C)]
pub struct CursorPos {
    pub row: usize,
    pub col: usize,
}
EOF
	cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
#[path = "imp.rs"]
mod imp;
EOF
	cat >"${TMPDIR}/src/kernel/klib/string/imp.rs" <<'EOF'
pub unsafe fn string_len(_ptr: *const u8) -> usize {
    0
}
EOF
	cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
#[path = "imp.rs"]
mod imp;
EOF
	cat >"${TMPDIR}/src/kernel/klib/memory/imp.rs" <<'EOF'
pub unsafe fn memory_copy(_dst: *mut u8, _src: *const u8, _len: usize) -> *mut u8 {
    _dst
}
EOF
	cat >"${TMPDIR}/src/kernel/drivers/vga_text/mod.rs" <<'EOF'
#[path = "writer.rs"]
mod writer;
EOF
	cat >"${TMPDIR}/src/kernel/drivers/serial/mod.rs" <<'EOF'
use crate::kernel::machine::port::Port;

pub fn initialize() {
    let _ = Port::new(0x3f8);
}
EOF
	cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
EOF
	cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn console_write() {}
EOF
	cat >"${TMPDIR}/src/kernel/services/diagnostics.rs" <<'EOF'
use crate::kernel::drivers::serial;

pub fn write_line() {
    serial::initialize();
}
EOF

	cat >"${TMPDIR}/tests/host_sample.rs" <<'EOF'
use kfs::kernel::types::range::KernelRange;

#[test]
fn host_links_real_library() {
    let _ = KernelRange::new(0, 1);
}
EOF

	cat >"${TMPDIR}/scripts/tests/unit/host-rust-lib.sh" <<'EOF'
#!/usr/bin/env bash
HOST_LIB_SOURCE="src/lib.rs"
run_host_rust_test() {
	KFS_HOST_LIB_SOURCE="${HOST_LIB_SOURCE}" \
	KFS_HOST_TEST_SOURCE="tests/host_sample.rs" \
	KFS_HOST_TEST_BIN_PATH="build/ut_host_sample" \
	make --no-print-directory host-rust-test
}
EOF
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

check_kernel_root_is_lone_top_level_rs() {
	local peers
	[[ -f "${TMPDIR}/src/main.rs" ]] || return 1
	[[ -f "${TMPDIR}/src/lib.rs" ]] || return 1
	[[ -f "${TMPDIR}/src/kernel/mod.rs" ]] || return 1
	peers="$(find "${TMPDIR}/src/kernel" -mindepth 1 -maxdepth 1 -type f -name '*.rs' -printf '%f\n' | sort)"
	[[ -n "${peers}" ]] && [[ "${peers}" == "mod.rs" ]]
}

check_private_leaves_owned() {
	local offenders

	offenders="$(
		find "${TMPDIR}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' -o -name '*_impl.rs' -o -name 'logic_impl.rs' -o -name 'sse2_*.rs' \) -printf '%P\n' |
			awk -F/ '
				{
					if (NF < 3) {
						print $0
						next
					}
					if ($1 !~ /^(core|drivers|klib|machine|services|types)$/) {
						print $0
					}
				}
			'
	)"

	[[ -z "${offenders}" ]]
}

check_private_leaf_imports_local() {
	local offenders
	offenders="$(
		find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
			xargs -0 rg -n '\#\[path[[:space:]]*=[[:space:]]*\"[^\"]*(string|memory|vga_text)/(imp|writer|sse2_[A-Za-z0-9_]+)\.rs\"|^\s*mod\s+(imp|writer|sse2_memcpy|sse2_memset)\s*;|\buse\s+crate::kernel::(?:klib|drivers)::(?:string|memory|vga_text)::(?:imp|writer|sse2_memcpy|sse2_memset)\b|\bcrate::kernel::(?:klib|drivers)::(?:string|memory|vga_text)::(?:imp|writer|sse2_memcpy|sse2_memset)\b' -P -S 2>/dev/null |
			grep -vE '^.*/src/kernel/(klib/string/mod\.rs|klib/memory/mod\.rs|drivers/vga_text/mod\.rs):' || true
	)"
	[[ -z "${offenders}" ]]
}

check_host_tests_do_not_mount_source() {
	! rg -n '#\[path[[:space:]]*=[[:space:]]*"\.\./src/|include!\([[:space:]]*"\.\./src/' \
		"${TMPDIR}/tests" "${TMPDIR}/scripts/tests" -g '*.rs' -g '*.sh' >/dev/null
}

check_no_test_only_path_switching() {
	! rg -n '#\[cfg\((test|not\(test\))\)\]' "${TMPDIR}/src/kernel" -g '*.rs' >/dev/null
}

run_case() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	make_tree

	case "${CASE}" in
	top-level-peer-file-fails)
		printf '\npub fn bad() {}\n' >"${TMPDIR}/src/kernel/extra.rs"
		expect_failure "top-level peer file" check_kernel_root_is_lone_top_level_rs
		;;
	missing-host-library-root-fails)
		rm -f "${TMPDIR}/src/lib.rs"
		expect_failure "missing host library root" check_kernel_root_is_lone_top_level_rs
		;;
	orphan-leaf-location-fails)
		printf '\npub fn bad() {}\n' >"${TMPDIR}/src/kernel/services/imp.rs"
		expect_failure "orphan private leaf location" check_private_leaves_owned
		;;
	cross-facade-leaf-import-fails)
		printf '\nuse crate::kernel::klib::string::imp;\n' >>"${TMPDIR}/src/kernel/services/console.rs"
		expect_failure "cross-facade leaf import" check_private_leaf_imports_local
		;;
	host-test-source-mount-fails)
		printf '\n#[path = "../src/kernel/core/init.rs"]\nmod mounted_init;\n' >>"${TMPDIR}/tests/host_sample.rs"
		expect_failure "host test mounting production source" check_host_tests_do_not_mount_source
		;;
	test-only-path-switching-fails)
		printf '\n#[cfg(test)]\nmod fake_root {}\n' >>"${TMPDIR}/src/kernel/core/entry.rs"
		expect_failure "cfg(test) path switching in kernel source" check_no_test_only_path_switching
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

	describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
	run_case
}

main "$@"
