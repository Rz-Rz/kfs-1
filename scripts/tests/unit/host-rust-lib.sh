#!/usr/bin/env bash

HOST_LIB_SOURCE="src/lib.rs"

run_host_rust_test() {
  local test_source="$1"
  local test_bin="$2"
  local filter="$3"

  bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
    bash -lc "tmpdir=\$(mktemp -d) && trap 'rm -rf \"\${tmpdir}\"' EXIT && rustc --crate-name kfs --crate-type rlib --edition=2021 -o \"\${tmpdir}/libkfs.rlib\" '${HOST_LIB_SOURCE}' >/dev/null && rustc --test --edition=2021 --extern kfs=\"\${tmpdir}/libkfs.rlib\" -o '${test_bin}' '${test_source}' >/dev/null && '${test_bin}' '${filter}'"
}
