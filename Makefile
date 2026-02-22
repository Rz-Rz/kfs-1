arch ?= i386
kernel := build/kernel-$(arch).bin
iso := build/os-$(arch).iso
kernel_test := build/kernel-$(arch)-test.bin
iso_test := build/os-$(arch)-test.iso

linker_script := src/arch/$(arch)/linker.ld
grub_cfg := src/arch/$(arch)/grub.cfg
assembly_source_files := $(wildcard src/arch/$(arch)/*.asm)
assembly_object_files := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/%.o, $(assembly_source_files))
assembly_object_files_test := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/test/%.o, $(assembly_source_files))

KFS_TEST_FORCE_FAIL ?= 0

TEST_ASM_DEFS := -DKFS_TEST=1
ifeq ($(KFS_TEST_FORCE_FAIL),1)
TEST_ASM_DEFS += -DKFS_TEST_FORCE_FAIL=1
endif

TEST_TIMEOUT_SECS ?= 10
TEST_PASS_RC ?= 33
TEST_FAIL_RC ?= 35

.PHONY: all clean run iso \
	container-image container-image-force container-shell container-env-check \
	container-all container-iso container-run container-qemu-smoke \
	container-bootstrap container-smoke \
	test dev iso-in-container run-in-container \
	iso-test test-qemu

all: $(kernel)

clean:
	@rm -r build

run: $(iso)
	@qemu-system-i386 -cdrom $(iso)

iso: $(iso)

$(iso): $(kernel) $(grub_cfg)
	@mkdir -p build/isofiles/boot/grub
	@cp $(kernel) build/isofiles/boot/kernel.bin
	@cp $(grub_cfg) build/isofiles/boot/grub
	@grub-mkrescue -o $(iso) build/isofiles 2> /dev/null
	@rm -r build/isofiles

$(kernel): $(assembly_object_files) $(linker_script)
	@ld -m elf_i386 -n -T $(linker_script) -o $(kernel) $(assembly_object_files)

# compile assembly files
build/arch/$(arch)/%.o: src/arch/$(arch)/%.asm
	@mkdir -p $(shell dirname $@)
	@nasm -felf32 $< -o $@

iso-test: $(iso_test)

$(iso_test): $(kernel_test) $(grub_cfg)
	@mkdir -p build/isofiles/boot/grub
	@cp $(kernel_test) build/isofiles/boot/kernel.bin
	@cp $(grub_cfg) build/isofiles/boot/grub
	@grub-mkrescue -o $(iso_test) build/isofiles 2> /dev/null
	@rm -r build/isofiles

$(kernel_test): $(assembly_object_files_test) $(linker_script)
	@ld -m elf_i386 -n -T $(linker_script) -o $(kernel_test) $(assembly_object_files_test)

build/arch/$(arch)/test/%.o: src/arch/$(arch)/%.asm
	@mkdir -p $(shell dirname $@)
	@nasm -felf32 $(TEST_ASM_DEFS) $< -o $@

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
		bash scripts/test-qemu.sh $(arch)

test:
	@bash scripts/test-host.sh $(arch)

dev: container-shell
	@true

iso-in-container: container-iso
	@true

run-in-container: container-run
	@true
