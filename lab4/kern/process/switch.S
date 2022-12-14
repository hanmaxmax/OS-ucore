.text
.globl switch_to
# switch_to是汇编实现的函数(子过程)，其参数是两个struct context结构体的指针。
# 第一个参数from代表着当前线程的上下文，第二个参数to代表着新线程的上下文，
# switch_to的功能就是保留current线程的上下文至from上下文结构中，
# 并将to上下文结构中的内容加载到CPU的各个寄存器中，恢复新线程的执行流上下文现场。
switch_to:                      # switch_to(from, to)

    # save from's registers
    # 令eax保存第一个参数from(context)的地址
    movl 4(%esp), %eax          # eax points to from
    # from.context 保存eip、esp等等寄存器的当前快照值
    popl 0(%eax)                # save eip !popl
    movl %esp, 4(%eax)
    movl %ebx, 8(%eax)
    movl %ecx, 12(%eax)
    movl %edx, 16(%eax)
    movl %esi, 20(%eax)
    movl %edi, 24(%eax)
    movl %ebp, 28(%eax)

    # restore to's registers
    # 令eax保存第二个参数next(context)的地址,因为之前popl了一次，所以4(%esp)目前指向第二个参数
    movl 4(%esp), %eax          # not 8(%esp): popped return address already
                                # eax now points to to
    # 恢复next.context中的各个寄存器的值
    movl 28(%eax), %ebp
    movl 24(%eax), %edi
    movl 20(%eax), %esi
    movl 16(%eax), %edx
    movl 12(%eax), %ecx
    movl 8(%eax), %ebx
    movl 4(%eax), %esp

    pushl 0(%eax)               # push eip
    # ret时栈上的eip为next(context)中设置的值(fork时，eip指向 forkret,esp指向分配好的trap_frame)
    # copy_thread函数中通过语句proc->context.eip = (uintptr_t)forkret处，
    # switch_to返回后将会跳转到forkret这一所有线程完成初始化后统一跳转的入口；
    # 在copy_thread中同时也设置了当前的栈顶指针esp指向proc->tf
    ret

