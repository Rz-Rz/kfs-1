ENTRY(start)

SECTIONS {
    . = 1M;
    kernel_start = .;

    .boot :
    {
        /* ensure that the multiboot header is at the beginning */
        *(.multiboot_header)
    }

    .text :
    {
        *(.text .text.*)
    }

    .rodata :
    {
        *(.rodata .rodata.*)
    }

    .data :
    {
        *(.data .data.*)
    }

    .bss :
    {
        bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        bss_end = .;
    }

    /DISCARD/ :
    {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.gcc_except_table .gcc_except_table.*)
    }

    kernel_end = .;

    ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")
    ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")
    ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")
}
