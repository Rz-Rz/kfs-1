#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

LAYERS=("core" "drivers" "klib" "machine" "services" "types")

list_cases() {
	cat <<'EOF'
crate-roots-use-single-shared-kernel-root
kernel-top-level-directories-are-layers-only
layer-roots-are-mod-rs
private-leaves-stay-under-owning-subsystems
private-leaf-imports-are-local
host-tests-link-through-real-library-boundary
host-tests-do-not-mount-production-source
kernel-tree-avoids-test-only-path-switching
EOF
}

describe_case() {
	case "$1" in
	crate-roots-use-single-shared-kernel-root) printf '%s\n' "src/main.rs and src/lib.rs share the same src/kernel/mod.rs root without top-level src/kernel peer files" ;;
	kernel-top-level-directories-are-layers-only) printf '%s\n' "kernel top-level directories match the target layer set" ;;
	layer-roots-are-mod-rs) printf '%s\n' "each kernel layer has a mod.rs root" ;;
	private-leaves-stay-under-owning-subsystems) printf '%s\n' "private leaves stay under an owning subsystem path" ;;
	private-leaf-imports-are-local) printf '%s\n' "private leaves are imported only by owning facades" ;;
	host-tests-link-through-real-library-boundary) printf '%s\n' "host test wrappers compile src/lib.rs and link tests through --extern kfs" ;;
	host-tests-do-not-mount-production-source) printf '%s\n' "host tests do not mount production source with #[path] or include!" ;;
	kernel-tree-avoids-test-only-path-switching) printf '%s\n' "kernel source avoids cfg(test) path switching" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_crate_roots_use_single_shared_kernel_root() {
	local peers

	[[ -f "${REPO_ROOT}/src/main.rs" ]] || {
		echo "FAIL ${CASE}: missing src/main.rs"
		return 1
	}

	[[ -f "${REPO_ROOT}/src/lib.rs" ]] || {
		echo "FAIL ${CASE}: missing src/lib.rs"
		return 1
	}

	[[ -f "${REPO_ROOT}/src/kernel/mod.rs" ]] || {
		echo "FAIL ${CASE}: missing src/kernel/mod.rs"
		return 1
	}

	peers="$(find "${REPO_ROOT}/src/kernel" -mindepth 1 -maxdepth 1 -type f -name '*.rs' -printf '%f\n' | sort)"
	if [[ -n "${peers}" ]] && [[ "${peers}" != "mod.rs" ]]; then
		echo "FAIL ${CASE}: top-level Rust peer files must not exist under src/kernel"
		printf '%s\n' "${peers}"
		return 1
	fi

	echo "PASS ${CASE}: src/main.rs, src/lib.rs, and src/kernel/mod.rs define the shared roots"
}

assert_top_level_is_layers_only() {
	local expected actual

	expected="$(
		cat <<'EOF'
core
drivers
klib
machine
services
types
EOF
	)"

	actual="$(find "${REPO_ROOT}/src/kernel" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)"

	if [[ "${actual}" != "${expected}" ]]; then
		echo "FAIL ${CASE}: kernel top-level directories are not exactly the layer set"
		printf 'expected:\n%s\n' "${expected}"
		printf 'actual:\n%s\n' "${actual}"
		return 1
	fi

	echo "PASS ${CASE}: kernel top-level directories are exactly expected layers"
}

assert_layer_roots_are_mod_rs() {
	local layer
	local missing=()
	local root

	for layer in "${LAYERS[@]}"; do
		root="${REPO_ROOT}/src/kernel/${layer}/mod.rs"
		[[ -f "${root}" ]] || missing+=("${root#${REPO_ROOT}/}")
	done

	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "FAIL ${CASE}: missing layer root mod.rs files"
		printf '%s\n' "${missing[@]}"
		return 1
	fi

	echo "PASS ${CASE}: all layer roots are explicit mod.rs files"
}

assert_private_leaves_stay_under_owning_subsystems() {
	local offenders

	offenders="$(
		find "${REPO_ROOT}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' -o -name '*_impl.rs' -o -name 'logic_impl.rs' -o -name 'sse2_*.rs' \) -printf '%P\n' |
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

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: private leaves are outside an owning subsystem path"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: private leaves stay under owning subsystem paths"
}

