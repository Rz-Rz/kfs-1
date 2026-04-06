#!/usr/bin/env bash

HOST_LIB_SOURCE="src/lib.rs"

run_host_rust_test() {
	local test_source="$1"
	local test_bin="$2"
	local filter="$3"
	local host_lib_flags="${KFS_HOST_LIB_RUSTC_FLAGS:-}"
	local host_test_flags="${KFS_HOST_TEST_RUSTC_FLAGS:-}"

	KFS_HOST_LIB_SOURCE="${HOST_LIB_SOURCE}" \
		KFS_HOST_TEST_SOURCE="${test_source}" \
		KFS_HOST_TEST_BIN_PATH="${test_bin}" \
		KFS_HOST_TEST_FILTER="${filter}" \
		KFS_HOST_LIB_RUSTC_FLAGS="${host_lib_flags}" \
		KFS_HOST_TEST_RUSTC_FLAGS="${host_test_flags}" \
		make --no-print-directory host-rust-test
}
