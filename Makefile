ARCH ?=
arch ?= $(if $(ARCH),$(ARCH),i386)
PYTHON ?= python3
source_date_epoch := $(shell bash scripts/source-date-epoch.sh)
xorriso_date := $(shell date -u -d "@$(source_date_epoch)" +%Y%m%d%H%M%S00)
repro_env = LC_ALL=C LANG=C TZ=UTC SOURCE_DATE_EPOCH=$(source_date_epoch)
kernel := build/kernel-$(arch).bin
iso := build/os-$(arch).iso
img := build/os-$(arch).img
kernel_compact := build/kernel-$(arch)-compact40x10.bin
iso_compact := build/os-$(arch)-compact40x10.iso
ui_runner_image := kfs1-ui-runner:latest
ui_runner_containerfile := Dockerfile.ui-runner
kernel_test := build/kernel-$(arch)-test.bin
iso_test := build/os-$(arch)-test.iso
img_test := build/os-$(arch)-test.img
kernel_test_bad_string := build/kernel-$(arch)-test-bad-string.bin
iso_test_bad_string := build/os-$(arch)-test-bad-string.iso
kernel_test_bad_memory := build/kernel-$(arch)-test-bad-memory.bin
iso_test_bad_memory := build/os-$(arch)-test-bad-memory.iso
kernel_test_dirty_bss := build/kernel-$(arch)-test-dirty-bss.bin
iso_test_dirty_bss := build/os-$(arch)-test-dirty-bss.iso
kernel_test_bad_layout := build/kernel-$(arch)-test-bad-layout.bin
iso_test_bad_layout := build/os-$(arch)-test-bad-layout.iso
kernel_test_no_cpuid := build/kernel-$(arch)-test-no-cpuid.bin
iso_test_no_cpuid := build/os-$(arch)-test-no-cpuid.iso
kernel_test_disable_simd := build/kernel-$(arch)-test-disable-simd.bin
iso_test_disable_simd := build/os-$(arch)-test-disable-simd.iso
test_variant_isos := \
	$(iso_test_bad_string) \
	$(iso_test_bad_memory) \
	$(iso_test_dirty_bss) \
	$(iso_test_bad_layout) \
	$(iso_test_no_cpuid) \
	$(iso_test_disable_simd)
section_rejection_cases := text-missing text-wrong-type rodata-missing rodata-wrong-type data-missing data-wrong-type bss-missing bss-wrong-type
layout_rejection_cases := bss-before-kernel bss-end-before-bss-start kernel-end-before-bss-end
freestanding_rejection_cases := interp-pt-interp-present dynamic-section-present unresolved-external-symbol host-runtime-marker-strings
section_rejection_stamps := $(addprefix build/rejections/section-$(arch)-,$(addsuffix .stamp,$(section_rejection_cases)))
layout_rejection_stamps := $(addprefix build/rejections/layout-$(arch)-,$(addsuffix .stamp,$(layout_rejection_cases)))
freestanding_rejection_stamps := $(addprefix build/rejections/freestanding-$(arch)-,$(addsuffix .stamp,$(freestanding_rejection_cases)))
reproducible_build_cases := release-artifacts-match-across-clean-rebuilds release-artifacts-match-across-workdirs
reproducible_build_stamps := $(addprefix build/reproducible/$(arch)-,$(addsuffix .stamp,$(reproducible_build_cases)))
negative_test_stamps := $(section_rejection_stamps) $(layout_rejection_stamps) $(freestanding_rejection_stamps)
test_proof_stamps := $(negative_test_stamps) $(reproducible_build_stamps)

