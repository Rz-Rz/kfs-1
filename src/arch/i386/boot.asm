global start
global kfs_test_mode
extern kmain
extern KFS_M4_BSS_CANARY
extern KFS_M4_LAYOUT_OVERRIDE
extern KFS_M5_STRING_OVERRIDE
extern KFS_M5_MEMORY_OVERRIDE

section .bss
align 16
stack_bottom:
    resb 16384
stack_top:

section .rodata
kfs_test_mode:
%ifdef KFS_TEST
    db 1
%else
    db 0
%endif

section .text
bits 32
start:
    cli
    cld
    mov esp, stack_top

%ifdef KFS_TEST
%ifdef KFS_TEST_FORCE_FAIL
    mov dx, 0xf4
    mov al, 0x11
    out dx, al
    jmp halt_loop
%else
%ifdef KFS_TEST_DIRTY_BSS
    mov dword [KFS_M4_BSS_CANARY], 1
%endif
%ifdef KFS_TEST_BAD_LAYOUT
    mov dword [KFS_M4_LAYOUT_OVERRIDE], 1
%endif
%ifdef KFS_TEST_BAD_STRING
    mov dword [KFS_M5_STRING_OVERRIDE], 1
%endif
%ifdef KFS_TEST_BAD_MEMORY
    mov dword [KFS_M5_MEMORY_OVERRIDE], 1
%endif
    call kmain
    jmp halt_loop
%endif
%else
    call kmain
%endif

halt_loop:
    cli
    hlt
    jmp halt_loop
