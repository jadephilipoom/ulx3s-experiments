.section .text.start

.global _start
_start:
  lw  x3, 0x40(x0)
  add x3, x3, x3
  sw  x3, 0x40(x0)
  ecall

.section .data

.balign 4
input:
  .word 0x01234567
