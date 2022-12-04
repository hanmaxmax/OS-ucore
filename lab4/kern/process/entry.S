.text
.globl kernel_thread_entry
kernel_thread_entry:        # void kernel_thread(void)
# edx和ebx都是在前面中断返回时通过__traprets的popal指令，
# 从init_proc创建时构造的临时中断栈帧中弹出的数据

# kern_thread中ebx保存的就是传入的fn，即init_main函数的地址，而edx则保存了arg参数，即"Hello world!!"字符串。
# 因此当init_proc执行到kernel_thread_entry时，实际上就是将参数"Hello world!!"地址压入了栈中，并且调用init_main函数，传入栈上参数"Hello world"的地址并将其打印在标准输出控制台上。
# 随后，init_main函数执行完毕并返回，保留了返回值eax的值之后，kernel_thread_entry简单的调用了do_exit函数，终止了init_proc当前线程。
    pushl %edx              # push arg
    call *%ebx              # call fn

    pushl %eax              # save the return value of fn(arg)
    call do_exit            # call do_exit to terminate current thread

