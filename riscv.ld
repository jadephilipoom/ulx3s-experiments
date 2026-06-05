MEMORY
{
    imem (x)  : ORIGIN = 0, LENGTH = 64
    dmem (rw)  : ORIGIN = 64, LENGTH = 64
}
SECTIONS
{
    . = 0x0;
    .text : {
        _text_start = .;
        *(.text.start)
        *(.text*)
        _text_end = .;
    }
    .data : {
        _data_start = .;
        *(.data .data.*)
        _data_end = .;
    }
}
