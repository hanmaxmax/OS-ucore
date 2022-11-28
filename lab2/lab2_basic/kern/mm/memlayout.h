#ifndef __KERN_MM_MEMLAYOUT_H__
#define __KERN_MM_MEMLAYOUT_H__

/* This file contains the definitions for memory management in our OS. */
// 管理每个物理页的Page数据结构（在mm/memlayout.h中），
// 这个数据结构也是实现连续物理内存分配算法的关键数据结构，
// 可通过此数据结构来完成空闲块的链接和信息存储，
// 而基于这个数据结构的管理物理页数组起始地址就是全局变量pages，
// 具体初始化此数组的函数位于page_init函数中

/* global segment number */
#define SEG_KTEXT   1
#define SEG_KDATA   2
#define SEG_UTEXT   3
#define SEG_UDATA   4
#define SEG_TSS     5

/* global descrptor numbers */
#define GD_KTEXT    ((SEG_KTEXT) << 3)      // kernel text
#define GD_KDATA    ((SEG_KDATA) << 3)      // kernel data
#define GD_UTEXT    ((SEG_UTEXT) << 3)      // user text
#define GD_UDATA    ((SEG_UDATA) << 3)      // user data
#define GD_TSS      ((SEG_TSS) << 3)        // task segment selector

#define DPL_KERNEL  (0)
#define DPL_USER    (3)

#define KERNEL_CS   ((GD_KTEXT) | DPL_KERNEL)
#define KERNEL_DS   ((GD_KDATA) | DPL_KERNEL)
#define USER_CS     ((GD_UTEXT) | DPL_USER)
#define USER_DS     ((GD_UDATA) | DPL_USER)

/* *
 * Virtual memory map:                                          Permissions
 *                                                              kernel/user
 *
 *     4G ------------------> +---------------------------------+
 *                            |                                 |
 *                            |         Empty Memory (*)        |
 *                            |                                 |
 *                            +---------------------------------+ 0xFB000000
 *                            |   Cur. Page Table (Kern, RW)    | RW/-- PTSIZE
 *     VPT -----------------> +---------------------------------+ 0xFAC00000
 *                            |        Invalid Memory (*)       | --/--
 *     KERNTOP -------------> +---------------------------------+ 0xF8000000
 *                            |                                 |
 *                            |    Remapped Physical Memory     | RW/-- KMEMSIZE
 *                            |                                 |
 *     KERNBASE ------------> +---------------------------------+ 0xC0000000
 *                            |                                 |
 *                            |                                 |
 *                            |                                 |
 *                            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 * (*) Note: The kernel ensures that "Invalid Memory" is *never* mapped.
 *     "Empty Memory" is normally unmapped, but user programs may map pages
 *     there if desired.
 *
 * */

/* All physical memory mapped at this address */
#define KERNBASE            0xC0000000
#define KMEMSIZE            0x38000000                  // the maximum amount of physical memory
#define KERNTOP             (KERNBASE + KMEMSIZE)

/* *
 * Virtual page table. Entry PDX[VPT] in the PD (Page Directory) contains
 * a pointer to the page directory itself, thereby turning the PD into a page
 * table, which maps all the PTEs (Page Table Entry) containing the page mappings
 * for the entire virtual address space into that 4 Meg region starting at VPT.
 * */
// 虚拟页表。
// PD（页面目录）中的条目PDX[VPT]包含指向页面目录本身的指针，
// 从而将PD转换为页面表，该页面表将包含整个虚拟地址空间的页面映射的
// 所有PTE（页面表条目）映射到从VPT开始的 4 Meg 区域。
#define VPT                 0xFAC00000

#define KSTACKPAGE          2                           // # of pages in kernel stack
#define KSTACKSIZE          (KSTACKPAGE * PGSIZE)       // sizeof kernel stack

#ifndef __ASSEMBLER__

#include <defs.h>
#include <atomic.h>
#include <list.h>

typedef uintptr_t pte_t;
typedef uintptr_t pde_t;

// some constants for bios interrupt 15h AX = 0xE820
#define E820MAX             20      // number of entries in E820MAP
#define E820_ARM            1       // address range memory
#define E820_ARR            2       // address range reserved

// 该数据结构保存于物理地址0x8000
struct e820map {
    int nr_map; // map中的元素个数

    // 系统内存映射地址描述符（Address Range Descriptor）格式
    struct {
        uint64_t addr;  // 某块内存的起始地址
        uint64_t size;  // 某块内存的大小
        uint32_t type;  // 某块内存的属性。1标识可被使用内存块；2表示保留的内存块，不可映射
    } __attribute__((packed)) map[E820MAX];
};

/* *
 * struct Page - Page descriptor structures. Each Page describes one
 * physical page. In kern/mm/pmm.h, you can find lots of useful functions
 * that convert Page to other data types, such as phyical address.
 * */
/* 
  struct Page：页面描述符结构。
  每个页面描述一个物理页面。
  在kern/mm/pmm.h可以找到许多有用的函数，它们将Page转换为其他数据类型，例如物理地址。
*/
struct Page {
    // 映射此物理页的虚拟页个数
    int ref;                        // page frame's reference counter 
    // 物理页的状态标记
    uint32_t flags;                 // array of flags that describe the status of the page frame
    // 某连续内存空闲块的大小（即地址连续的空闲页的个数）
    // 用到此成员变量的这个Page比较特殊，是这个连续内存空闲块地址最小的一页（即头一页， Head Page）。
    // 连续内存空闲块利用这个页的成员变量property来记录在此块内的空闲页的个数。
    unsigned int property;          // the num of free block, used in first fit pm manager
    // 把多个连续内存空闲块链接在一起的双向链表指针
    // 用到此成员变量的Page也是这个连续内存空闲块地址最小的一页（即头一页， Head Page）。
    // 连续内存空闲块利用这个页的成员变量page_link来链接比它地址小和大的其他连续内存空闲块。
    list_entry_t page_link;         // free list link
};

/* Flags describing the status of a page frame */
// bit 0表示此页是否被保留（reserved），
// 如果是被保留的页，则bit 0会设置为1，
// 且不能放到空闲页链表中，即这样的页不是空闲页，不能动态分配与释放。
#define PG_reserved                 0       // the page descriptor is reserved for kernel or unusable
// bit 1表示此页是否是free的，如果设置为1，表示这页是free的，可以被分配；
// 如果设置为0，表示这页已经被分配出去了，不能被再二次分配。
#define PG_property                 1       // the member 'property' is valid

#define SetPageReserved(page)       set_bit(PG_reserved, &((page)->flags))
#define ClearPageReserved(page)     clear_bit(PG_reserved, &((page)->flags))
#define PageReserved(page)          test_bit(PG_reserved, &((page)->flags))
#define SetPageProperty(page)       set_bit(PG_property, &((page)->flags))
#define ClearPageProperty(page)     clear_bit(PG_property, &((page)->flags))
#define PageProperty(page)          test_bit(PG_property, &((page)->flags))

// convert list entry to page
#define le2page(le, member)                 \
    to_struct((le), struct Page, member)

/* free_area_t - maintains a doubly linked list to record free (unused) pages */
// 为了管理这些小连续内存空闲块。所有的连续内存空闲块可用一个双向链表管理起来，便于分配和释放
typedef struct {
    list_entry_t free_list;         // the list header
    // 记录当前空闲页的个数
    unsigned int nr_free;           // # of free pages in this free list
} free_area_t;

#endif /* !__ASSEMBLER__ */

#endif /* !__KERN_MM_MEMLAYOUT_H__ */

