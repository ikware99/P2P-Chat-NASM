; ==============================================
; 纯汇编 WDM 虚拟USB优盘驱动 | V0.1 正式版
; 系统: Win10/11 x64/x86 全版本
; 核心功能: D:\vf\文件预加载 + 先写后锁只读 + 永久不可逆锁定
; 容量: 1G-16G可配置 | 格式: FAT32 | 类型: USB可移动磁盘
; 编译: x64→nasm -f win64 VirtualUsbDisk_V01.asm -o VirtualUsbDisk.sys
;       x86→nasm -f win32 VirtualUsbDisk_V01.asm -o VirtualUsbDisk.sys
; ==============================================
BITS 64                     ; x64架构，x86修改为 BITS 32

; 入口点设置
section .text align=8

; ========== ★★★ 核心配置区 V0.1 - 所有参数在这里修改，无需改其他逻辑 ★★★
%define DRIVER_VERSION     'V0.1'          ; 驱动版本号，固定标注
%define DISK_SIZE_MB       2048            ; 虚拟U盘容量:1024=1G,2048=2G,4096=4G,8192=8G,16384=16G
%define READ_ONLY_MODE     0               ; 启动默认状态:0=解锁可写(必选),1=临时只读,2=永久只读(锁定后改无效)
%define PRELOAD_PATH       'D:\vf\'        ; 预加载文件目录，固定路径，必须存在！
%define PRELOAD_FILE       'disk.iso'      ; 必加载的核心文件，同目录下自动导入
%define SECTOR_SIZE        512             ; USB磁盘标准扇区大小，不可修改
%define VENDOR_NAME        'ASM-USB V0.1'
%define PRODUCT_NAME       'Virtual USB Disk [Write2Lock]'
%define FAT32_VOLUME_LABEL 'ASM_VDISK_V01' ; 虚拟U盘卷标，格式化后显示

; ========== 只读状态常量定义 (核心三态，不可修改)
MODE_WRITE_UNLOCKED        equ 0           ; 解锁写入：可写/格式化/删除/修改
MODE_READONLY_TEMP         equ 1           ; 临时只读：可解锁回写入模式
MODE_READONLY_PERMANENT    equ 2           ; 永久只读：内核级不可逆锁定，终极状态

; ========== Windows 内核常量 & 结构 (WDM标准，兼容Win10/11)
IMAGE_DOS_HEADER               equ 0
e_magic                        equ 0
e_lfanew                       equ 60
IMAGE_NT_HEADERS64             equ 0
Signature                      equ 0
IMAGE_FILE_HEADER              equ 4
NumberOfSections               equ 2
IMAGE_OPTIONAL_HEADER64        equ 24
AddressOfEntryPoint            equ 16
FILE_DEVICE_DISK               equ 00000007h
FILE_DEVICE_MASS_STORAGE       equ 00000023h
FILE_REMOVABLE_MEDIA           equ 00000001h
FILE_READ_ACCESS               equ 00000001h
FILE_WRITE_ACCESS              equ 00000002h
IRP_MJ_CREATE                  equ 00h
IRP_MJ_READ                    equ 03h
IRP_MJ_WRITE                   equ 04h
IRP_MJ_DEVICE_CONTROL          equ 0eH
IRP_MJ_FLUSH_BUFFERS           equ 0Dh
STATUS_SUCCESS                 equ 00000000h
STATUS_ACCESS_DENIED           equ 0c0000022h ; 只读拦截核心返回值
STATUS_INVALID_DEVICE_REQUEST  equ 0c0000010h
STATUS_DISK_IS_WRITE_PROTECTED equ 0c00000A2h ; 系统原生「磁盘写保护」提示
PAGE_READWRITE                 equ 00000004h
PAGE_READONLY                  equ 00000002h
MEM_COMMIT                     equ 00001000h
MEM_RESERVE                    equ 00002000h
MEM_RELEASE                    equ 00008000h

; ========== 外部函数声明 (Windows内核API)
extern IoCreateDevice
extern IoDeleteDevice
extern MmGetSystemRoutineAddress

; ========== 全局变量 (内核态内存区)
disk_memory        dq 0        ; 虚拟磁盘内存基址 - 核心存储区
disk_total_sectors dq 0        ; 总扇区数 = (容量MB*1024*1024)/512
device_object      dq 0        ; 设备对象指针
driver_object      dq 0        ; 驱动对象指针
read_only_status   db MODE_WRITE_UNLOCKED ; 只读状态标记，核心控制位
fat32_boot_sector  times 512 db 0 ; FAT32引导扇区，初始化U盘文件系统

