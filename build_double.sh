#! /bin/bash

set -e

riscv32-unknown-elf-as -march=rv32i tests/double.s -o double.o
riscv32-unknown-elf-ld -T riscv.ld double.o -o double.elf
riscv32-unknown-elf-objcopy -O binary double.elf double.bin
