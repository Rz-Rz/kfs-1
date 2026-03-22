global start
extern kmain

section .bss
align 16
stack_bottom:
    resb 16384
stack_top:

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
