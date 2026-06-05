.section .text.start

.global _start
_start:
  la  x4, input
  lw  x3, 0(x4)
  add x3, x3, x3
  sw  x3, 0(x4)
  ecall

.section .data

.balign 4
input:
  .word 0x01234567