linker_script := src/arch/$(arch)/linker.ld
grub_cfg := src/arch/$(arch)/grub.cfg
assembly_source_files := $(wildcard src/arch/$(arch)/*.asm)
assembly_object_files := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/%.o, $(assembly_source_files))
assembly_object_files_test := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/test/%.o, $(assembly_source_files))

rust_target := i586-unknown-linux-gnu
rust_source_files := src/main.rs
rust_object_files := build/arch/$(arch)/rust/kernel.o
rust_output_dir := build/arch/$(arch)/rust
rust_object_files_compact := build/arch/$(arch)/rust-compact40x10/kernel.o
rust_output_dir_compact := build/arch/$(arch)/rust-compact40x10
kernel_keepglobals := scripts/architecture-tests/fixtures/exports.$(arch).keepglobals

KFS_TEST_FORCE_FAIL ?= 0
KFS_TEST_DIRTY_BSS ?= 0
KFS_TEST_BAD_LAYOUT ?= 0
KFS_TEST_BAD_STRING ?= 0
KFS_TEST_BAD_MEMORY ?= 0
KFS_TEST_NO_CPUID ?= 0
KFS_TEST_DISABLE_SIMD ?= 0
KFS_SCREEN_GEOMETRY_PRESET ?= vga80x25
KFS_SKIP_LINT ?= 0
KFS_INSIDE_CONTAINER ?= 0
KFS_CONTAINER_ENGINE ?=
KFS_VERBOSE ?= 0
toolchain_image := kfs1-dev:latest
toolchain_containerfile := Dockerfile
toolchain_workdir := /work

container_engine := $(if $(KFS_CONTAINER_ENGINE),$(KFS_CONTAINER_ENGINE),$(shell if command -v podman >/dev/null 2>&1; then printf podman; elif command -v docker >/dev/null 2>&1; then printf docker; fi))
selinux_enforcing := $(shell if [ -r /sys/fs/selinux/enforce ] && [ "$$(cat /sys/fs/selinux/enforce)" = "1" ]; then printf 1; else printf 0; fi)
docker_rootless := $(shell if [ "$(container_engine)" = "docker" ] && docker info --format '{{join .SecurityOptions "\n"}}' 2>/dev/null | grep -q '^name=rootless$$'; then printf 1; else printf 0; fi)
container_mount := $(CURDIR):$(toolchain_workdir)$(if $(filter podman,$(container_engine)),:z,$(if $(and $(filter docker,$(container_engine)),$(filter 1,$(selinux_enforcing))),:z,))
container_user_args := $(if $(filter podman,$(container_engine)),--userns=keep-id,$(if $(and $(filter docker,$(container_engine)),$(filter 0,$(docker_rootless))),--user $(shell id -u):$(shell id -g),))
compile_curdir := $(if $(filter 1,$(KFS_INSIDE_CONTAINER)),$(CURDIR),$(toolchain_workdir))

RUST_CFG_FLAGS = $(if $(filter compact40x10,$(KFS_SCREEN_GEOMETRY_PRESET)),--cfg kfs_geometry_preset_compact40x10)
RUST_CODEGEN_FLAGS :=
RUST_CODEGEN_FLAGS += --remap-path-prefix $(compile_curdir)=.

TEST_ASM_DEFS = -DKFS_TEST=1 \
	$(if $(filter 1,$(KFS_TEST_FORCE_FAIL)),-DKFS_TEST_FORCE_FAIL=1) \
	$(if $(filter 1,$(KFS_TEST_DIRTY_BSS)),-DKFS_TEST_DIRTY_BSS=1) \
	$(if $(filter 1,$(KFS_TEST_BAD_LAYOUT)),-DKFS_TEST_BAD_LAYOUT=1) \
	$(if $(filter 1,$(KFS_TEST_BAD_STRING)),-DKFS_TEST_BAD_STRING=1) \
	$(if $(filter 1,$(KFS_TEST_BAD_MEMORY)),-DKFS_TEST_BAD_MEMORY=1) \
	$(if $(filter 1,$(KFS_TEST_NO_CPUID)),-DKFS_TEST_NO_CPUID=1) \
	$(if $(filter 1,$(KFS_TEST_DISABLE_SIMD)),-DKFS_TEST_DISABLE_SIMD=1)

TEST_TIMEOUT_SECS ?= 10
TEST_PASS_RC ?= 33
TEST_FAIL_RC ?= 35
test_ui_venv := .venv-test-ui
test_ui_python := $(if $(wildcard $(test_ui_venv)/bin/python),$(test_ui_venv)/bin/python,$(PYTHON))
lint_script := scripts/lint.sh
lint_required_tools := bash python3 rg rustfmt rustc shellcheck shfmt black ruff

define package_iso_rule
	$(Q)mkdir -p build/isofiles/boot/grub
	$(Q)cp $1 build/isofiles/boot/kernel.bin
	$(Q)cp $(grub_cfg) build/isofiles/boot/grub
	$(Q)find build/isofiles -exec touch -d "@$(source_date_epoch)" {} +
	$(Q)$(call toolchain_exec,grub-mkrescue \
		--modification-date=$(xorriso_date) \
		-o $2 build/isofiles -- \
		-volume_date all_file_dates $(xorriso_date) \
		-iso_nowtime $(xorriso_date) \
		-boot_image any gpt_disk_guid=volume_date_uuid \
		2> /dev/null)
	$(Q)rm -rf build/isofiles
endef

define define_test_variant
kernel_test_$(1)_objects := $(patsubst src/arch/$(arch)/%.asm,build/arch/$(arch)/test-$(2)/%.o,$(assembly_source_files))

$$(kernel_test_$(1)_objects) $$(kernel_test_$(1)) $$(iso_test_$(1)): $(3)

$$(kernel_test_$(1)): $$(kernel_test_$(1)_objects) $(rust_object_files) $(linker_script) | container-image
	$$(call announce_step,LINK-TEST,link test assembly and Rust objects into the final test kernel binary,rule: test assembly objects + $(rust_object_files) -> $$@ using ld in Docker)
	$$(Q)$$(call toolchain_exec,ld -m elf_i386 -n -T $(linker_script) -o $$@ $$(kernel_test_$(1)_objects) $(rust_object_files))
	$$(call announce_step,OBJCOPY,trim the final test kernel to the allowed exported global symbols,rule: keep symbols listed in $(kernel_keepglobals) inside $$@)
	$$(Q)$$(call toolchain_exec,objcopy --keep-global-symbols=$(kernel_keepglobals) $$@)

$$(iso_test_$(1)): $$(kernel_test_$(1)) $(grub_cfg) | container-image
	$$(call announce_step,ISO-TEST,package the test kernel and GRUB config into a bootable ISO,rule: $$< + $(grub_cfg) -> $$@ using grub-mkrescue in Docker)
	$$(call package_iso_rule,$$(kernel_test_$(1)),$$(iso_test_$(1)))

build/arch/$(arch)/test-$(2)/%.o: src/arch/$(arch)/%.asm | container-image
	$$(call announce_step,ASM-TEST,assemble one test assembly source file into one ELF32 object file,rule: $$< -> $$@ using nasm in Docker)
	$$(Q)mkdir -p $$(dir $$@)
	$$(Q)$$(call toolchain_exec,nasm -felf32 $$(TEST_ASM_DEFS) $$< -o $$@)
endef

define toolchain_exec
$(if $(filter 1,$(KFS_INSIDE_CONTAINER)),env $(repro_env) $1,$(container_engine) run --rm -e LC_ALL=C -e LANG=C -e TZ=UTC -e SOURCE_DATE_EPOCH=$(source_date_epoch) -v $(container_mount) -w $(toolchain_workdir) $(container_user_args) $(toolchain_image) $1)
endef

container_tty_args := $(if $(filter 1 true yes,$(KFS_CONTAINER_TTY)),-t,$(if $(filter 0 false no,$(KFS_CONTAINER_TTY)),,$(if $(shell [ -t 1 ] && printf 1),-t,)))
container_stdin_args := $(if $(filter 1 true yes,$(KFS_CONTAINER_STDIN)),-i,$(if $(filter 0 false no,$(KFS_CONTAINER_STDIN)),,$(if $(shell [ -t 0 ] && printf 1),-i,)))
container_interactive_args := $(strip $(container_stdin_args) $(container_tty_args))
container_kvm_args := $(if $(and $(filter 1,$(KFS_USE_KVM)),$(shell [ -e /dev/kvm ] && printf 1)),--device /dev/kvm,)
gui_security_args := $(if $(or $(filter podman,$(container_engine)),$(and $(filter docker,$(container_engine)),$(filter 1,$(selinux_enforcing)))),--security-opt label=disable,)
gui_xauth_host := $(if $(and $(XAUTHORITY),$(wildcard $(XAUTHORITY))),$(XAUTHORITY),)
gui_xauth_container := /tmp/kfs-host.xauth

Q := $(if $(filter 1,$(KFS_VERBOSE)),,@)

define announce_step
	@label="$(1)"; \
	summary="$(2)"; \
	detail="$(3)"; \
	if [ -t 1 ] && [ -z "$$NO_COLOR" ]; then \
		case "$$label" in \
			ASM|ASM-TEST) color='36' ;; \
			RUST) color='33' ;; \
			LINK|LINK-TEST) color='35' ;; \
			OBJCOPY) color='32' ;; \
			ISO|ISO-TEST|IMG|IMG-TEST) color='34' ;; \
			RUN-ISO|RUN-UI) color='1;37' ;; \
			*) color='1' ;; \
		esac; \
		printf '\033[%sm%-10s\033[0m %s\n' "$$color" "$$label" "$$summary"; \
		if [ -n "$$detail" ]; then \
			printf '           \033[2m%s\033[0m\n' "$$detail"; \
		fi; \
	else \
		printf '%-10s %s\n' "$$label" "$$summary"; \
		if [ -n "$$detail" ]; then \
			printf '           %s\n' "$$detail"; \
		fi; \
	fi
endef

.SECONDEXPANSION:
.PHONY: FORCE
FORCE:

.PHONY: all clean run run-iso iso \
	container-image container-image-force container-shell container-env-check \
	container-all container-iso container-run container-qemu-smoke \
	container-bootstrap container-smoke \
	metrics-sync \
	lint test test-plain test-ui test-ui-demo test-ui-bootstrap \
	dev iso-in-container run-in-container \
	run-ui run-ui-compact \
	iso-test test-artifacts test-prep test-host test-qemu test-vga reproducible-builds \
	img img-test run-img host-rust-test

all: $(kernel)

clean:
	@if [ -d build ]; then \
		find build -mindepth 1 -maxdepth 1 \
			! -name 'os-*.iso' \
			! -name 'os-*.img' \
			-exec rm -rf {} +; \
	fi

run: $(iso)
	$(call announce_step,RUN-ISO,boot the ISO in QEMU,artifact: $(iso))
	@qemu-system-i386 -cdrom $(iso)

run-iso:
	$(call announce_step,RUN-ISO,boot an existing ISO in QEMU,artifact: $(iso))
	@test -r "$(iso)" || { \
		echo "error: missing ISO: $(iso) (build it first with 'make iso' or use 'make run')" >&2; \
		exit 1; \
	}
	@qemu-system-i386 -cdrom $(iso)

## Manual visual-proof entrypoints.
## - run-ui: normal 80x25 UI
## - run-ui-compact: compact 40x10 UI
run-ui: KFS_SCREEN_GEOMETRY_PRESET := vga80x25
run-ui: KFS_FORCE_REBUILD := 1
run-ui: $(img)
	$(call announce_step,RUN-UI,boot the IMG in the manual UI viewer,artifact: $(img))
	@if command -v qemu-system-i386 >/dev/null 2>&1; then \
		KFS_SCREEN_GEOMETRY_PRESET=$(KFS_SCREEN_GEOMETRY_PRESET) \
			bash scripts/run-ui.sh $(arch); \
	else \
		if [ -z "$(container_engine)" ]; then \
			echo "error: no container engine found (install podman or docker)" >&2; \
			exit 1; \
		fi; \
		if ! $(container_engine) image inspect "$(ui_runner_image)" >/dev/null 2>&1; then \
			echo "container: building image $(ui_runner_image) (engine=$(container_engine))"; \
			$(container_engine) build -t "$(ui_runner_image)" -f "$(ui_runner_containerfile)" .; \
		fi; \
		test -n "$$DISPLAY" || { echo "error: DISPLAY is not set; cannot launch GUI command" >&2; exit 1; }; \
		test -d /tmp/.X11-unix || { echo "error: /tmp/.X11-unix is missing; cannot mount X11 socket" >&2; exit 1; }; \
		KFS_SCREEN_GEOMETRY_PRESET=$(KFS_SCREEN_GEOMETRY_PRESET) \
			$(container_engine) run --rm $(container_tty_args) $(gui_security_args) \
				-e KFS_INSIDE_CONTAINER=1 \
				-e DISPLAY="$$DISPLAY" \
				$(if $(gui_xauth_host),-e XAUTHORITY=$(gui_xauth_container),) \
				-v /tmp/.X11-unix:/tmp/.X11-unix \
				$(if $(gui_xauth_host),-v $(gui_xauth_host):$(gui_xauth_container):ro,) \
				-v $(container_mount) -w $(toolchain_workdir) \
				$(container_user_args) $(container_kvm_args) \
				"$(ui_runner_image)" bash scripts/run-ui.sh $(arch); \
	fi

run-ui-compact: KFS_SCREEN_GEOMETRY_PRESET := compact40x10
run-ui-compact:
	@KFS_SCREEN_GEOMETRY_PRESET=compact40x10 $(MAKE) --no-print-directory run-ui arch=$(arch)

iso: $(iso)

run-img: $(img)
	@qemu-system-i386 -drive format=raw,file=$(img)

img: $(img)

test-artifacts: $(img) $(img_test) $(iso_compact) $(test_variant_isos) $(test_proof_stamps)

reproducible-builds: $(reproducible_build_stamps)

test-prep: container-image container-env-check test-artifacts

$(img): $(iso) $$(if $$(filter 1,$$(KFS_FORCE_REBUILD)),FORCE,)
	$(call announce_step,IMG,copy the ISO bytes into the IMG artifact,rule: $(iso) -> $(img))
	$(Q)cp $(iso) $(img)

$(iso): $(kernel) $(grub_cfg) $$(if $$(filter 1,$$(KFS_FORCE_REBUILD)),FORCE,) | container-image
	$(call announce_step,ISO,package the kernel and GRUB config into a bootable ISO,rule: $(kernel) + $(grub_cfg) -> $(iso) using grub-mkrescue in Docker)
	$(call package_iso_rule,$(kernel),$(iso))

$(kernel): $(assembly_object_files) $(rust_object_files) $(linker_script) $$(if $$(filter 1,$$(KFS_FORCE_REBUILD)),FORCE,) | container-image
	$(call announce_step,LINK,link all assembly and Rust objects into the final kernel binary,rule: assembly objects + $(rust_object_files) -> $(kernel) using ld in Docker)
	$(Q)$(call toolchain_exec,ld -m elf_i386 -n -T $(linker_script) -o $(kernel) $(assembly_object_files) $(rust_object_files))
	$(call announce_step,OBJCOPY,trim the final kernel to the allowed exported global symbols,rule: keep symbols listed in $(kernel_keepglobals) inside $(kernel))
	$(Q)$(call toolchain_exec,objcopy --keep-global-symbols=$(kernel_keepglobals) $(kernel))
	@KFS_M3_2_KERNEL="$(kernel)" bash scripts/tests/kernel-sections.sh $(arch)

# compile assembly files
build/arch/$(arch)/%.o: src/arch/$(arch)/%.asm $$(if $$(filter 1,$$(KFS_FORCE_REBUILD)),FORCE,) | container-image
	$(call announce_step,ASM,assemble one assembly source file into one ELF32 object file,rule: $< -> $@ using nasm in Docker)
	$(Q)mkdir -p $(dir $@)
	$(Q)$(call toolchain_exec,nasm -felf32 $< -o $@)

$(rust_output_dir_compact):
	@mkdir -p $@

$(rust_object_files_compact): KFS_SCREEN_GEOMETRY_PRESET := compact40x10
$(rust_object_files_compact): src/main.rs | $(rust_output_dir_compact) container-image
	$(call announce_step,RUST,compile the freestanding Rust kernel crate into one object file,rule: $< -> $@ using rustc in Docker)
	$(Q)$(call toolchain_exec,rustc \
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
		$<)

$(kernel_compact): KFS_SCREEN_GEOMETRY_PRESET := compact40x10
$(iso_compact): KFS_SCREEN_GEOMETRY_PRESET := compact40x10

$(kernel_compact): $(assembly_object_files) $(rust_object_files_compact) $(linker_script) | container-image
	$(call announce_step,LINK,link all assembly and Rust objects into the final kernel binary,rule: assembly objects + $(rust_object_files_compact) -> $(kernel_compact) using ld in Docker)
	$(Q)$(call toolchain_exec,ld -m elf_i386 -n -T $(linker_script) -o $(kernel_compact) $(assembly_object_files) $(rust_object_files_compact))
	$(call announce_step,OBJCOPY,trim the final kernel to the allowed exported global symbols,rule: keep symbols listed in $(kernel_keepglobals) inside $(kernel_compact))
	$(Q)$(call toolchain_exec,objcopy --keep-global-symbols=$(kernel_keepglobals) $(kernel_compact))

$(iso_compact): $(kernel_compact) $(grub_cfg) | container-image
	$(call announce_step,ISO,package the kernel and GRUB config into a bootable ISO,rule: $(kernel_compact) + $(grub_cfg) -> $(iso_compact) using grub-mkrescue in Docker)
	$(call package_iso_rule,$(kernel_compact),$(iso_compact))

iso-test: $(iso_test)

img-test: $(img_test)

$(img_test): $(iso_test)
	$(call announce_step,IMG-TEST,copy the test ISO bytes into the test IMG artifact,rule: $(iso_test) -> $(img_test))
	$(Q)cp $(iso_test) $(img_test)

$(iso_test): $(kernel_test) $(grub_cfg) | container-image
	$(call announce_step,ISO-TEST,package the test kernel and GRUB config into a bootable ISO,rule: $(kernel_test) + $(grub_cfg) -> $(iso_test) using grub-mkrescue in Docker)
	$(call package_iso_rule,$(kernel_test),$(iso_test))

$(kernel_test): $(assembly_object_files_test) $(rust_object_files) $(linker_script) | container-image
	$(call announce_step,LINK-TEST,link test assembly and Rust objects into the final test kernel binary,rule: test assembly objects + $(rust_object_files) -> $(kernel_test) using ld in Docker)
	$(Q)$(call toolchain_exec,ld -m elf_i386 -n -T $(linker_script) -o $(kernel_test) $(assembly_object_files_test) $(rust_object_files))
	$(call announce_step,OBJCOPY,trim the final test kernel to the allowed exported global symbols,rule: keep symbols listed in $(kernel_keepglobals) inside $(kernel_test))
	$(Q)$(call toolchain_exec,objcopy --keep-global-symbols=$(kernel_keepglobals) $(kernel_test))
	@KFS_M3_2_KERNEL="$(kernel_test)" bash scripts/tests/kernel-sections.sh $(arch)

build/arch/$(arch)/test/%.o: src/arch/$(arch)/%.asm | container-image
	$(call announce_step,ASM-TEST,assemble one test assembly source file into one ELF32 object file,rule: $< -> $@ using nasm in Docker)
	$(Q)mkdir -p $(dir $@)
	$(Q)$(call toolchain_exec,nasm -felf32 $(TEST_ASM_DEFS) $< -o $@)

$(eval $(call define_test_variant,bad_string,bad-string,KFS_TEST_BAD_STRING := 1))
$(eval $(call define_test_variant,bad_memory,bad-memory,KFS_TEST_BAD_MEMORY := 1))
$(eval $(call define_test_variant,dirty_bss,dirty-bss,KFS_TEST_DIRTY_BSS := 1))
$(eval $(call define_test_variant,bad_layout,bad-layout,KFS_TEST_BAD_LAYOUT := 1))
$(eval $(call define_test_variant,no_cpuid,no-cpuid,KFS_TEST_NO_CPUID := 1))
$(eval $(call define_test_variant,disable_simd,disable-simd,KFS_TEST_DISABLE_SIMD := 1))

$(rust_output_dir):
	@mkdir -p $@

build/arch/$(arch)/rust/kernel.o: src/main.rs $$(if $$(filter 1,$$(KFS_FORCE_REBUILD)),FORCE,) | $(rust_output_dir) container-image
	$(call announce_step,RUST,compile the freestanding Rust kernel crate into one object file,rule: $< -> $@ using rustc in Docker)
	$(Q)$(call toolchain_exec,rustc \
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
		$<)

container-image:
	@if [ "$(KFS_INSIDE_CONTAINER)" = "1" ]; then \
		true; \
	elif [ -z "$(container_engine)" ]; then \
		echo "error: no container engine found (install podman or docker)" >&2; \
		exit 1; \
	elif [ "$(KFS_FORCE_IMAGE_BUILD)" != "1" ] && $(container_engine) image inspect "$(toolchain_image)" >/dev/null 2>&1; then \
		true; \
	else \
		echo "container: building image $(toolchain_image) (engine=$(container_engine))"; \
		$(container_engine) build -t "$(toolchain_image)" -f "$(toolchain_containerfile)" .; \
	fi

container-image-force:
	@KFS_FORCE_IMAGE_BUILD=1 $(MAKE) --no-print-directory container-image

container-shell: container-image
	@$(container_engine) run --rm -it \
		-v $(container_mount) -w $(toolchain_workdir) \
		$(container_user_args) $(container_kvm_args) \
		"$(toolchain_image)" bash

container-env-check: container-image
	@if [ "$(KFS_INSIDE_CONTAINER)" = "1" ]; then \
		bash scripts/dev-env.sh check; \
	else \
		$(container_engine) run --rm -v $(container_mount) -w $(toolchain_workdir) $(container_user_args) $(toolchain_image) bash scripts/dev-env.sh check; \
	fi

container-all: all
	@true

container-iso: iso
	@true

container-run: run
	@true

container-qemu-smoke: container-iso
	@$(container_engine) run --rm $(container_tty_args) \
		-e KFS_INSIDE_CONTAINER=1 \
		-e KFS_USE_KVM=$(KFS_USE_KVM) \
		-v $(container_mount) -w $(toolchain_workdir) \
		$(container_user_args) $(container_kvm_args) \
		"$(toolchain_image)" bash -lc 'bash scripts/qemu-smoke.sh $(arch)'

container-bootstrap: container-env-check
	@true

container-smoke: container-env-check container-qemu-smoke
	@true

test-qemu: $(img_test) container-image
	@$(container_engine) run --rm -t \
		-e KFS_INSIDE_CONTAINER=1 \
		TEST_TIMEOUT_SECS=$(TEST_TIMEOUT_SECS) \
		TEST_PASS_RC=$(TEST_PASS_RC) \
		TEST_FAIL_RC=$(TEST_FAIL_RC) \
		KFS_TEST_FORCE_FAIL=$(KFS_TEST_FORCE_FAIL) \
		KFS_TEST_BAD_STRING=$(KFS_TEST_BAD_STRING) \
		KFS_TEST_BAD_MEMORY=$(KFS_TEST_BAD_MEMORY) \
		-v $(container_mount) -w $(toolchain_workdir) \
		$(container_user_args) $(container_kvm_args) \
		"$(toolchain_image)" \
		bash scripts/boot-tests/qemu-boot.sh $(arch)

test-host: test-prep
	@KFS_RUN_LINT=0 bash scripts/test-host.sh $(arch)

test-vga: $(iso) container-image
	@$(container_engine) run --rm -t \
		-e KFS_INSIDE_CONTAINER=1 \
		TEST_TIMEOUT_SECS=$(TEST_TIMEOUT_SECS) \
		-v $(container_mount) -w $(toolchain_workdir) \
		$(container_user_args) $(container_kvm_args) \
		"$(toolchain_image)" \
		bash scripts/boot-tests/vga-memory.sh $(arch)

test: test-prep
	@bash -lc 'set -euo pipefail; \
		mode="$${KFS_TEST_UI:-auto}"; \
		run_lint="$${KFS_SKIP_LINT:-0}"; \
		if [[ "$${run_lint}" == "1" ]]; then \
			run_lint=0; \
		else \
			run_lint=1; \
		fi; \
		if [[ "$${run_lint}" == "1" ]]; then \
			$(MAKE) --no-print-directory lint arch=$(arch); \
		fi; \
		if [[ "$${mode}" == "0" ]] || [[ -n "$${CI:-}" ]] || [[ -n "$${GITHUB_ACTIONS:-}" ]] || [[ ! -t 1 ]]; then \
			exec env KFS_RUN_LINT=0 bash scripts/test-host.sh $(arch); \
		fi; \
		if "$(test_ui_python)" -c "import textual" >/dev/null 2>&1; then \
			exec env KFS_RUN_LINT=0 "$(test_ui_python)" scripts/kfs_tui.py --arch "$(arch)" --make-target test-host; \
		fi; \
		if $(container_engine) run --rm -e KFS_INSIDE_CONTAINER=1 -v $(container_mount) -w $(toolchain_workdir) $(container_user_args) "$(toolchain_image)" python3 -c "import textual" >/dev/null 2>&1; then \
			exec $(container_engine) run --rm $(container_interactive_args) \
				-e KFS_INSIDE_CONTAINER=1 \
				-e KFS_RUN_LINT=0 \
				$(if $(TERM),-e TERM="$(TERM)",) \
				-v $(container_mount) -w $(toolchain_workdir) \
				$(container_user_args) \
				"$(toolchain_image)" \
				python3 scripts/kfs_tui.py --arch "$(arch)" --make-target test-host; \
		fi; \
		if [[ "$${mode}" == "1" ]]; then \
			echo "error: Textual is not installed on the host or in the toolchain image. Run '\''make test-ui-bootstrap'\'' or rebuild the image." >&2; \
			exit 2; \
		fi; \
		echo "warn: Textual UI dependencies missing on the host and in the toolchain image; falling back to plain test output." >&2; \
		exec env KFS_RUN_LINT=0 bash scripts/test-host.sh $(arch)'

lint:
	@bash -lc 'set -euo pipefail; \
	if [ "$(KFS_INSIDE_CONTAINER)" = "1" ]; then \
		exec bash scripts/lint-runner.sh; \
	fi; \
	missing=0; \
	for tool in $(lint_required_tools); do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			missing=1; \
			break; \
		fi; \
	done; \
	if [ "$$missing" = "0" ]; then \
		exec bash scripts/lint-runner.sh; \
	fi; \
	if [ -z "$(container_engine)" ]; then \
		echo "error: missing lint tools on host and no container engine found" >&2; \
		exit 2; \
	fi; \
	exec $(container_engine) run --rm \
		-e KFS_INSIDE_CONTAINER=1 \
		-v $(container_mount) -w $(toolchain_workdir) \
		$(container_user_args) \
		"$(toolchain_image)" \
		bash scripts/lint-runner.sh'

host-rust-test: container-image
	@bash -lc 'set -euo pipefail; \
	test -n "$${KFS_HOST_LIB_SOURCE:-}" || { echo "error: KFS_HOST_LIB_SOURCE is required" >&2; exit 2; }; \
	test -n "$${KFS_HOST_TEST_SOURCE:-}" || { echo "error: KFS_HOST_TEST_SOURCE is required" >&2; exit 2; }; \
	test -n "$${KFS_HOST_TEST_BIN_NAME:-}" || { echo "error: KFS_HOST_TEST_BIN_NAME is required" >&2; exit 2; }; \
	exec $(container_engine) run --rm \
		-e KFS_INSIDE_CONTAINER=1 \
		-e KFS_HOST_LIB_SOURCE="$${KFS_HOST_LIB_SOURCE}" \
		-e KFS_HOST_TEST_SOURCE="$${KFS_HOST_TEST_SOURCE}" \
		-e KFS_HOST_TEST_BIN_NAME="$${KFS_HOST_TEST_BIN_NAME}" \
		-e KFS_HOST_TEST_FILTER="$${KFS_HOST_TEST_FILTER:-}" \
		-e KFS_HOST_LIB_RUSTC_FLAGS="$${KFS_HOST_LIB_RUSTC_FLAGS:-}" \
		-e KFS_HOST_TEST_RUSTC_FLAGS="$${KFS_HOST_TEST_RUSTC_FLAGS:-}" \
		-v $(container_mount) -w $(toolchain_workdir) \
		$(container_user_args) \
		"$(toolchain_image)" \
		bash -lc '\''set -euo pipefail; tmpdir="$$(mktemp -d)"; trap "rm -rf \"$$tmpdir\"" EXIT; rustc $${KFS_HOST_LIB_RUSTC_FLAGS:-} --crate-name kfs --crate-type rlib --edition=2021 -o "$$tmpdir/libkfs.rlib" "$${KFS_HOST_LIB_SOURCE}" >/dev/null; rustc --test $${KFS_HOST_TEST_RUSTC_FLAGS:-} --edition=2021 --extern kfs="$$tmpdir/libkfs.rlib" -o "$$tmpdir/$${KFS_HOST_TEST_BIN_NAME}" "$${KFS_HOST_TEST_SOURCE}" >/dev/null; if [[ -n "$${KFS_HOST_TEST_FILTER:-}" ]]; then "$$tmpdir/$${KFS_HOST_TEST_BIN_NAME}" "$${KFS_HOST_TEST_FILTER}"; else "$$tmpdir/$${KFS_HOST_TEST_BIN_NAME}"; fi'\'''

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

build/rejections/section-$(arch)-%.stamp: $(kernel) | container-image
	$(Q)mkdir -p build/rejections
	$(Q)case_name='$*'; \
	linker="build/rejections/section-$(arch)-$${case_name}.ld"; \
	kernel_out="build/rejections/section-$(arch)-$${case_name}.bin"; \
	log="build/rejections/section-$(arch)-$${case_name}.log"; \
	rm -f "$$linker" "$$kernel_out" "$$log" "$@"; \
	case "$$case_name" in \
		text-missing) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' \
			'  .rodata : { *(.text .text.*) *(.rodata .rodata.*) }' \
			'  .data : { *(.data .data.*) }' \
			'  .bss : { *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		text-wrong-type) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text (NOLOAD) : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) }' \
			'  .bss : { *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		rodata-missing) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) *(.rodata .rodata.*) }' \
			'  .data : { *(.data .data.*) }' '  .bss : { *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		rodata-wrong-type) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata (NOLOAD) : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) }' \
			'  .bss : { *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		data-missing) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) *(.data .data.*) }' '  .bss : { *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		data-wrong-type) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data (NOLOAD) : { *(.data .data.*) }' \
			'  .bss : { *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		bss-missing) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		bss-wrong-type) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) }' \
			'  .bss : { BYTE(0); *(.bss .bss.*) *(COMMON) }' \
			'  bss_start = .;' '  bss_end = .;' '  kernel_end = .;' '}' >"$$linker" ;; \
		*) echo "error: unknown section rejection case: $$case_name" >&2; exit 2 ;; \
	esac; \
	$(call toolchain_exec,ld -m elf_i386 -n -T "$$linker" -o "$$kernel_out" $(assembly_object_files) $(rust_object_files)) >"$$log" 2>&1; \
	$(call toolchain_exec,objcopy --keep-global-symbols=$(kernel_keepglobals) "$$kernel_out") >>"$$log" 2>&1; \
	set +e; KFS_M3_2_KERNEL="$$kernel_out" bash scripts/tests/kernel-sections.sh $(arch) >>"$$log" 2>&1; rc=$$?; set -e; \
	case "$$case_name" in \
		text-missing) expected='missing section .text' ;; \
		text-wrong-type) expected='.text exists but is not PROGBITS' ;; \
		rodata-missing) expected='missing section .rodata' ;; \
		rodata-wrong-type) expected='.rodata exists but is not PROGBITS' ;; \
		data-missing) expected='missing section .data' ;; \
		data-wrong-type) expected='.data exists but is not PROGBITS' ;; \
		bss-missing) expected='missing section .bss' ;; \
		bss-wrong-type) expected='.bss exists but is not NOBITS' ;; \
	esac; \
	if [ "$$rc" -eq 0 ]; then echo "FAIL $$case_name: rejection unexpectedly passed" >&2; cat "$$log" >&2; exit 1; fi; \
	grep -qF "$$expected" "$$log" || { echo "FAIL $$case_name: expected rejection message not found: $$expected" >&2; cat "$$log" >&2; exit 1; }; \
	touch "$@"

build/rejections/layout-$(arch)-%.stamp: $(kernel) | container-image
	$(Q)mkdir -p build/rejections
	$(Q)case_name='$*'; \
	linker="build/rejections/layout-$(arch)-$${case_name}.ld"; \
	log="build/rejections/layout-$(arch)-$${case_name}.log"; \
	rm -f "$$linker" "$$log" "$@"; \
	case "$$case_name" in \
		bss-before-kernel) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  bss_start = .;' '  kernel_start = . + 0x10;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) }' \
			'  .bss : { *(.bss .bss.*) *(COMMON) bss_end = .; }' '  kernel_end = .;' \
			'  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")' \
			'  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")' \
			'  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")' '}' >"$$linker" ;; \
		bss-end-before-bss-start) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) }' \
			'  .bss : { bss_end = .; *(.bss .bss.*) *(COMMON) bss_start = .; }' '  kernel_end = .;' \
			'  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")' \
			'  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")' \
			'  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")' '}' >"$$linker" ;; \
		kernel-end-before-bss-end) printf '%s\n' \
			'ENTRY(start)' 'SECTIONS {' '  . = 1M;' '  kernel_start = .;' \
			'  .boot : { *(.multiboot_header) }' '  .text : { *(.text .text.*) }' \
			'  .rodata : { *(.rodata .rodata.*) }' '  .data : { *(.data .data.*) }' \
			'  .bss : { bss_start = .; *(.bss .bss.*) *(COMMON) bss_end = .; }' '  kernel_end = bss_start;' \
			'  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")' \
			'  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")' \
			'  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")' '}' >"$$linker" ;; \
		*) echo "error: unknown layout rejection case: $$case_name" >&2; exit 2 ;; \
	esac; \
	set +e; $(call toolchain_exec,ld -m elf_i386 -n -T "$$linker" -o /tmp/unused-layout-$(arch)-$${case_name}.bin $(assembly_object_files) $(rust_object_files)) >"$$log" 2>&1; rc=$$?; set -e; \
	case "$$case_name" in \
		bss-before-kernel) expected='layout symbol order invalid: kernel_start > bss_start' ;; \
		bss-end-before-bss-start) expected='layout symbol order invalid: bss_start > bss_end' ;; \
		kernel-end-before-bss-end) expected='layout symbol order invalid: bss_end > kernel_end' ;; \
	esac; \
	if [ "$$rc" -eq 0 ]; then echo "FAIL $$case_name: rejection unexpectedly passed" >&2; cat "$$log" >&2; exit 1; fi; \
	grep -qF "$$expected" "$$log" || { echo "FAIL $$case_name: expected rejection message not found: $$expected" >&2; cat "$$log" >&2; exit 1; }; \
	touch "$@"

build/rejections/freestanding-$(arch)-%.stamp: $(kernel) | container-image
	$(Q)mkdir -p build/rejections
	$(Q)case_name='$*'; \
	asm_path="build/rejections/freestanding-$(arch)-$${case_name}.asm"; \
	obj_path="build/rejections/freestanding-$(arch)-$${case_name}.o"; \
	linker_path="build/rejections/freestanding-$(arch)-$${case_name}.ld"; \
	kernel_out="build/rejections/freestanding-$(arch)-$${case_name}.bin"; \
	log="build/rejections/freestanding-$(arch)-$${case_name}.log"; \
	rm -f "$$asm_path" "$$obj_path" "$$linker_path" "$$kernel_out" "$$log" "$@"; \
	case "$$case_name" in \
		interp-pt-interp-present) printf '%s\n' \
			'section .interp' \
			'  db "/lib/ld-linux.so.2", 0' >"$$asm_path"; \
			printf '%s\n' \
			'ENTRY(start)' \
			'PHDRS { interp PT_INTERP FLAGS(4); text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }' \
			'SECTIONS {' \
			'  . = 1M; kernel_start = .;' \
			'  .interp : { *(.interp) } :interp :text' \
			'  .boot : { *(.multiboot_header) } :text' \
			'  .text : { *(.text .text.*) } :text' \
			'  .rodata : { *(.rodata .rodata.*) } :text' \
			'  .data : { *(.data .data.*) } :data' \
			'  .bss : { bss_start = .; *(.bss .bss.*) *(COMMON) bss_end = .; } :data' \
			'  kernel_end = .;' \
			'  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")' \
			'  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")' \
			'  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")' \
			'}' >"$$linker_path"; \
			$(call toolchain_exec,nasm -felf32 "$$asm_path" -o "$$obj_path") >"$$log" 2>&1; \
			$(call toolchain_exec,ld -m elf_i386 -n -T "$$linker_path" -o "$$kernel_out" $(assembly_object_files) $(rust_object_files) "$$obj_path") >>"$$log" 2>&1; \
			run_gate() { gate_case="$$1"; expected="$$2"; gate_log="build/rejections/freestanding-$(arch)-$${case_name}-$${gate_case}.log"; set +e; KFS_M0_2_KERNEL="$$kernel_out" bash scripts/boot-tests/freestanding-kernel.sh $(arch) "$$gate_case" >"$$gate_log" 2>&1; gate_rc="$$?"; set -e; if [ "$$gate_rc" -eq 0 ]; then echo "FAIL $$case_name: gate $$gate_case unexpectedly passed" >&2; cat "$$gate_log" >&2; exit 1; fi; grep -qF "$$expected" "$$gate_log" || { echo "FAIL $$case_name: expected rejection message not found: $$expected" >&2; cat "$$gate_log" >&2; exit 1; }; }; \
			run_gate no-pt-interp-segment 'PT_INTERP present'; \
			run_gate no-interp-section '.interp section present' \
		;; \
		dynamic-section-present) printf '%s\n' \
			'section .dynamic' \
			'  dd 0' \
			'  dd 0' >"$$asm_path"; \
			printf '%s\n' \
			'ENTRY(start)' \
			'PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); dynamic PT_DYNAMIC FLAGS(6); }' \
			'SECTIONS {' \
			'  . = 1M; kernel_start = .;' \
			'  .boot : { *(.multiboot_header) } :text' \
			'  .text : { *(.text .text.*) } :text' \
			'  .rodata : { *(.rodata .rodata.*) } :text' \
			'  .data : { *(.data .data.*) } :data' \
			'  .dynamic : { *(.dynamic) } :data :dynamic' \
			'  .bss : { bss_start = .; *(.bss .bss.*) *(COMMON) bss_end = .; } :data' \
			'  kernel_end = .;' \
			'  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")' \
			'  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")' \
			'  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")' \
			'}' >"$$linker_path"; \
			$(call toolchain_exec,nasm -felf32 "$$asm_path" -o "$$obj_path") >"$$log" 2>&1; \
			$(call toolchain_exec,ld -m elf_i386 -n -T "$$linker_path" -o "$$kernel_out" $(assembly_object_files) $(rust_object_files) "$$obj_path") >>"$$log" 2>&1; \
			set +e; KFS_M0_2_KERNEL="$$kernel_out" bash scripts/boot-tests/freestanding-kernel.sh $(arch) no-dynamic-section >"$$log.gate" 2>&1; gate_rc="$$?"; set -e; \
			if [ "$$gate_rc" -eq 0 ]; then echo "FAIL $$case_name: gate no-dynamic-section unexpectedly passed" >&2; cat "$$log.gate" >&2; exit 1; fi; \
			grep -qF '.dynamic section present' "$$log.gate" || { echo "FAIL $$case_name: expected rejection message not found: .dynamic section present" >&2; cat "$$log.gate" >&2; exit 1; } \
		;; \
		unresolved-external-symbol) printf '%s\n' \
			'global kfs_bad_undefined_call' \
			'extern missing_host_symbol' \
			'section .text' \
			'kfs_bad_undefined_call:' \
			'  call missing_host_symbol' \
			'  ret' >"$$asm_path"; \
			$(call toolchain_exec,nasm -felf32 "$$asm_path" -o "$$obj_path") >"$$log" 2>&1; \
			set +e; $(call toolchain_exec,ld -m elf_i386 -n -T src/arch/i386/linker.ld -o "$$kernel_out" $(assembly_object_files) $(rust_object_files) "$$obj_path") >>"$$log" 2>&1; rc="$$?"; set -e; \
			if [ "$$rc" -eq 0 ]; then echo "FAIL $$case_name: link unexpectedly succeeded with an unresolved external symbol" >&2; cat "$$log" >&2; exit 1; fi; \
			grep -qE 'undefined reference to .*missing_host_symbol' "$$log" || { echo "FAIL $$case_name: expected undefined-reference message not found" >&2; cat "$$log" >&2; exit 1; } \
		;; \
		host-runtime-marker-strings) printf '%s\n' \
			'section .rodata' \
			'  db "glibc", 0' \
			'  db "libc.so.6", 0' \
			'  db "ld-linux.so.2", 0' >"$$asm_path"; \
			$(call toolchain_exec,nasm -felf32 "$$asm_path" -o "$$obj_path") >"$$log" 2>&1; \
			$(call toolchain_exec,ld -m elf_i386 -n -T src/arch/i386/linker.ld -o "$$kernel_out" $(assembly_object_files) $(rust_object_files) "$$obj_path") >>"$$log" 2>&1; \
			run_gate() { gate_case="$$1"; expected="$$2"; gate_log="build/rejections/freestanding-$(arch)-$${case_name}-$${gate_case}.log"; set +e; KFS_M0_2_KERNEL="$$kernel_out" bash scripts/boot-tests/freestanding-kernel.sh $(arch) "$$gate_case" >"$$gate_log" 2>&1; gate_rc="$$?"; set -e; if [ "$$gate_rc" -eq 0 ]; then echo "FAIL $$case_name: gate $$gate_case unexpectedly passed" >&2; cat "$$gate_log" >&2; exit 1; fi; grep -qF "$$expected" "$$gate_log" || { echo "FAIL $$case_name: expected rejection message not found: $$expected" >&2; cat "$$gate_log" >&2; exit 1; }; }; \
			run_gate no-libc-strings 'libc marker strings found'; \
			run_gate no-loader-strings 'loader marker strings found' \
		;; \
		*) echo "error: unknown freestanding rejection case: $$case_name" >&2; exit 2 ;; \
	esac; \
	touch "$@"

build/reproducible/$(arch)-%.stamp: $(img) | container-image
	$(Q)mkdir -p build/reproducible
	$(Q)case_name='$*'; \
	tmp_root="$$(mktemp -d -t kfs-repro-$(arch).XXXXXX)"; \
	left="$$tmp_root/left"; \
	right="$$tmp_root/right"; \
	cleanup() { rm -rf "$$tmp_root"; }; \
	trap cleanup EXIT INT TERM; \
	copy_workspace() { mkdir -p "$$1"; cp -a "$(CURDIR)/." "$$1/"; rm -rf "$$1/build" "$$1/.cache" "$$1/.tmp" "$$1/.history" "$$1/node_modules" "$$1/.venv-test-ui"; }; \
	build_img() { rm -rf "$$1/build"; $(MAKE) --no-print-directory -C "$$1" img arch=$(arch) KFS_CONTAINER_ENGINE=$(container_engine) >/dev/null; }; \
	compare_release_artifacts() { cmp -s "$$1/build/kernel-$(arch).bin" "$$2/build/kernel-$(arch).bin" && cmp -s "$$1/build/os-$(arch).iso" "$$2/build/os-$(arch).iso" && cmp -s "$$1/build/os-$(arch).img" "$$2/build/os-$(arch).img"; }; \
	case "$$case_name" in \
		release-artifacts-match-across-clean-rebuilds) \
			copy_workspace "$$left"; \
			build_img "$$left"; \
			mkdir -p "$$right/build"; \
			cp "$$left/build/kernel-$(arch).bin" "$$right/build/"; \
			cp "$$left/build/os-$(arch).iso" "$$right/build/"; \
			cp "$$left/build/os-$(arch).img" "$$right/build/"; \
			build_img "$$left"; \
			compare_release_artifacts "$$left" "$$right" || { echo "FAIL $$case_name: release artifacts differ across clean rebuilds" >&2; sha256sum "$$left/build/kernel-$(arch).bin" "$$right/build/kernel-$(arch).bin" "$$left/build/os-$(arch).iso" "$$right/build/os-$(arch).iso" "$$left/build/os-$(arch).img" "$$right/build/os-$(arch).img" >&2; exit 1; } \
		;; \
		release-artifacts-match-across-workdirs) \
			copy_workspace "$$left"; \
			copy_workspace "$$right"; \
			build_img "$$left"; \
			build_img "$$right"; \
			compare_release_artifacts "$$left" "$$right" || { echo "FAIL $$case_name: release artifacts differ across workdirs" >&2; sha256sum "$$left/build/kernel-$(arch).bin" "$$right/build/kernel-$(arch).bin" "$$left/build/os-$(arch).iso" "$$right/build/os-$(arch).iso" "$$left/build/os-$(arch).img" "$$right/build/os-$(arch).img" >&2; exit 1; } \
		;; \
		*) echo "error: unknown reproducible-build case: $$case_name" >&2; exit 2 ;; \
	esac; \
	touch "$@"
