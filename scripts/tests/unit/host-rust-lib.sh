#!/usr/bin/env bash

HOST_LIB_SOURCE="src/lib.rs"

run_host_rust_test() {
	local test_source="$1"
	local test_bin="$2"
	local filter="$3"
	local host_lib_flags="${KFS_HOST_LIB_RUSTC_FLAGS:-}"
	local host_test_flags="${KFS_HOST_TEST_RUSTC_FLAGS:-}"
	local test_name="${test_bin##*/}"

	[[ -n "${test_name}" ]] || test_name="host-unit-test"

	bash scripts/container.sh run -- \
		env \
		KFS_HOST_LIB_SOURCE="${HOST_LIB_SOURCE}" \
		KFS_HOST_TEST_SOURCE="${test_source}" \
		KFS_HOST_TEST_BIN_NAME="${test_name}" \
		KFS_HOST_TEST_FILTER="${filter}" \
		KFS_HOST_LIB_RUSTC_FLAGS="${host_lib_flags}" \
		KFS_HOST_TEST_RUSTC_FLAGS="${host_test_flags}" \
		bash -lc '
			tmpdir="$(mktemp -d)"
			trap '\''rm -rf "${tmpdir}"'\'' EXIT
			rustc ${KFS_HOST_LIB_RUSTC_FLAGS} \
				--crate-name kfs \
				--crate-type rlib \
				--edition=2021 \
				-o "${tmpdir}/libkfs.rlib" \
				"${KFS_HOST_LIB_SOURCE}" >/dev/null
			rustc --test ${KFS_HOST_TEST_RUSTC_FLAGS} \
				--edition=2021 \
				--extern kfs="${tmpdir}/libkfs.rlib" \
				-o "${tmpdir}/${KFS_HOST_TEST_BIN_NAME}" \
				"${KFS_HOST_TEST_SOURCE}" >/dev/null
			if [[ -n "${KFS_HOST_TEST_FILTER}" ]]; then
				"${tmpdir}/${KFS_HOST_TEST_BIN_NAME}" "${KFS_HOST_TEST_FILTER}"
			else
				"${tmpdir}/${KFS_HOST_TEST_BIN_NAME}"
			fi
		'
}
