.section .text.start

.global _start
_start:
  add x3, x0, 0xff
  sw  x3, 0x40(x0)
  ecall

.section .data

.balign 4
input:
  .word 0x01234567
