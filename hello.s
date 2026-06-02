.equ UART_BASE, 0x10000000

.section .text
.global _start

_start:
    li t0, UART_BASE

    la t1, hello_msg

print_loop:
    lb t2, 0(t1)

    beqz t2, end

    sb t2, 0(t0)

    addi t1, t1, 1

    j print_loop

end:
    j end

.section .rodata
hello_msg:
    .asciz "Hello World!\n"
