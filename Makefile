ARCH ?=
arch ?= $(if $(ARCH),$(ARCH),i386)
PYTHON ?= python3
kernel := build/kernel-$(arch).bin
iso := build/os-$(arch).iso
img := build/os-$(arch).img
kernel_test := build/kernel-$(arch)-test.bin
iso_test := build/os-$(arch)-test.iso
img_test := build/os-$(arch)-test.img

linker_script := src/arch/$(arch)/linker.ld
grub_cfg := src/arch/$(arch)/grub.cfg
assembly_source_files := $(wildcard src/arch/$(arch)/*.asm)
assembly_object_files := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/%.o, $(assembly_source_files))
assembly_object_files_test := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/test/%.o, $(assembly_source_files))

rust_target := i686-unknown-linux-gnu
rust_source_files := src/main.rs
rust_object_files := build/arch/$(arch)/rust/kernel.o
rust_output_dir := build/arch/$(arch)/rust
kernel_keepglobals := scripts/architecture-tests/fixtures/exports.$(arch).keepglobals

KFS_TEST_FORCE_FAIL ?= 0
KFS_TEST_DIRTY_BSS ?= 0
KFS_TEST_BAD_LAYOUT ?= 0
KFS_TEST_BAD_STRING ?= 0
KFS_TEST_BAD_MEMORY ?= 0
KFS_SCREEN_GEOMETRY_PRESET ?= vga80x25
KFS_SKIP_LINT ?= 0

RUST_CFG_FLAGS :=
ifeq ($(KFS_SCREEN_GEOMETRY_PRESET),compact40x10)
RUST_CFG_FLAGS += --cfg kfs_geometry_preset_compact40x10
endif
RUST_CODEGEN_FLAGS := -C target-feature=-sse,-sse2

TEST_ASM_DEFS := -DKFS_TEST=1
ifeq ($(KFS_TEST_FORCE_FAIL),1)
TEST_ASM_DEFS += -DKFS_TEST_FORCE_FAIL=1
endif
ifeq ($(KFS_TEST_DIRTY_BSS),1)
TEST_ASM_DEFS += -DKFS_TEST_DIRTY_BSS=1
endif
ifeq ($(KFS_TEST_BAD_LAYOUT),1)
TEST_ASM_DEFS += -DKFS_TEST_BAD_LAYOUT=1
endif
ifeq ($(KFS_TEST_BAD_STRING),1)
TEST_ASM_DEFS += -DKFS_TEST_BAD_STRING=1
endif
ifeq ($(KFS_TEST_BAD_MEMORY),1)
TEST_ASM_DEFS += -DKFS_TEST_BAD_MEMORY=1
endif

TEST_TIMEOUT_SECS ?= 10
TEST_PASS_RC ?= 33
TEST_FAIL_RC ?= 35
test_ui_venv := .venv-test-ui
test_ui_python := $(if $(wildcard $(test_ui_venv)/bin/python),$(test_ui_venv)/bin/python,$(PYTHON))
lint_script := scripts/lint.sh

.PHONY: all clean run iso \
	container-image container-image-force container-shell container-env-check \
	container-all container-iso container-run container-qemu-smoke \
	container-bootstrap container-smoke \
	metrics-sync \
	lint test test-plain test-ui test-ui-demo test-ui-bootstrap \
	dev iso-in-container run-in-container \
	run-ui run-ui-compact \
	iso-test test-qemu test-vga \
	img img-test run-img

all: $(kernel)

clean:
	@rm -rf build

run: $(iso)
	@qemu-system-i386 -cdrom $(iso)

## Manual visual-proof entrypoints.
## - run-ui: normal 80x25 UI
## - run-ui-compact: compact 40x10 UI
run-ui: KFS_SCREEN_GEOMETRY_PRESET := vga80x25
run-ui:
	@bash scripts/container.sh build-image
	@KFS_SCREEN_GEOMETRY_PRESET=$(KFS_SCREEN_GEOMETRY_PRESET) bash scripts/container.sh run-gui -- bash scripts/run-ui.sh $(arch)

run-ui-compact: KFS_SCREEN_GEOMETRY_PRESET := compact40x10
run-ui-compact:
	@KFS_SCREEN_GEOMETRY_PRESET=compact40x10 $(MAKE) --no-print-directory run-ui arch=$(arch)

iso: $(iso)

run-img: $(img)
	@qemu-system-i386 -drive format=raw,file=$(img)

img: $(img)

$(img): $(iso)
	@cp $(iso) $(img)

$(iso): $(kernel) $(grub_cfg)
	@mkdir -p build/isofiles/boot/grub
	@cp $(kernel) build/isofiles/boot/kernel.bin
	@cp $(grub_cfg) build/isofiles/boot/grub
	@grub-mkrescue -o $(iso) build/isofiles 2> /dev/null
	@rm -rf build/isofiles

$(kernel): $(assembly_object_files) $(rust_object_files) $(linker_script)
	@ld -m elf_i386 -n -T $(linker_script) -o $(kernel) $(assembly_object_files) $(rust_object_files)
	@objcopy --keep-global-symbols=$(kernel_keepglobals) $(kernel)
	@KFS_M3_2_KERNEL="$(kernel)" bash scripts/tests/kernel-sections.sh $(arch)

# compile assembly files
build/arch/$(arch)/%.o: src/arch/$(arch)/%.asm
	@mkdir -p $(dir $@)
	@nasm -felf32 $< -o $@

iso-test: $(iso_test)

img-test: $(img_test)

$(img_test): $(iso_test)
	@cp $(iso_test) $(img_test)

$(iso_test): $(kernel_test) $(grub_cfg)
	@mkdir -p build/isofiles/boot/grub
	@cp $(kernel_test) build/isofiles/boot/kernel.bin
	@cp $(grub_cfg) build/isofiles/boot/grub
	@grub-mkrescue -o $(iso_test) build/isofiles 2> /dev/null
	@rm -rf build/isofiles

$(kernel_test): $(assembly_object_files_test) $(rust_object_files) $(linker_script)
	@ld -m elf_i386 -n -T $(linker_script) -o $(kernel_test) $(assembly_object_files_test) $(rust_object_files)
	@objcopy --keep-global-symbols=$(kernel_keepglobals) $(kernel_test)
	@KFS_M3_2_KERNEL="$(kernel_test)" bash scripts/tests/kernel-sections.sh $(arch)

build/arch/$(arch)/test/%.o: src/arch/$(arch)/%.asm
	@mkdir -p $(dir $@)
	@nasm -felf32 $(TEST_ASM_DEFS) $< -o $@

$(rust_output_dir):
	@mkdir -p $@

build/arch/$(arch)/rust/kernel.o: src/main.rs | $(rust_output_dir)
	@rustc \
		$(RUST_CFG_FLAGS) \
		--crate-type lib \
		--target $(rust_target) \
		--emit=obj \
		$(RUST_CODEGEN_FLAGS) \
		-C panic=abort \
		-C force-unwind-tables=no \
		-C opt-level=z \
		-C code-model=kernel \
		-C relocation-model=static \
		-o $@ \
		$<

container-image:
	@bash scripts/container.sh build-image

container-image-force:
	@KFS_FORCE_IMAGE_BUILD=1 bash scripts/container.sh build-image

container-shell: container-image
	@bash scripts/container.sh shell

container-env-check: container-image
	@bash scripts/container.sh env-check

container-all: container-image
	@bash scripts/container.sh run -- make all arch=$(arch)

container-iso: container-image
	@bash scripts/container.sh run -- make iso arch=$(arch)

container-run: container-image
	@bash scripts/container.sh run -- make run arch=$(arch)

container-qemu-smoke: container-iso
	@bash scripts/container.sh run -- bash -lc 'bash scripts/qemu-smoke.sh $(arch)'

container-bootstrap: container-env-check
	@true

container-smoke: container-env-check container-qemu-smoke
	@true

test-qemu: container-image-force
	@KFS_CONTAINER_TTY=1 bash scripts/container.sh run -- env \
		TEST_TIMEOUT_SECS=$(TEST_TIMEOUT_SECS) \
		TEST_PASS_RC=$(TEST_PASS_RC) \
		TEST_FAIL_RC=$(TEST_FAIL_RC) \
		KFS_TEST_FORCE_FAIL=$(KFS_TEST_FORCE_FAIL) \
		KFS_TEST_BAD_STRING=$(KFS_TEST_BAD_STRING) \
		KFS_TEST_BAD_MEMORY=$(KFS_TEST_BAD_MEMORY) \
		bash scripts/boot-tests/qemu-boot.sh $(arch)

test-vga: container-image-force
	@KFS_CONTAINER_TTY=1 bash scripts/container.sh run -- env \
		TEST_TIMEOUT_SECS=$(TEST_TIMEOUT_SECS) \
		KFS_HOST_TEST_DIRECT=1 \
		bash scripts/boot-tests/vga-memory.sh $(arch)

test:
	@if [ "$(KFS_SKIP_LINT)" != "1" ]; then \
		"$(MAKE)" --no-print-directory lint; \
	fi
	@bash -lc 'set -euo pipefail; \
		mode="$${KFS_TEST_UI:-auto}"; \
		if [[ "$${mode}" == "0" ]] || [[ -n "$${CI:-}" ]] || [[ -n "$${GITHUB_ACTIONS:-}" ]] || [[ ! -t 1 ]]; then \
			exec bash scripts/test-host.sh $(arch); \
		fi; \
		if "$(test_ui_python)" -c "import textual" >/dev/null 2>&1; then \
			exec "$(test_ui_python)" scripts/kfs_tui.py --arch "$(arch)" --make-target test-plain; \
		fi; \
		if [[ "$${mode}" == "1" ]]; then \
			echo "error: Textual is not installed. Run '\''make test-ui-bootstrap'\'' first." >&2; \
			exit 2; \
		fi; \
		echo "warn: Textual UI dependencies missing; falling back to plain test output. Run '\''make test-ui-bootstrap'\'' to enable the TUI." >&2; \
		exec bash scripts/test-host.sh $(arch)'

lint:
	@bash $(lint_script)

test-plain:
	@$(PYTHON) scripts/kfs_test_runner.py --arch $(arch) --make-target test-plain

test-ui:
	@KFS_TEST_UI=1 $(MAKE) --no-print-directory test arch=$(arch)

test-ui-demo:
	@"$(test_ui_python)" scripts/kfs_tui.py --demo

test-ui-bootstrap:
	@$(PYTHON) -m venv "$(test_ui_venv)"
	@"$(test_ui_venv)/bin/python" -m pip install --upgrade pip
	@"$(test_ui_venv)/bin/pip" install -r requirements.txt

metrics-sync:
	@$(PYTHON) scripts/kfs_metrics_sync.py

dev: container-shell
	@true

iso-in-container: container-iso
	@true

run-in-container: container-run
	@true
