arch ?= $(shell bash scripts/detect-arch.sh 2>/dev/null || echo x86_64)
kernel := build/kernel-$(arch).bin
iso := build/os-$(arch).iso

linker_script := src/arch/$(arch)/linker.ld
grub_cfg := src/arch/$(arch)/grub.cfg
assembly_source_files := $(wildcard src/arch/$(arch)/*.asm)
assembly_object_files := $(patsubst src/arch/$(arch)/%.asm, \
	build/arch/$(arch)/%.o, $(assembly_source_files))

.PHONY: all clean run iso \
	container-image container-shell container-env-check \
	container-all container-iso container-run container-qemu-smoke \
	container-bootstrap container-smoke \
	test dev iso-in-container run-in-container

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
	@nasm -felf64 $< -o $@

container-image:
	@bash scripts/container.sh build-image

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

test: container-smoke
	@true

dev: container-shell
	@true

iso-in-container: container-iso
	@true

run-in-container: container-run
	@true
