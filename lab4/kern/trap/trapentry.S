#include <memlayout.h>

# vectors.S sends all traps here.
.text
.globl __alltraps
__alltraps:
    # push registers to build a trap frame
    # therefore make the stack look like a struct trapframe
    pushl %ds
    pushl %es
    pushl %fs
    pushl %gs
    pushal

    # load GD_KDATA into %ds and %es to set up data segments for kernel
    movl $GD_KDATA, %eax
    movw %ax, %ds
    movw %ax, %es

    # push %esp to pass a pointer to the trapframe as an argument to trap()
    pushl %esp

    # call trap(tf), where tf=%esp
    call trap

    # pop the pushed stack pointer
    popl %esp

    # return falls through to trapret...
.globl __trapret
__trapret:
# 依次将前面设置好的临时trap_frame中断栈帧中的各个数据依次还原
    # restore registers from stack
    popal

    # restore %ds, %es, %fs and %gs
    popl %gs
    popl %fs
    popl %es
    popl %ds

    # get rid of the trap number and error code
    addl $0x8, %esp

    # 执行iret 完成中断返回
    iret
# 中断返回时，其cs、eip会依次从中断栈帧中还原，中断栈帧中eip是通过kern_thread中的语句
# （tf.tf_eip = (uint32_t)kernel_thread_entry; ），指向了kernel_thread_entry。
# 因此中断返回后会跳转到kernel_thread_entry函数入口处执行。


.globl forkrets
forkrets:
    # set stack to this new process's trapframe
    # 令栈顶指针指向了前面设置好的trap_frame首地址
    movl 4(%esp), %esp
    jmp __trapret