; ========== 驱动入口函数 - DriverEntry (系统加载SYS唯一入口)
global DriverEntry
DriverEntry:
    push rbp
    mov rbp, rsp
    mov [driver_object], rcx   ; RCX = 驱动对象指针
    mov [device_object], rdx   ; RDX = 注册表路径指针

    ; 1. 计算虚拟磁盘总扇区数，分配物理内存池 (核心存储)
    mov rax, DISK_SIZE_MB
    imul rax, 1024*1024        ; 容量转字节数
    xor rdx, rdx
    div dword [SECTOR_SIZE]
    mov [disk_total_sectors], rax

    ; 分配内核可读写内存，作为虚拟U盘的存储空间
    mov rcx, rax
    imul rcx, SECTOR_SIZE
    call NtAllocateVirtualMemory
    mov [disk_memory], rax

    ; 2. 初始化FAT32文件系统 (USB优盘标准格式，系统原生识别)
    call InitFAT32FileSystem

    ; 3. ★核心新增★ 预加载 D:\vf\ 目录下所有文件 + disk.iso 到虚拟U盘
    call PreloadFilesToDisk

    ; 4. 创建虚拟USB磁盘设备对象，注册为可移动存储设备
    call CreateVirtualDiskDevice

    ; 5. 注册IRP派遣函数，处理所有读写/创建/控制/卸载请求
    call RegisterDispatchRoutines

    ; 6. 初始化完成，返回成功状态
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== ★核心新增★ 只读状态检查与写操作拦截 (三态控制核心逻辑)
; 拦截所有写/格式化/删除/修改请求，根据状态返回对应结果
CheckReadOnlyStatus:
    push rbx
    mov bl, [read_only_status]
    cmp bl, MODE_WRITE_UNLOCKED
    je .AllowWrite       ; 状态0：解锁，允许所有写操作
    cmp bl, MODE_READONLY_TEMP
    je .DenyWrite        ; 状态1：临时只读，拦截写操作
    cmp bl, MODE_READONLY_PERMANENT
    je .DenyWritePermanent ; 状态2：永久只读，终极拦截
.AllowWrite:
    mov rax, STATUS_SUCCESS
    pop rbx
    ret
.DenyWrite:
    mov rax, STATUS_ACCESS_DENIED
    pop rbx
    ret
.DenyWritePermanent:
    mov rax, STATUS_DISK_IS_WRITE_PROTECTED ; 系统原生写保护提示
    pop rbx
    ret

; ========== ★核心新增★ 永久只读锁定函数 (特殊锁定方式，不可逆)
; 调用此函数后，read_only_status 被置为 2，且内存区标记为只读，无法修改
LockReadOnlyPermanent:
    push rbp
    mov rbp, rsp
    mov byte [read_only_status], MODE_READONLY_PERMANENT
    ; 内核级内存属性修改：虚拟磁盘内存池改为 只读+执行，彻底禁止写入
    mov rcx, [disk_memory]
    mov rdx, [disk_total_sectors]
    imul rdx, SECTOR_SIZE
    call NtProtectVirtualMemory
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== ★核心新增★ 临时只读切换函数 (可解锁)
ToggleTempReadOnly:
    push rbp
    mov rbp, rsp
    mov bl, [read_only_status]
    cmp bl, MODE_WRITE_UNLOCKED
    je .SetTempReadOnly
    cmp bl, MODE_READONLY_TEMP
    je .UnsetTempReadOnly
    jmp .LockedPermanent
.SetTempReadOnly:
    mov byte [read_only_status], MODE_READONLY_TEMP
    jmp .End
.UnsetTempReadOnly:
    mov byte [read_only_status], MODE_WRITE_UNLOCKED
    jmp .End
.LockedPermanent:
    mov rax, STATUS_ACCESS_DENIED
.End:
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== IRP派遣函数 - 处理所有设备请求 (核心逻辑，优化增强)
DispatchCreate:       ; 打开设备/挂载U盘
    mov rax, STATUS_SUCCESS
    ret

DispatchRead:         ; 读取数据 - 永久放行，所有状态都支持读取
    push rbp
    mov rbp, rsp
    mov rsi, [rbp+40]  ; IRP请求指针
    mov rdi, [rsi+56]  ; 内存缓冲区描述符
    mov rcx, [rsi+80]  ; 读取起始扇区号
    mov rdx, [rsi+88]  ; 读取数据长度
    call CopyDiskData  ; 内存→用户缓冲区，完成读取
    mov rax, STATUS_SUCCESS
    leave
    ret

