#!/usr/bin/env bash

HOST_LIB_SOURCE="src/lib.rs"

host_rust_test_output_path() {
	local requested="$1"
	local root="${KFS_HOST_TEST_OUTPUT_ROOT:-}"

	if [[ -z "${root}" && "${KFS_INSIDE_CONTAINER:-0}" == "1" ]]; then
		root="${TMPDIR:-/tmp}/kfs-host-rust-tests-${USER:-$(id -u)}"
	fi

	if [[ -z "${root}" ]]; then
		printf '%s\n' "${requested}"
		return 0
	fi

	printf '%s/%s\n' "${root}" "$(basename "${requested}")"
}

run_host_rust_test() {
	local test_source="$1"
	local test_bin="$2"
	local filter="$3"
	local host_lib_flags="${KFS_HOST_LIB_RUSTC_FLAGS:-}"
	local host_test_flags="${KFS_HOST_TEST_RUSTC_FLAGS:-}"
	local output_bin

	output_bin="$(host_rust_test_output_path "${test_bin}")"

	KFS_HOST_LIB_SOURCE="${HOST_LIB_SOURCE}" \
		KFS_HOST_TEST_SOURCE="${test_source}" \
		KFS_HOST_TEST_BIN_PATH="${output_bin}" \
		KFS_HOST_TEST_FILTER="${filter}" \
		KFS_HOST_LIB_RUSTC_FLAGS="${host_lib_flags}" \
		KFS_HOST_TEST_RUSTC_FLAGS="${host_test_flags}" \
		make --no-print-directory host-rust-test
}
