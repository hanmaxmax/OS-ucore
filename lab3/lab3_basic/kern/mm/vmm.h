#ifndef __KERN_MM_VMM_H__
#define __KERN_MM_VMM_H__

#include <defs.h>
#include <list.h>
#include <memlayout.h>
#include <sync.h>

//pre define
struct mm_struct;

// the virtual continuous memory area(vma)
// 连续地址的虚拟内存空间
struct vma_struct {

    // vm_mm是一个指针，指向一个比vma_struct更高的抽象层次的数据结构mm_struct
    struct mm_struct *vm_mm; // the set of vma using the same PDT 

    // vm_start、vm_end这两个值都应该是PGSIZE 对齐的，
    // 而且描述的是一个合理的地址空间范围（即严格确保 vm_start < vm_end的关系）
    uintptr_t vm_start;      // 连续地址的虚拟内存空间的起始位置 
    uintptr_t vm_end;        // end addr of vma 结束位置 

    // 这个虚拟内存空间的属性（只读、可读写、可执行）
    uint32_t vm_flags;       // flags of vma 

    //list_link是一个双向链表，按照从小到大的顺序把一系列用vma_struct表示的虚拟内存空间链接起来，
    //并且还要求这些链起来的vma_struct应该是不相交的，即vma之间的地址空间无交集
    list_entry_t list_link;  // linear list link which sorted by start addr of vma
};

#define le2vma(le, member)                  \
    to_struct((le), struct vma_struct, member)

#define VM_READ                 0x00000001 //只读
#define VM_WRITE                0x00000002 //可读写
#define VM_EXEC                 0x00000004 //可执行

// 总的内存管理器，统一的管理一个进程的虚拟内存以及物理内存。
// the control struct for a set of vma using the same PDT
struct mm_struct {
    //mmap_list是双向链表头，链接了所有属于同一页目录表的虚拟内存空间
    list_entry_t mmap_list;        // linear list link which sorted by start addr of vma

    //mmap_cache是指向当前正在使用的虚拟内存空间，由于操作系统执行的“局部性”原理，
    // 当前正在用到的虚拟内存空间在接下来的操作中可能还会用到，这时就不需要查链表，
    // 而是直接使用此指针就可找到下一次要用到的虚拟内存空间。
    struct vma_struct *mmap_cache; // current accessed vma, used for speed purpose

    // pgdir 所指向的就是 mm_struct数据结构所维护的页表，
    // 通过访问pgdir可以查找某虚拟地址对应的页表项是否存在以及页表项的属性等。
    pde_t *pgdir;                  // the PDT of these vma

    // map_count记录mmap_list 里面链接的 vma_struct的个数
    int map_count;                 // the count of these vma

    //sm_priv指向用来链接记录页访问情况的链表头，这建立了mm_struct和后续要讲到的swap_manager之间的联系
    void *sm_priv;                   // the private data for swap manager
};

struct vma_struct *find_vma(struct mm_struct *mm, uintptr_t addr);
struct vma_struct *vma_create(uintptr_t vm_start, uintptr_t vm_end, uint32_t vm_flags);
void insert_vma_struct(struct mm_struct *mm, struct vma_struct *vma);

struct mm_struct *mm_create(void);
void mm_destroy(struct mm_struct *mm);

void vmm_init(void);

int do_pgfault(struct mm_struct *mm, uint32_t error_code, uintptr_t addr);

extern volatile unsigned int pgfault_num;
extern struct mm_struct *check_mm_struct;
#endif /* !__KERN_MM_VMM_H__ */

