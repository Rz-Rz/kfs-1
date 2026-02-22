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
    mov dx, 0xf4
%ifdef KFS_TEST_FORCE_FAIL
    mov al, 0x11
%else
    mov al, 0x10
%endif
    out dx, al
.halt:
    hlt
    jmp .halt
%else
    call kmain
.halt:
    cli
    hlt
    jmp .halt
%endif
