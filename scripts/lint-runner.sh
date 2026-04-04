#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HAS_FAILURE=0
REQUIRED_TOOLS=(
	bash
	python3
	rg
	rustfmt
	shellcheck
	shfmt
	black
	ruff
)
SHELL_QUALITY_FILES=(
	"${ROOT_DIR}/scripts/lint.sh"
	"${ROOT_DIR}/scripts/lint-runner.sh"
	"${ROOT_DIR}/scripts/container.sh"
	"${ROOT_DIR}/scripts/dev-env.sh"
	"${ROOT_DIR}/scripts/run-ui.sh"
	"${ROOT_DIR}/scripts/test-host.sh"
	"${ROOT_DIR}/scripts/with-build-lock.sh"
	"${ROOT_DIR}/scripts/boot-tests/ui-interaction.sh"
	"${ROOT_DIR}/scripts/boot-tests/compact-geometry.sh"
	"${ROOT_DIR}/scripts/boot-tests/vga-memory.sh"
	"${ROOT_DIR}/scripts/boot-tests/lib/qemu-vnc.bash"
)

say() {
	local kind="$1"
	local msg="$2"
	echo "[$kind] ${msg}"
}

pass() {
	say PASS "$1"
}

warn() {
	say WARN "$1"
}

fail() {
	HAS_FAILURE=1
	say FAIL "$1"
}

require_tools() {
	local tool

	for tool in "${REQUIRED_TOOLS[@]}"; do
		if ! command -v "${tool}" >/dev/null 2>&1; then
			fail "missing required tool: ${tool}"
		fi
	done
}

run_shell_checks() {
	local -a scripts
	local -a shell_quality_files
	mapfile -t scripts < <(rg --files "${ROOT_DIR}/scripts" -g '*.sh')
	shell_quality_files=("${SHELL_QUALITY_FILES[@]}")

	if ((${#scripts[@]} == 0)); then
		warn "no shell scripts found under scripts/"
		return 0
	fi

	say INFO "running shell syntax checks on ${#scripts[@]} files"
	for path in "${scripts[@]}"; do
		if ! bash -n "${path}"; then
			fail "shell syntax failed: ${path}"
		fi
	done

	pass "shell syntax"

	if ! shellcheck -S warning -e SC2046 -x "${shell_quality_files[@]}"; then
		fail "shellcheck reported issues in scripts/**/*.sh"
	else
		pass "shellcheck"
	fi

	if ! shfmt -d "${shell_quality_files[@]}"; then
		fail "shfmt reported formatting issues in curated shell infrastructure"
	else
		pass "shell formatting"
	fi
}

run_python_checks() {
	say INFO "running python syntax checks"
	if ! python3 -m compileall -q "${ROOT_DIR}/scripts"; then
		fail "python bytecode compile failed"
	else
		pass "python compileall"
	fi

	if ! black --check "${ROOT_DIR}/scripts"; then
		fail "black formatting violations in scripts/**/*.py"
	else
		pass "python formatting"
	fi

	if ! ruff check "${ROOT_DIR}/scripts"; then
		fail "ruff check found Python quality issues in scripts/**/*.py"
	else
		pass "python lint"
	fi
}

run_rust_checks() {
	local -a rust_files
	mapfile -t rust_files < <(rg --files "${ROOT_DIR}/src" -g '*.rs')

	if ((${#rust_files[@]} == 0)); then
		warn "no Rust files found under src/"
		return 0
	fi

	if ! rustfmt --edition 2021 --check "${rust_files[@]}"; then
		fail "rustfmt check failed"
	else
		pass "rustfmt"
	fi
}

run_no_heap_gate() {
	local -a patterns=(
		'\\bextern crate alloc\\b'
		'\\buse\\s+alloc::'
		'\\balloc::'
		'\\bVec<'
		'\\bString\\b'
		'\\bBox<'
		'\\bBox::'
		'\\bRc<'
		'\\bRc::'
		'\\bArc<'
		'\\bArc::'
		'\\bRefCell\\b'
		'\\bCell<'
		'\\bHashMap\\b'
		'\\bHashSet\\b'
		'\\bBTreeMap\\b'
		'\\bBTreeSet\\b'
		'\\bVecDeque\\b'
		'\\bBinaryHeap\\b'
	)
	local any_hits=0

	for pattern in "${patterns[@]}"; do
		if rg -n -g '*.rs' -e "${pattern}" "${ROOT_DIR}/src"; then
			any_hits=1
		fi
	done

	if ((any_hits)); then
		fail "heap-backed type or allocation primitive detected in src/"
	else
		pass "no-heap policy in src/"
	fi
}

require_tools

if ((HAS_FAILURE)); then
	exit 1
fi

run_shell_checks
run_python_checks
run_rust_checks
run_no_heap_gate

if ((HAS_FAILURE)); then
	exit 1
fi

pass "quality lane complete"