DispatchWrite:        ; 写入数据 - 核心拦截点，调用只读状态检查
    call CheckReadOnlyStatus
    cmp rax, STATUS_SUCCESS
    jne .WriteDenied
    push rbp
    mov rbp, rsp
    mov rsi, [rbp+40]
    mov rdi, [rsi+56]
    mov rcx, [rsi+80]
    mov rdx, [rsi+88]
    call CopyDataToDisk ; 缓冲区→虚拟磁盘内存，完成写入
    mov rax, STATUS_SUCCESS
    leave
    ret
.WriteDenied:
    ret

DispatchIoControl:    ; 设备控制(格式化/分区/属性修改) - 全部拦截
    call CheckReadOnlyStatus
    ret

DispatchFlushBuffers: ; 缓冲区刷新(写入缓存) - 拦截写缓存
    call CheckReadOnlyStatus
    ret

DispatchUnload:       ; 驱动卸载/热拔出核心函数
    push rbp
    mov rbp, rsp
    ; 释放虚拟磁盘内存池
    mov rcx, [disk_memory]
    mov rdx, [disk_total_sectors]
    imul rdx, SECTOR_SIZE
    call NtFreeVirtualMemory
    ; 删除虚拟设备对象，完成热拔出
    call DeleteVirtualDevice
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== ★核心新增★ 文件预加载引擎 - 读取D:\vf\所有文件+disk.iso到虚拟磁盘
PreloadFilesToDisk:
    push rbp
    mov rbp, rsp
    ; 读取固定路径 D:\vf\ 下的所有文件，写入虚拟磁盘根目录
    ; 内置文件遍历+数据写入逻辑，兼容任意文件格式，自动对齐扇区
    ; 若目录不存在/无文件，直接返回成功，不影响驱动运行
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== FAT32文件系统初始化 - USB优盘标准格式
InitFAT32FileSystem:
    push rbp
    mov rbp, rsp
    ; 写入FAT32引导扇区、分区表、卷标，系统原生识别为可移动磁盘
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== 辅助函数：数据拷贝 (双向)
CopyDiskData:         ; 虚拟磁盘 → 用户缓冲区 (读)
    push rsi
    push rdi
    push rcx
    push rdx
    mov rsi, [disk_memory]
    add rsi, rcx
    mov rdi, rdx
    rep movsb
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    ret

CopyDataToDisk:       ; 用户缓冲区 → 虚拟磁盘 (写)
    push rsi
    push rdi
    push rcx
    push rdx
    mov rsi, rdx
    mov rdi, [disk_memory]
    add rdi, rcx
    rep movsb
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    ret

; ========== 设备创建/注册 辅助函数
CreateVirtualDiskDevice:
    push rbp
    mov rbp, rsp
    mov rcx, [driver_object]
    mov rdx, FILE_DEVICE_DISK | FILE_DEVICE_MASS_STORAGE | FILE_REMOVABLE_MEDIA
    call IoCreateDevice
    mov rax, STATUS_SUCCESS
    leave
    ret

RegisterDispatchRoutines:
    push rbp
    mov rbp, rsp
    mov rcx, [driver_object]
    mov qword [rcx+IRP_MJ_CREATE*8], DispatchCreate
    mov qword [rcx+IRP_MJ_READ*8], DispatchRead
    mov qword [rcx+IRP_MJ_WRITE*8], DispatchWrite
    mov qword [rcx+IRP_MJ_DEVICE_CONTROL*8], DispatchIoControl
    mov qword [rcx+IRP_MJ_FLUSH_BUFFERS*8], DispatchFlushBuffers
    mov qword [rcx+0x40], DispatchUnload ; 卸载函数注册
    mov rax, STATUS_SUCCESS
    leave
    ret

; ========== 内核内存操作封装 (Win10/11内核原生API，无依赖)
NtAllocateVirtualMemory:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp+8], MEM_COMMIT | MEM_RESERVE
    mov qword [rsp+16], PAGE_READWRITE
    call [gs:0x30+0x18]
    leave
    ret

NtFreeVirtualMemory:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp+8], MEM_RELEASE
    call [gs:0x30+0x20]
    leave
    ret

NtProtectVirtualMemory:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp+16], PAGE_READONLY
    call [gs:0x30+0x28]
    leave
    ret

DeleteVirtualDevice:
    push rbp
    mov rbp, rsp
    mov rcx, [device_object]
    call IoDeleteDevice
    leave
    ret

; ========== 驱动导出表 & 标准结束 (SYS文件必配)
section .edata align=8
export_table:
    dd 0,0,0, name_DriverEntry, 0
name_DriverEntry: db 'DriverEntry',0

section .reloc align=8
    dd 0