assert_private_leaf_imports_are_local() {
	local offenders

	offenders="$(
		find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
			xargs -0 rg -n '\#\[path[[:space:]]*=[[:space:]]*"[^\"]*(string|memory|keyboard|vga_text)/(imp|writer|sse2_[A-Za-z0-9_]+)\.rs"|^\s*mod\s+(imp|writer|sse2_memcpy|sse2_memset)\s*;|\buse\s+crate::kernel::(?:klib|drivers)::(?:string|memory|keyboard|vga_text)::(?:imp|writer|sse2_memcpy|sse2_memset)\b|\bcrate::kernel::(?:klib|drivers)::(?:string|memory|keyboard|vga_text)::(?:imp|writer|sse2_memcpy|sse2_memset)\b' -P -S 2>/dev/null |
			grep -vE '^.*/src/kernel/(klib/string/mod\.rs|klib/memory/mod\.rs|drivers/keyboard/mod\.rs|drivers/vga_text/mod\.rs):' || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: private leaf imports referenced outside owning subsystem files"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: private leaf imports are local to owning facades"
}

assert_host_tests_link_through_real_library_boundary() {
	local helper="${REPO_ROOT}/scripts/tests/unit/host-rust-lib.sh"
	local makefile="${REPO_ROOT}/Makefile"

	[[ -f "${helper}" ]] || {
		echo "FAIL ${CASE}: missing ${helper#${REPO_ROOT}/}"
		return 1
	}

	[[ -f "${makefile}" ]] || {
		echo "FAIL ${CASE}: missing ${makefile#${REPO_ROOT}/}"
		return 1
	}

	if ! rg -n "HOST_LIB_SOURCE=\"src/lib\\.rs\"" "${helper}" >/dev/null; then
		echo "FAIL ${CASE}: host test helper does not compile src/lib.rs"
		return 1
	fi

	if ! rg -n 'make --no-print-directory host-rust-test' "${helper}" >/dev/null; then
		echo "FAIL ${CASE}: host test helper does not delegate through make host-rust-test"
		return 1
	fi

	if ! rg -n -- '--extern kfs=' "${makefile}" >/dev/null; then
		echo "FAIL ${CASE}: Makefile host test rule does not link through --extern kfs"
		return 1
	fi

	echo "PASS ${CASE}: host tests link through the real library boundary"
}

assert_host_tests_do_not_mount_production_source() {
	local offenders

	offenders="$(
		rg -n '#\[path[[:space:]]*=[[:space:]]*"\.\./src/|include!\([[:space:]]*"\.\./src/' \
			"${REPO_ROOT}/tests" "${REPO_ROOT}/scripts/tests" -g '*.rs' -g '*.sh' || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: host tests mount production source directly"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: host tests avoid direct production-source mounts"
}

assert_kernel_tree_avoids_test_only_path_switching() {
	local offenders

	offenders="$(
		rg -n '#\[cfg\((test|not\(test\))\)\]' "${REPO_ROOT}/src/kernel" -g '*.rs' || true
	)"

	if [[ -n "${offenders}" ]]; then
		echo "FAIL ${CASE}: kernel tree contains test-only path switching"
		printf '%s\n' "${offenders}"
		return 1
	fi

	echo "PASS ${CASE}: kernel tree avoids cfg(test) path switching"
}

run_case() {
	case "${CASE}" in
	crate-roots-use-single-shared-kernel-root) assert_crate_roots_use_single_shared_kernel_root ;;
	kernel-top-level-directories-are-layers-only) assert_top_level_is_layers_only ;;
	layer-roots-are-mod-rs) assert_layer_roots_are_mod_rs ;;
	private-leaves-stay-under-owning-subsystems) assert_private_leaves_stay_under_owning_subsystems ;;
	private-leaf-imports-are-local) assert_private_leaf_imports_are_local ;;
	host-tests-link-through-real-library-boundary) assert_host_tests_link_through_real_library_boundary ;;
	host-tests-do-not-mount-production-source) assert_host_tests_do_not_mount_production_source ;;
	kernel-tree-avoids-test-only-path-switching) assert_kernel_tree_avoids_test_only_path_switching ;;
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
