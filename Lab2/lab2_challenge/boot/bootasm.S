#include <asm.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.set PROT_MODE_CSEG,        0x8                     # kernel code segment selector
.set PROT_MODE_DSEG,        0x10                    # kernel data segment selector
.set CR0_PE_ON,             0x1                     # protected mode enable flag
.set SMAP,                  0x534d4150

# start address should be 0:7c00, in real mode, the beginning address of the running bootloader
.globl start
start:
.code16                                             # Assemble for 16-bit mode
    cli                                             # Disable interrupts
    cld                                             # String operations increment

    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data Segment
    movw %ax, %es                                   # -> Extra Segment
    movw %ax, %ss                                   # -> Stack Segment

    # Enable A20:
    #  For backwards compatibility with the earliest PCs, physical
    #  address line 20 is tied low, so that addresses higher than
    #  1MB wrap around to zero by default. This code undoes this.
seta20.1:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.1

    movb $0xd1, %al                                 # 0xd1 -> port 0x64
    outb %al, $0x64                                 # 0xd1 means: write data to 8042's P2 port

seta20.2:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.2

    movb $0xdf, %al                                 # 0xdf -> port 0x60
    outb %al, $0x60                                 # 0xdf = 11011111, means set P2's A20 bit(the 1 bit) to 1
 
 # 内存探测：
 # 要获取所有的内存段的信息，probe_memory通过一个do_while循环来不断触发int 0x15中断来
 # 获取每个内存段的信息，并且将这些信息保存在一个数组中，即e820map.map
probe_memory:
    # 对0x8000处的32位单元清零,即给位于0x8000处的struct e820map的成员变量nr_map清零
    movl $0, 0x8000
    xorl %ebx, %ebx
    # 表示设置调用INT 15h BIOS中断后，BIOS返回的?映射地址描述符?e820map吗?的起始地址?
    # 0x8004处开始存放e820map中的map字段，存放每一个entry
    movw $0x8004, %di
start_probe:
    # INT 15的中断调用参数  

    # 设置功能码 E820h
    movl $0xE820, %eax 
    # 设置地址范围描述符的大小为20字节，其大小等于struct e820map的成员变量map的大小
    movl $20, %ecx 
    # 设置edx为534D4150h (即4个ASCII字符“SMAP”)，这是一个约定
    movl $SMAP, %edx 
    # 调用int 0x15中断，要求BIOS返回一个用地址范围描述符表示的内存段信息
    # 'SMAP' -BIOS将会使用此标志，对调用者将要请求的系统映象信息进行校验，这些信息会被BIOS放置到ES:DI所指向的结构中。

    int $0x15 
        	
    # 不进位表示没有错误，否则则存在错误。
    # 如果eflags的CF位为0，则表示还有内存段需要探测?
    # 如果eflags的CF位为0，说明探测成功，跳转至cont段执行
    jnc cont 
    
    # 探测有问题，结束探测
    # e820h中断失败，直接结束探测
    movw $12345, 0x8000 
    jmp finish_probe
cont:
    # 设置下一个 BIOS返回的映射地址描述符 20bytes自增 的起始地址
    addw $20, %di
    # 递增struct e820map的成员变量nr_map
    # e820map中的nr_map自增1
    incl 0x8000
    # 如果INT0x15返回的ebx为零，表示探测结束，否则继续探测
    # 0与中断响应后的ebx比较
    # (如果是第一次调用或内存区域扫描完毕，则ebx为0。 如果不是，则ebx存放上次调用之后的计数值)
    cmpl $0, %ebx
    # 是否还存在新的内存段需要探测
    jnz start_probe
finish_probe:

    # Switch from real to protected mode, using a bootstrap GDT
    # and segment translation that makes virtual addresses
    # identical to physical addresses, so that the
    # effective memory map does not change during the switch.
    lgdt gdtdesc
    movl %cr0, %eax
    orl $CR0_PE_ON, %eax
    movl %eax, %cr0

    # Jump to next instruction, but in 32-bit code segment.
    # Switches processor into 32-bit mode.
    ljmp $PROT_MODE_CSEG, $protcseg

.code32                                             # Assemble for 32-bit mode
protcseg:
    # Set up the protected-mode data segment registers
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    movw %ax, %fs                                   # -> FS
    movw %ax, %gs                                   # -> GS
    movw %ax, %ss                                   # -> SS: Stack Segment

    # Set up the stack pointer and call into C. The stack region is from 0--start(0x7c00)
    movl $0x0, %ebp
    movl $start, %esp
    call bootmain

    # If bootmain returns (it shouldn't), loop.
spin:
    jmp spin

.data
# Bootstrap GDT
.p2align 2                                          # force 4 byte alignment
gdt:
    SEG_NULLASM                                     # null seg
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # code seg for bootloader and kernel
    SEG_ASM(STA_W, 0x0, 0xffffffff)                 # data seg for bootloader and kernel

gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt                                       # address gdt
