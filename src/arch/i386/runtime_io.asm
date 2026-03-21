global kfs_arch_is_test_mode
global kfs_arch_should_fail_bss
global kfs_arch_should_fail_layout
global kfs_arch_should_fail_string
global kfs_arch_should_fail_memory
global kfs_arch_qemu_exit
global kfs_arch_halt_forever

section .text
bits 32

kfs_arch_is_test_mode:
%ifdef KFS_TEST
    mov eax, 1
%else
    xor eax, eax
%endif
    ret

kfs_arch_should_fail_bss:
%ifdef KFS_TEST_DIRTY_BSS
    mov eax, 1
%else
    xor eax, eax
%endif
    ret

kfs_arch_should_fail_layout:
%ifdef KFS_TEST_BAD_LAYOUT
    mov eax, 1
%else
    xor eax, eax
%endif
    ret

kfs_arch_should_fail_string:
%ifdef KFS_TEST_BAD_STRING
    mov eax, 1
%else
    xor eax, eax
%endif
    ret

kfs_arch_should_fail_memory:
%ifdef KFS_TEST_BAD_MEMORY
    mov eax, 1
%else
    xor eax, eax
%endif
    ret

kfs_arch_qemu_exit:
    mov al, [esp + 4]
    mov dx, 0x00f4
    out dx, al
    jmp kfs_arch_halt_forever

kfs_arch_halt_forever:
    cli
.halt_loop:
    hlt
    jmp .halt_loop
