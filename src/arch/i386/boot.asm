global start

section .text
bits 32
start:
%ifdef KFS_TEST
    mov dx, 0xf4
%ifdef KFS_TEST_FORCE_FAIL
    mov al, 0x11
%else
    mov al, 0x10
%endif
    out dx, al
    cli
.halt:
    hlt
    jmp .halt
%else
    ; print `OK` to screen
    mov dword [0xb8000], 0x2f4b2f4f
    hlt
%endif
