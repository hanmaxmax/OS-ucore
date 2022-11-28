#include <mmu.h>
#include <memlayout.h>

#define REALLOC(x) (x - KERNBASE)

# kern_entry函数的主要任务是为执行kern_init建立一个良好的C语言运
# 行环境（设置堆栈），而且临时建立了一个段映射关系，为之后建立分页
# 机制的过程做一个准备（细节在3.5小节有进一步阐述）。

.text
.globl kern_entry
kern_entry:
    # load pa of boot pgdir
    movl $REALLOC(__boot_pgdir), %eax
    movl %eax, %cr3 # 把页目录表的起始地址存入CR3寄存器中

    # enable paging
    movl %cr0, %eax
    orl $(CR0_PE | CR0_PG | CR0_AM | CR0_WP | CR0_NE | CR0_TS | CR0_EM | CR0_MP), %eax
    andl $~(CR0_TS | CR0_EM), %eax
    movl %eax, %cr0 # 把cr0中的CR0_PG标志位设置上

    # 执行完上面指令，计算机系统进入分页模式
    # 映射关系：
#      virt addr = linear addr = phy addr # 线性地址在0~4MB之内三者的映射关系
#      virt addr = linear addr = phy addr + 0xC0000000 # 线性地址在0xC0000000~0xC0000000+4MB之内三者的映射关系

# 指导书：此时的内核（EIP）还在0~4M的低虚拟地址区域（eip = 0x1.....）运行，而在之后，这个区域的虚拟内存是要给用户程序使用的。
# 为此，需要使用一个绝对跳转来使内核跳转到高虚拟地址：
    # update eip
    # now, eip = 0x1.....
    # （lea, load effective address,LEA指令的功能是取偏移地址， 指令形式是从存储器读数据到寄存器, 效果是将存储器的有效地址写入到目的操作数, 类似, C语言中的”&”.）
    leal next, %eax # kernel.sym符号表里：c010001e next
    # set eip = KERNBASE + 0x1.....
    # 为啥可以？？ 回来的时候会做映射？？
    # 去看kernel.asm 地址

    # 这个时候eip里面还是低虚拟地址，jmp主要是为了调整eip！这段代码是无害的
    jmp *%eax
next:
    # 跳转完毕后，通过把boot_pgdir[0]对应的第一个页目录表项（0~4MB）清零来取消了临时的页映射关系：
    # unmap va 0 ~ 4M, it's temporary mapping
    xorl %eax, %eax
    movl %eax, __boot_pgdir

    # set ebp, esp
    movl $0x0, %ebp
    # the kernel stack region is from bootstack -- bootstacktop,
    # the kernel stack size is KSTACKSIZE (8KB)defined in memlayout.h
    movl $bootstacktop, %esp
    # now kernel stack is ready , call the first C function
    call kern_init

# should never get here
spin:
    jmp spin

.data
.align PGSIZE
    .globl bootstack
bootstack:
    .space KSTACKSIZE
    .globl bootstacktop
bootstacktop:

# kernel builtin pgdir
# an initial page directory (Page Directory Table, PDT)
# These page directory table and page table can be reused!
.section .data.pgdir
.align PGSIZE
__boot_pgdir:
.globl __boot_pgdir
    # map va 0 ~ 4M to pa 0 ~ 4M (temporary)
    .long REALLOC(__boot_pt1) + (PTE_P | PTE_U | PTE_W)
    # #define PGSHIFT  12 // log2(PGSIZE)
    .space (KERNBASE >> PGSHIFT >> 10 << 2) - (. - __boot_pgdir) # pad to PDE of KERNBASE
    # map va KERNBASE + (0 ~ 4M) to pa 0 ~ 4M
    # memlayout中： #define KERNBASE  0xC0000000
    .long REALLOC(__boot_pt1) + (PTE_P | PTE_U | PTE_W)
    .space PGSIZE - (. - __boot_pgdir) # pad to PGSIZE

.set i, 0
__boot_pt1:
.rept 1024
    .long i * PGSIZE + (PTE_P | PTE_W)
    .set i, i + 1
.endr

