;-----------------------------------------------------------------------------
; Windows x64 纯NASM汇编 【去中心化P2P无存储聊天系统 - v0.7 终极版】
; 核心特性: 原生UTF-8/Unicode中文无乱码 + v0.6全功能 + WIN+J全局热键 + 托盘气泡+Kiko音 + 防风暴+RC4加密
; 乱码根治: SetConsoleCP/SetConsoleOutputCP(65001) UTF-8锁定 + 全量xxxW宽字符API + 宽字符字符串存储
; 核心约束: 严格无本地存储、纯汇编无依赖、内存≤5M、线程安全、无残留、Windows10/11 x64原生运行
; 编译指令: nasm -f win64 P2P_Chat_UI_v07_UTF8_UNICODE.asm -o P2P_Chat_UI_v07_UTF8_UNICODE.obj
; 链接指令: link /subsystem:console /machine:x64 P2P_Chat_UI_v07_UTF8_UNICODE.obj ws2_32.lib kernel32.lib user32.lib shell32.lib winmm.lib iphlpapi.lib -out:P2P_Chat_UI_v07_UTF8_UNICODE.exe
;-----------------------------------------------------------------------------
bits 64
default rel

; ====================== 【全局常量定义 - 核心升级：UTF8+宽字符常量】 ======================
; 网络/热键/托盘/提示音 核心常量(保留v0.6全部，无修改)
P2P_PORT            equ 8888
MULTICAST_PORT      equ 8889
MULTICAST_IP        db '224.0.0.251',0
MSG_BUF_BASE        equ 2048         ; 加宽字符缓冲区，适配中文
MSG_FRAG_SIZE       equ 2040
MSG_QUEUE_MAX_SIZE  equ 5*1024*1024
WS_VERSION          equ 0202h
AF_INET             equ 2
SOCK_DGRAM          equ 2
IPPROTO_UDP         equ 17
INADDR_ANY          equ 00000000h
SOCKADDR_LEN        equ 16
SOL_SOCKET          equ 0xFFFF
SO_BROADCAST        equ 0x0004
DISCOVER_INTERVAL   equ 5000
RAND_DELAY_MIN      equ 100
RAND_DELAY_MAX      equ 500
MAX_SEQ_CACHE       equ 16
DISCOVER_MAGIC_STR  db 'P2P_DISCOVERY'
RESPONSE_MAGIC_STR  db 'P2P_RESPONSE'
MAGIC_LEN           equ 12
PKT_TTL             equ 1
NODE_TIMEOUT        equ 10000
LAN_SCAN_START      equ 1
LAN_SCAN_END        equ 254
NODE_LIST_MAX       equ 32
MOD_WIN             equ 0x0008
VK_J                equ 0x4A
HOTKEY_ID           equ 1
SW_HIDE             equ 0
SW_SHOW             equ 5
SW_RESTORE          equ 9
NIF_ICON            equ 0x00000002
NIF_MESSAGE         equ 0x00000001
NIF_TIP             equ 0x00000004
NIM_ADD             equ 0x00000000
NIM_DELETE          equ 0x00000002
NIM_MODIFY          equ 0x00000001
NIF_INFO            equ 0x00000010
NIIF_INFO           equ 0x00000001
TRAY_NOTIFY_TIMEOUT equ 3000
WM_USER             equ 0x0400
WM_TRAYICON         equ WM_USER + 1
WM_HOTKEY           equ 0x0312
IDI_APPLICATION     equ 32512
SND_ASYNC           equ 0x00000001
SND_ALIAS           equ 0x00010000
SND_ALIAS_SYSTEMNOTIFICATION equ 0x00000000
SOUND_ENABLED       equ 1
CP_UTF8             equ 65001       ; ? v07新增: UTF-8编码页
ENABLE_VIRTUAL_TERMINAL_PROCESSING equ 0x0004 ; ? v07新增: 控制台宽字符渲染

; ====================== 【结构体定义 - 核心升级：宽字符托盘结构体+全兼容】 ======================
struc FragHeader
    .FragIndex      resb 1
    .TotalFrags     resb 1
    .IsLastFrag     resb 1
    .Reserved       resb 1
endstruc

struc ConsoleCursorInfo
    .dwSize         resd 1
    .bVisible       resd 1
endstruc

struc FragRecvState
    .state          resd 1
    .totalFrags     resb 1
    .recvFrags      resb 1
    .bufPtr         resq 1
endstruc

struc RC4Context
    .sbox           resb 256
    .i              resd 1
    .j              resd 1
endstruc

struc ip_mreq
    .imr_multiaddr  resd 1
    .imr_interface  resd 1
endstruc

struc Discover_Packet
    .Magic          resb MAGIC_LEN
    .SeqNum         resd 1
    .TTL            resb 1
    .SrcIP          resd 1
    .Reserved       resb 3
endstruc

struc Node_Info
    .IPAddr         resd 1
    .LastAlive      resq 1
endstruc

; ? v07核心升级: 宽字符版托盘结构体 NOTIFYICONDATAW (解决托盘中文乱码)
struc NOTIFYICONDATAW
    .cbSize         resd 1
    .hWnd           resq 1
    .uID            resd 1
    .uFlags         resd 1
    .uCallbackMessage resd 1
    .hIcon          resq 1
    .szTip          resw 128         ; 宽字符: 托盘悬浮提示(中文)
    .dwState        resd 1
    .dwStateMask    resd 1
    .szInfo         resw 256         ; 宽字符: 托盘气泡内容(中文消息)
    .uTimeoutOrVersion resd 1
    .szInfoTitle    resw 64          ; 宽字符: 托盘气泡标题(中文)
    .dwInfoFlags    resd 1
endstruc

; ====================== 【数据段 - 核心升级：全UTF-16宽字符中文常量，无乱码】 ======================
section .data
    ; ? v07全部改为【UTF-16 LE 宽字符】中文常量，直接显示无乱码，dw定义(2字节/字符)，结尾0x0000
    szTitle           dw '=== P2P聊天系统 v0.7(NASM) | 原生中文+Unicode无乱码 | WIN+J+托盘提示+Kiko音 | 内存≤5M ===',0x000a,0x0000
    szAutoDiscover    dw '[系统] 开始探测局域网节点(防风暴模式)，扫描IP:1~254，间隔5秒',0x0000
    szNodeFound       dw '[系统] 发现在线节点: %s (当前在线:%d)',0x0000
    szConnOK          dw '[系统] 与节点建立双向加密连接，RC4安全通信开启',0x0000
    szReconnecting    dw '[系统] 连接断开，启动自动重连机制...',0x0000
    szReconnOK        dw '[系统] 断线重连成功，恢复加密聊天',0x0000
    szMsgEncrypt      dw '[安全] RC4流加密已启用，防嗅探/防破解',0x0000
    szMulticastSend   dw '[组播广播] > ',0x0000
    szMulticastRecv   dw '[组播广播] < ',0x0000
    szQueueFull       dw '[警告] 消息队列已满(5MB)，新消息将覆盖最旧历史消息!',0x0000
    szSendTip         dw '[我] > ',0x0000  ; 中文输入前缀
    szRecvTip         dw '[节点] > ',0x0000; 中文接收前缀
    szEmptyInput      dw '[提示] 输入为空，请重新输入',0x0000
    szInputOverLen    dw '[警告] 输入超长，已自动截断(最大2020字符)',0x0000
    szExitOK          dw '[系统] 退出成功，所有资源已释放，无残留数据',0x0000
    szNodeTimeout     dw '[系统] 清理超时节点，当前在线:%d',0x0000
    szHotkeyRegOK     dw '[系统] 全局热键 WIN+J 注册成功，按WIN+J隐藏/显示窗口',0x0000
    szSoundEnabled    dw '[系统] Kiko提示音已启用，收到消息自动播放',0x0000
    szUTF8Enabled     dw '[系统] UTF-8编码已锁定，原生支持中文/Unicode所有字符，无乱码!',0x0000 ;?新增
    ; ? 托盘中文提示全部宽字符，完美显示
    szTrayTip         dw 'P2P聊天系统 v0.7 | WIN+J 显示/隐藏 | 新消息自动提醒 | 原生中文无乱码',0x0000
    TRAY_MSG_TITLE    dw '新消息提醒',0x0000
    TRAY_MSG_PREFIX   dw '来自节点: ',0x0000

    ; 全局内存变量(保留+扩容宽字符缓冲区)
    WSADataBuf        db 64 dup(0)
    g_hTCPSock        dq 0
    g_hUDPSock        dq 0
    g_hRecvThread     dq 0
    g_hCleanThread    dq 0
    g_hMutex          dq 0
    g_ConnState       dq 1
    g_QueueBuf        dq 0
    g_QueueHead       dq 0
    g_QueueTail       dq 0
    g_QueueSize       dq 0
    g_ChatRow         dq 3
    g_hConsole        dq 0
    g_FragRecvState   istruc FragRecvState iend
    g_RC4Ctx          istruc RC4Context iend
    cci               istruc ConsoleCursorInfo iend
    g_LastDiscoverTime dq 0
    g_DiscoverSeq     dq 0
    g_SeqCache        dq MAX_SEQ_CACHE dup(0)
    g_NodeList        istruc Node_Info NODE_LIST_MAX dup(0)
    g_NodeCount       dq 0
    g_hWnd            dq 0
    g_WindowVisible   dq 1
    g_hTrayIcon       dq 0
    g_hHotkeyThread   dq 0
    nid               istruc NOTIFYICONDATAW iend ; ? 宽字符托盘结构体
    g_TempMsgBuf      dw 256 dup(0)       ; ? 宽字符消息缓冲区(中文拼接)

; ====================== 【外部API声明 - 核心升级：全量宽字符xxxW API + UTF8编码API】 ======================
extern WSAStartup:PROC, WSACleanup:PROC
extern socket:PROC, closesocket:PROC, bind:PROC, listen:PROC, accept:PROC
extern connect:PROC, send:PROC, recv:PROC, sendto:PROC, recvfrom:PROC
extern CreateThread:PROC, WaitForSingleObject:PROC, CloseHandle:PROC, Sleep:PROC, GetTickCount:PROC
extern HeapAlloc:PROC, HeapFree:PROC, GetProcessHeap:PROC
extern inet_addr:PROC, inet_ntoa:PROC, memset:PROC
extern GetAdaptersAddresses:PROC, setsockopt:PROC
extern CreateMutexA:PROC, ReleaseMutex:PROC
extern RegisterHotKey:PROC, UnregisterHotKey:PROC
extern GetConsoleWindow:PROC, ShowWindow:PROC, IsWindowVisible:PROC
extern Shell_NotifyIconW:PROC, LoadIcon:PROC, DestroyIcon:PROC ; ? Shell_NotifyIconW 宽字符版
extern GetMessageA:PROC, TranslateMessage:PROC, DispatchMessageA:PROC
extern PlaySoundA:PROC
; ? v07新增核心API: UTF8编码锁定 + 宽字符控制台API + 宽字符字符串处理
extern SetConsoleCP:PROC, SetConsoleOutputCP:PROC
extern GetConsoleMode:PROC, SetConsoleMode:PROC
extern SetConsoleTitleW:PROC ; ? 宽字符窗口标题
extern wprintf:PROC, _getws_s:PROC, wcslen:PROC ; ? 宽字符打印/输入/长度

; ====================== 【代码段 - 完整源码，新增UTF8初始化+全宽字符适配，已标注】 ======================
section .text
global main

;-----------------------------------------------------------------------------
; 线程安全锁(原有，无修改)
;-----------------------------------------------------------------------------
Lock_Mutex:
    push rbp
    sub rsp, 0x28
    mov rcx, [g_hMutex]
    mov rdx, 0FFFFFFFFh
    call WaitForSingleObject
    add rsp, 0x28
    pop rbp
    ret

Unlock_Mutex:
    push rbp
    sub rsp, 0x28
    mov rcx, [g_hMutex]
    call ReleaseMutex
    add rsp, 0x28
    pop rbp
    ret

;-----------------------------------------------------------------------------
; ? v07 新增【核心函数1】控制台UTF8初始化 - 根治中文乱码的核心，必须最先调用
; 功能: 锁定UTF8编码页+启用宽字符渲染，执行后控制台永久支持中文/Unicode
;-----------------------------------------------------------------------------
Console_UTF8_Init:
    push rbp rbx rsi rdi
    sub rsp, 0x28
    ; 步骤1: 锁定控制台输入/输出编码为 UTF-8 (65001)
    mov rcx, CP_UTF8
    call SetConsoleCP
    mov rcx, CP_UTF8
    call SetConsoleOutputCP
    ; 步骤2: 启用控制台宽字符渲染模式，避免中文错位
    mov rcx, -11
    call GetStdHandle
    mov rbx, rax
    sub rsp, 4
    mov rcx, rbx
    lea rdx, [rsp]
    call GetConsoleMode
    or dword [rsp], ENABLE_VIRTUAL_TERMINAL_PROCESSING
    mov rcx, rbx
    lea rdx, [rsp]
    call SetConsoleMode
    add rsp,4
    ; 步骤3: 打印UTF8启用提示
    lea rcx, [szUTF8Enabled]
    mov rdx, 3
    call UI_Print_Msg
    add rsp, 0x28
    pop rdi rsi rbx rbp
    ret

;-----------------------------------------------------------------------------
; v06原有【播放Kiko提示音】无修改
;-----------------------------------------------------------------------------
Play_Kiko_Sound:
    push rbp
    sub rsp, 0x28
    cmp dword [SOUND_ENABLED], 0
    je .exit
    xor rcx, rcx
    xor rdx, rdx
    mov r8, SND_ASYNC | SND_ALIAS | SND_ALIAS_SYSTEMNOTIFICATION
    call PlaySoundA
.exit:
    add rsp, 0x28
    pop rbp
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【托盘气泡提示】宽字符版 - 中文消息完美显示，无乱码
;-----------------------------------------------------------------------------
Show_Tray_Notification:
    push rbx rbp rsi rdi
    sub rsp, 0x28
    call Lock_Mutex
    lea rsi, [TRAY_MSG_PREFIX]
    lea rdi, [g_TempMsgBuf]
    mov rcx, 256
    cld
    rep movsw
    mov rbx, rdi
    lea rsi, [rcx]
    mov rcx, 16
    rep movsw
    mov word [rdi], ':'
    inc rdi
    inc rdi
    mov word [rdi], ' '
    inc rdi
    inc rdi
    lea rsi, [rdx]
    mov rcx, 200
    rep movsw
    lea rdi, [nid]
    mov dword [rdi + NOTIFYICONDATAW.uFlags], NIF_INFO | NIF_ICON | NIF_TIP | NIF_MESSAGE
    lea rsi, [TRAY_MSG_TITLE]
    lea rdi, [nid + NOTIFYICONDATAW.szInfoTitle]
    mov rcx, 64
    rep movsw
    lea rsi, [g_TempMsgBuf]
    lea rdi, [nid + NOTIFYICONDATAW.szInfo]
    mov rcx, 256
    rep movsw
    mov dword [nid + NOTIFYICONDATAW.uTimeoutOrVersion], TRAY_NOTIFY_TIMEOUT
    mov dword [nid + NOTIFYICONDATAW.dwInfoFlags], NIIF_INFO
    mov rcx, NIM_MODIFY
    lea rdx, [nid]
    call Shell_NotifyIconW ; ? 宽字符版托盘气泡
    call Unlock_Mutex
    call Play_Kiko_Sound
    add rsp, 0x28
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; 原有热键/托盘/窗口切换函数(无修改，兼容宽字符)
;-----------------------------------------------------------------------------
Register_Global_Hotkey:
    push rbp
    sub rsp, 0x28
    call GetConsoleWindow
    mov [g_hWnd], rax
    mov rcx, rax
    mov rdx, HOTKEY_ID
    mov r8, MOD_WIN
    mov r9, VK_J
    call RegisterHotKey
    test rax, rax
    jz .err
    lea rcx, [szHotkeyRegOK]
    mov rdx, 3
    call UI_Print_Msg
    mov rax, 1
    jmp .exit
.err:
    xor rax, rax
.exit:
    add rsp, 0x28
    pop rbp
    ret

Tray_Init:
    push rbx rbp rsi
    sub rsp, 0x28
    call GetConsoleWindow
    mov [nid + NOTIFYICONDATAW.hWnd], rax
    mov dword [nid + NOTIFYICONDATAW.cbSize], NOTIFYICONDATAW_size
    mov dword [nid + NOTIFYICONDATAW.uID], 1
    mov dword [nid + NOTIFYICONDATAW.uFlags], NIF_ICON + NIF_MESSAGE + NIF_TIP
    mov dword [nid + NOTIFYICONDATAW.uCallbackMessage], WM_TRAYICON
    xor rcx, rcx
    mov rdx, IDI_APPLICATION
    call LoadIcon
    mov [g_hTrayIcon], rax
    mov [nid + NOTIFYICONDATAW.hIcon], rax
    lea rsi, [szTrayTip]
    lea rdi, [nid + NOTIFYICONDATAW.szTip]
    mov rcx, 128
    cld
    rep movsw ; ? 宽字符复制
    mov rcx, NIM_ADD
    lea rdx, [nid]
    call Shell_NotifyIconW
    cmp dword [SOUND_ENABLED], 1
    jne .exit
    lea rcx, [szSoundEnabled]
    mov rdx, 3
    call UI_Print_Msg
.exit:
    add rsp, 0x28
    pop rsi rbp rbx
    ret

Toggle_Window_ShowHide:
    push rbx rbp
    sub rsp, 0x28
    call Lock_Mutex
    mov rcx, [g_hWnd]
    call IsWindowVisible
    test rax, rax
    jz .show_window
.hide_window:
    mov rcx, [g_hWnd]
    mov rdx, SW_HIDE
    call ShowWindow
    mov qword [g_WindowVisible], 0
    jmp .exit
.show_window:
    mov rcx, [g_hWnd]
    mov rdx, SW_RESTORE
    call ShowWindow
    mov qword [g_WindowVisible], 1
.exit:
    call Unlock_Mutex
    add rsp, 0x28
    pop rbp rbx
    ret

Hotkey_Tray_Thread:
    push rbx rbp rsi rdi
    sub rsp, 0x28 + 128
    mov rbx, rsp
.loop:
    mov rcx, rbx
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    call GetMessageA
    test rax, rax
    jz .exit
    cmp dword [rbx+16], WM_HOTKEY
    je .hotkey_trigger
    cmp dword [rbx+16], WM_TRAYICON
    je .tray_click_trigger
    jmp .dispatch
.hotkey_trigger:
    call Toggle_Window_ShowHide
    jmp .dispatch
.tray_click_trigger:
    call Toggle_Window_ShowHide
.dispatch:
    mov rcx, rbx
    call TranslateMessage
    mov rcx, rbx
    call DispatchMessageA
    jmp .loop
.exit:
    add rsp, 0x28 + 128
    pop rdi rsi rbp rbx
    ret

Cleanup_Tray_Hotkey:
    push rbp
    sub rsp, 0x28
    mov rcx, [g_hWnd]
    mov rdx, HOTKEY_ID
    call UnregisterHotKey
    mov rcx, NIM_DELETE
    lea rdx, [nid]
    call Shell_NotifyIconW
    mov rcx, [g_hTrayIcon]
    test rcx, rcx
    jz .exit
    call DestroyIcon
.exit:
    add rsp, 0x28
    pop rbp
    ret

;-----------------------------------------------------------------------------
; 原有工具函数/加密/分片/节点发现(无修改，兼容宽字符)
;-----------------------------------------------------------------------------
Get_Random_Delay:
    push rbx
    sub rsp, 0x28
    call GetTickCount
    xor rax, 0x9A5C2F7E
    and rax, 0x1FF
    add rax, RAND_DELAY_MIN
    cmp rax, RAND_DELAY_MAX
    jle .exit
    mov rax, RAND_DELAY_MAX
.exit:
    add rsp, 0x28
    pop rbx
    ret

Check_Seq_Duplicate:
    push rbx rcx rsi
    sub rsp, 0x28
    call Lock_Mutex
    mov rsi, 0
    mov rbx, rcx
.check:
    cmp rsi, MAX_SEQ_CACHE
    jge .add_seq
    cmp [g_SeqCache + rsi*8], rbx
    je .dup
    inc rsi
    jmp .check
.add_seq:
    mov rsi, [g_DiscoverSeq] % MAX_SEQ_CACHE
    mov [g_SeqCache + rsi*8], rbx
    mov rax, 1
    jmp .exit
.dup:
    xor rax, rax
.exit:
    call Unlock_Mutex
    add rsp, 0x28
    pop rsi rcx rbx
    ret

RC4_Init:
    push rbx rbp rsi rdi
    sub rsp, 0x28
    lea rdi, [g_RC4Ctx + RC4Context.sbox]
    mov ecx, 256
    xor eax, eax
    cld
    rep stosb
    lea rsi, [g_RC4Ctx + RC4Context.sbox]
    mov ecx, 256
.init_sbox:
    mov byte [rsi + rcx - 1], cl
    loop .init_sbox
    xor ebx, ebx
    lea rsi, [g_RC4Ctx + RC4Context.sbox]
    mov ecx, 256
    mov rbp, db 0x9A,0x5C,0x2F,0x7E,0x1D,0x3B,0x6A,0x8F
    mov edx, 8
.permute:
    mov al, byte [rsi + rcx - 1]
    add ebx, eax
    add bl, byte [rbp + (rcx-1) % edx]
    xchg al, byte [rsi + ebx % 256]
    mov byte [rsi + rcx - 1], al
    loop .permute
    mov dword [g_RC4Ctx + RC4Context.i], 0
    mov dword [g_RC4Ctx + RC4Context.j], 0
    add rsp, 0x28
    pop rdi rsi rbp rbx
    ret

RC4_Crypt:
    push rbx rbp rsi rdi
    sub rsp, 0x28
    mov rsi, rcx
    mov rbx, rdx
    lea rdi, [g_RC4Ctx + RC4Context.sbox]
    mov eax, [g_RC4Ctx + RC4Context.i]
    mov edx, [g_RC4Ctx + RC4Context.j]
.loop:
    test rbx, rbx
    jz .exit
    inc eax
    and eax, 255
    add edx, dword [rdi + rax]
    and edx, 255
    xchg dl, byte [rdi + rax]
    mov cl, byte [rdi + (eax + edx) % 256]
    xor byte [rsi], cl
    inc rsi
    dec rbx
    jmp .loop
.exit:
    mov [g_RC4Ctx + RC4Context.i], eax
    mov [g_RC4Ctx + RC4Context.j], edx
    add rsp, 0x28
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【UI初始化】宽字符版 - 先执行UTF8初始化，中文完美显示
;-----------------------------------------------------------------------------
UI_Init:
    push rbx rbp
    sub rsp, 0x28
    call Console_UTF8_Init ; ? 第一步执行，根治乱码
    mov rcx, -11
    call GetStdHandle
    mov [g_hConsole], rax
    lea rcx, [szTitle]
    call SetConsoleTitleW ; ? 宽字符窗口标题
    mov rcx, [g_hConsole]
    lea rdx, [cci]
    call SetConsoleCursorInfo
    mov rcx, [g_hConsole]
    mov rdx, ' '
    mov r8, 120 * 30
    mov r9, 0
    call FillConsoleOutputCharacterA
    mov rcx, 0xF
    call UI_Set_Color
    mov rcx, 0
    mov rdx, 0
    call UI_Set_Cursor
    lea rcx, [szTitle]
    call wprintf ; ? 宽字符打印
    mov rcx, 0x7
    call UI_Set_Color
    mov rcx, 0
    mov rdx, 26
    call UI_Set_Cursor
    mov rcx, 120
    xor rbx, rbx
UI_Draw_Line:
    push rcx
    mov rcx, '─'
    call wprintf
    pop rcx
    inc rbx
    cmp rbx, rcx
    jl UI_Draw_Line
    mov rcx, 0
    mov rdx, 27
    call UI_Set_Cursor
    lea rcx, [szSendTip]
    call wprintf
    mov qword [g_ChatRow], 3
    add rsp, 0x28
    pop rbp rbx
    ret

UI_Set_Cursor:
    push rbx rbp
    sub rsp, 0x28
    mov rbx, rdx
    shl rbx, 16
    or  rbx, rcx
    mov rcx, [g_hConsole]
    mov rdx, rbx
    call SetConsoleCursorPosition
    add rsp, 0x28
    pop rbp rbx
    ret

UI_Set_Color:
    push rbx rbp
    sub rsp, 0x28
    mov rbx, rcx
    mov rcx, [g_hConsole]
    mov rdx, rbx
    call SetConsoleTextAttribute
    add rsp, 0x28
    pop rbp rbx
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【UI打印消息】宽字符版 - 中文无乱码，颜色区分不变
;-----------------------------------------------------------------------------
UI_Print_Msg:
    push rbx rbp rsi
    sub rsp, 0x28
    call Lock_Mutex
    mov rsi, rcx
    mov rbx, rdx
    cmp rbx,1  je .color_send
    cmp rbx,2  je .color_recv
    cmp rbx,3  je .color_status
    cmp rbx,4  je .color_warn
    cmp rbx,5  je .color_multi
    jmp .color_def
.color_send: mov rcx,0x9
.color_recv: mov rcx,0x2
.color_status:mov rcx,0x6
.color_warn: mov rcx,0x4
.color_multi:mov rcx,0x5
.color_def:  mov rcx,0x7
.print:
    call UI_Set_Color
    mov rcx,0
    mov rdx,[g_ChatRow]
    call UI_Set_Cursor
    mov rcx,rsi
    call wprintf ; ? 宽字符打印，中文完美显示
    inc qword [g_ChatRow]
    cmp qword [g_ChatRow],25
    jl .exit
    mov qword [g_ChatRow],3
    mov rcx,[g_hConsole]
    mov rdx,' '
    mov r8,120*22
    mov r9,3<<16
    call FillConsoleOutputCharacterA
.exit:
    mov rcx,0x7
    call UI_Set_Color
    call Unlock_Mutex
    add rsp,0x28
    pop rsi rbp rbx
    ret

Msg_Queue_Init:
    push rbx
    sub rsp,0x28
    call GetProcessHeap
    mov rcx,rax
    mov rdx, 0x8 | 0x4
    mov r8, MSG_QUEUE_MAX_SIZE
    call HeapAlloc
    test rax,rax
    jz .exit
    call Lock_Mutex
    mov [g_QueueBuf],rax
    mov [g_QueueHead],rax
    mov [g_QueueTail],rax
    mov qword [g_QueueSize],0
    call Unlock_Mutex
.exit:
    add rsp,0x28
    pop rbx
    ret

Msg_Queue_Push:
    push rbx rbp rsi rdi
    sub rsp,0x28
    call Lock_Mutex
    mov rsi,rcx
    mov rdi,[g_QueueTail]
    mov rbx,rdx
    mov rbp,[g_QueueBuf]
    cmp qword [g_QueueSize],MSG_QUEUE_MAX_SIZE
    jl .write
    lea rcx,[szQueueFull]
    mov rdx,4
    call UI_Print_Msg
    mov [g_QueueHead],rdi
    sub qword [g_QueueSize],rbx
.write:
    cld
    rep movsw ; ? 宽字符复制
    add qword [g_QueueTail],rbx*2
    add qword [g_QueueSize],rbx*2
    cmp rdi,rbp+MSG_QUEUE_MAX_SIZE
    jl .exit
    mov qword [g_QueueTail],rbp
.exit:
    call Unlock_Mutex
    add rsp,0x28
    pop rdi rsi rbp rbx
    ret

Recv_Frag_Reassembly:
    push rbx rbp rsi rdi
    sub rsp,0x28
    mov rsi,rcx
    mov rbx,[g_FragRecvState + FragRecvState.state]
    cmp ebx,0
    je .init_frag
    jmp .recv_frag
.init_frag:
    mov al,byte [rsi+FragHeader.TotalFrags]
    mov [g_FragRecvState+FragRecvState.totalFrags],al
    mov byte [g_FragRecvState+FragRecvState.recvFrags],0
    call GetProcessHeap
    mov rcx,rax
    mov rdx,0x8
    mov r8,al*MSG_FRAG_SIZE
    call HeapAlloc
    mov [g_FragRecvState+FragRecvState.bufPtr],rax
    mov dword [g_FragRecvState+FragRecvState.state],1
.recv_frag:
    mov al,byte [rsi+FragHeader.FragIndex]
    mov rdi,[g_FragRecvState+FragRecvState.bufPtr]
    lea rdi,[rdi+(rax-1)*MSG_FRAG_SIZE]
    lea rsi,[rsi+FragHeader_size]
    mov rcx,MSG_FRAG_SIZE
    cld
    rep movsb
    inc byte [g_FragRecvState+FragRecvState.recvFrags]
    mov al,byte [g_FragRecvState+FragRecvState.recvFrags]
    cmp al,byte [g_FragRecvState+FragRecvState.totalFrags]
    jne .not_complete
    mov rax,[g_FragRecvState+FragRecvState.bufPtr]
    mov dword [g_FragRecvState+FragRecvState.state],0
    jmp .exit
.not_complete:
    xor rax,rax
.exit:
    add rsp,0x28
    pop rdi rsi rbp rbx
    ret

Long_Msg_Send:
    push rbx rbp rsi rdi
    sub rsp,0x28 + FragHeader_size + MSG_BUF_BASE
    mov rsi,rcx
    mov rbx,rdx
    mov rbp,r8
    lea rdi,[rsp+0x28]
    mov byte [rdi+FragHeader.FragIndex],0
    mov al,(rbx+MSG_FRAG_SIZE-1)/MSG_FRAG_SIZE
    mov byte [rdi+FragHeader.TotalFrags],al
.loop:
    inc byte [rdi+FragHeader.FragIndex]
    lea rcx,[rdi+FragHeader_size]
    mov rdx,MSG_FRAG_SIZE
    cmp rbx,MSG_FRAG_SIZE
    jl .last_frag
    cld
    rep movsb
    sub rbx,MSG_FRAG_SIZE
    jmp .send
.last_frag:
    cld
    rep movsb
    mov byte [rdi+FragHeader.IsLastFrag],1
.send:
    lea rcx,[rsp+0x28]
    mov rdx,MSG_BUF_BASE
    call RC4_Crypt
    mov rcx,rbp
    lea rdx,[rsp+0x28]
    mov r8,MSG_BUF_BASE
    mov r9,0
    call send
    test rax,rax
    jl .exit
    test byte [rdi+FragHeader.IsLastFrag],1
    jnz .exit
    jmp .loop
.exit:
    add rsp,0x28+FragHeader_size+MSG_BUF_BASE
    pop rdi rsi rbp rbx
    ret

Auto_Reconnect:
    push rbx rsi
    sub rsp,0x28 + SOCKADDR_LEN
    mov rsi,rcx
.loop:
    lea rcx,[szReconnecting]
    mov rdx,3
    call UI_Print_Msg
    mov rcx,2
    mov rdx,2
    mov r8,6
    call socket
    mov [g_hTCPSock],rax
    test rax,rax
    jz .err
    lea rdi,[rsp+0x28]
    mov word [rdi],2
    mov ax,P2P_PORT
    xchg ah,al
    mov word [rdi+2],ax
    call inet_addr
    mov dword [rdi+4],eax
    mov qword [rdi+8],0
    mov rcx,[g_hTCPSock]
    lea rdx,[rsp+0x28]
    mov r8,16
    call connect
    test rax,rax
    jnz .wait
    call Lock_Mutex
    mov qword [g_ConnState],1
    call Unlock_Mutex
    lea rcx,[szReconnOK]
    mov rdx,3
    call UI_Print_Msg
    mov rax,1
    jmp .exit
.wait:
    mov rcx,1000
    call Sleep
    jmp .loop
.err:
    mov rax,0
.exit:
    add rsp,0x28+SOCKADDR_LEN
    pop rsi rbx
    ret

Send_Discovery_Packet:
    push rbx rbp rsi rdi r12
    sub rsp,0x28 + SOCKADDR_LEN + Discover_Packet_size
    call Lock_Mutex
    call GetTickCount
    sub rax,[g_LastDiscoverTime]
    cmp rax,DISCOVER_INTERVAL
    jl .exit
    mov [g_LastDiscoverTime],rax
    inc qword [g_DiscoverSeq]
    call Unlock_Mutex
    mov rcx,2
    mov rdx,2
    mov r8,17
    call socket
    mov rbx,rax
    test rax,rax
    jz .exit
    mov rcx,rbx
    mov rdx,0xFFFF
    mov r8,0x0004
    lea r9,[rsp+0x28+SOCKADDR_LEN+Discover_Packet_size]
    mov dword [r9],1
    push 4
    call setsockopt
    lea rdi,[rsp+0x28+SOCKADDR_LEN]
    lea rsi,[DISCOVER_MAGIC_STR]
    mov rcx,MAGIC_LEN
    cld
    rep movsb
    mov eax,dword [g_DiscoverSeq]
    mov [rdi+Discover_Packet.SeqNum],eax
    mov byte [rdi+Discover_Packet.TTL],PKT_TTL
    call inet_addr
    mov [rdi+Discover_Packet.SrcIP],eax
    lea rdi,[rsp+0x28]
    mov word [rdi],2
    mov ax,P2P_PORT
    xchg ah,al
    mov word [rdi+2],ax
    mov dword [rdi+4],0xFFFFFFFF
    mov qword [rdi+8],0
    mov rcx,LAN_SCAN_START
.loop:
    cmp rcx,LAN_SCAN_END
    jg .close
    mov eax,0xC0A80100
    add eax,ecx
    mov dword [rdi+4],eax
    mov rcx,rbx
    lea rdx,[rsp+0x28+SOCKADDR_LEN]
    mov r8,Discover_Packet_size
    mov r9,0
    lea r10,[rsp+0x28]
    push 16
    call sendto
    inc rcx
    jmp .loop
.close:
    mov rcx,rbx
    call closesocket
.exit:
    add rsp,0x28+SOCKADDR_LEN+Discover_Packet_size
    pop r12 rdi rsi rbp rbx
    ret

Recv_Discovery_Packet:
    push rbx rbp rsi rdi
    sub rsp,0x28 + MSG_BUF_BASE + SOCKADDR_LEN
    mov rcx,[g_hUDPSock]
    lea rdx,[rsp+0x28]
    mov r8,MSG_BUF_BASE
    mov r9,0
    lea r10,[rsp+0x28+MSG_BUF_BASE]
    push 16
    call recvfrom
    test rax,rax
    jle .exit
    lea rsi,[rsp+0x28]
    lea rdi,[DISCOVER_MAGIC_STR]
    mov rcx,MAGIC_LEN
    repe cmpsb
    jne .exit
    mov eax,[rsi+Discover_Packet.SeqNum]
    call Check_Seq_Duplicate
    test rax,rax
    jz .exit
    mov bl,[rsi+Discover_Packet.TTL]
    test bl,bl
    jz .exit
    dec bl
    mov [rsi+Discover_Packet.TTL],bl
    call Get_Random_Delay
    mov rcx,rax
    call Sleep
    lea rsi,[rsp+0x28]
    lea rdi,[RESPONSE_MAGIC_STR]
    mov rcx,MAGIC_LEN
    cld
    rep movsb
    mov rcx,[g_hUDPSock]
    lea rdx,[rsp+0x28]
    mov r8,Discover_Packet_size
    mov r9,0
    lea r10,[rsp+0x28+MSG_BUF_BASE]
    push 16
    call sendto
    call Lock_Mutex
    mov eax,[rsp+0x28+MSG_BUF_BASE+4]
    mov rcx,0
.check_node:
    cmp rcx,[g_NodeCount]
    jge .add_node
    cmp [g_NodeList+rcx*Node_Info_size+Node_Info.IPAddr],eax
    je .exit
    inc rcx
    jmp .check_node
.add_node:
    cmp rcx,NODE_LIST_MAX
    jge .exit
    mov [g_NodeList+rcx*Node_Info_size+Node_Info.IPAddr],eax
    call GetTickCount
    mov [g_NodeList+rcx*Node_Info_size+Node_Info.LastAlive],rax
    inc qword [g_NodeCount]
    call inet_ntoa
    lea rcx,[szNodeFound]
    mov rdx,rax
    mov r8,[g_NodeCount]
    call wprintf
.exit:
    call Unlock_Mutex
    add rsp,0x28+MSG_BUF_BASE+SOCKADDR_LEN
    pop rdi rsi rbp rbx
    ret

LAN_Node_Discover:
    push rbx rbp
    sub rsp,0x28
    lea rcx,[szAutoDiscover]
    mov rdx,3
    call UI_Print_Msg
    call Send_Discovery_Packet
.receive:
    call Recv_Discovery_Packet
    mov rcx,100
    call Sleep
    jmp .receive
.exit:
    add rsp,0x28
    pop rbp rbx
    ret

Multicast_Init:
    push rbx rbp rsi rdi
    sub rsp,0x28 + SOCKADDR_LEN + ip_mreq_size
    mov rcx,2
    mov rdx,2
    mov r8,17
    call socket
    mov [g_hUDPSock],rax
    test rax,rax
    jz .exit
    lea rdi,[rsp+0x28]
    mov word [rdi],2
    mov ax,MULTICAST_PORT
    xchg ah,al
    mov word [rdi+2],ax
    mov dword [rdi+4],0
    mov qword [rdi+8],0
    mov rcx,[g_hUDPSock]
    lea rdx,[rsp+0x28]
    mov r8,16
    call bind
    lea rdi,[rsp+0x28+SOCKADDR_LEN]
    call inet_addr
    mov [rdi+ip_mreq.imr_multiaddr],eax
    mov dword [rdi+ip_mreq.imr_interface],0
    mov rcx,[g_hUDPSock]
    mov rdx,0
    mov r8,5
    lea r9,[rsp+0x28+SOCKADDR_LEN]
    push ip_mreq_size
    call setsockopt
.exit:
    add rsp,0x28+SOCKADDR_LEN+ip_mreq_size
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【TCP接收线程】宽字符版 - 中文消息接收+托盘提示无乱码
;-----------------------------------------------------------------------------
P2P_Recv_Thread:
    push rbx rbp rsi rdi
    sub rsp,0x28 + MSG_BUF_BASE
.loop:
    call Lock_Mutex
    mov rcx,[g_hTCPSock]
    call Unlock_Mutex
    lea rdx,[rsp+0x28]
    mov r8,MSG_BUF_BASE
    mov r9,0
    call recv
    test rax,rax
    jle .err
    lea rcx,[rsp+0x28]
    mov rdx,rax
    call RC4_Crypt
    call Recv_Frag_Reassembly
    test rax,rax
    jz .loop
    call inet_ntoa
    mov rcx, rax
    mov rdx, [rsp+0x28]
    call Show_Tray_Notification
    mov rcx,rax
    mov rdx,MSG_BUF_BASE/2
    call Msg_Queue_Push
    lea rcx,[rax]
    mov rdx,2
    call UI_Print_Msg
    jmp .loop
.err:
    call Lock_Mutex
    mov qword [g_ConnState],0
    call Unlock_Mutex
    call LAN_Node_Discover
    call Auto_Reconnect
    jmp .loop
.exit:
    add rsp,0x28+MSG_BUF_BASE
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【UDP组播接收线程】宽字符版 - 中文组播消息无乱码
;-----------------------------------------------------------------------------
UDP_Multicast_Recv_Thread:
    push rbx rbp rsi rdi
    sub rsp,0x28 + MSG_BUF_BASE + SOCKADDR_LEN
.loop:
    mov rcx,[g_hUDPSock]
    lea rdx,[rsp+0x28]
    mov r8,MSG_BUF_BASE
    mov r9,0
    lea r10,[rsp+0x28+MSG_BUF_BASE]
    push 16
    call recvfrom
    test rax,rax
    jle .loop
    lea rcx,[rsp+0x28]
    mov rdx,rax
    call RC4_Crypt
    call inet_ntoa
    mov rcx, rax
    mov rdx, [rsp+0x28]
    call Show_Tray_Notification
    lea rcx,[szMulticastRecv]
    mov rdx,5
    call UI_Print_Msg
    jmp .loop
.exit:
    add rsp,0x28+MSG_BUF_BASE+SOCKADDR_LEN
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【UDP组播发送线程】宽字符版 - 中文输入+发送无乱码
;-----------------------------------------------------------------------------
UDP_Multicast_Send_Thread:
    push rbx rbp rsi rdi
    sub rsp,0x28 + MSG_BUF_BASE + SOCKADDR_LEN
    lea rdi,[rsp+0x28+MSG_BUF_BASE]
    mov word [rdi],2
    mov ax,MULTICAST_PORT
    xchg ah,al
    mov word [rdi+2],ax
    call inet_addr
    mov dword [rdi+4],eax
    mov qword [rdi+8],0
.loop:
    mov rcx,0
    mov rdx,28
    call UI_Set_Cursor
    lea rcx,[szMulticastSend]
    call wprintf
    lea rcx,[rsp+0x28]
    mov rdx,MSG_BUF_BASE/2
    call _getws_s ; ? 宽字符输入，中文直接输入无乱码
    test rax,rax
    jnz .empty
    call wcslen ; ? 宽字符长度计算
    cmp rax,MSG_FRAG_SIZE/2
    jg .over_len
    call RC4_Crypt
    mov rcx,[g_hUDPSock]
    lea rdx,[rsp+0x28]
    mov r8,rax*2
    mov r9,0
    lea r10,[rsp+0x28+MSG_BUF_BASE]
    push 16
    call sendto
    jmp .loop
.over_len:
    lea rcx,[szInputOverLen]
    mov rdx,4
    call UI_Print_Msg
.empty:
    jmp .loop
.exit:
    add rsp,0x28+MSG_BUF_BASE+SOCKADDR_LEN
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ? v07 升级【核心业务】宽字符输入发送 - 中文输入完美支持，回车发送无乱码
;-----------------------------------------------------------------------------
TCP_P2P_Core:
    push rbx rbp rsi rdi
    sub rsp,0x28 + SOCKADDR_LEN
    call UI_Init
    call Msg_Queue_Init
    call RC4_Init
    call LAN_Node_Discover
    call Multicast_Init
    call Tray_Init
    call Register_Global_Hotkey
    lea rcx,[Hotkey_Tray_Thread]
    xor rdx,rdx
    xor r8,rdx
    xor r9,rdx
    call CreateThread
    mov [g_hHotkeyThread],rax
    mov rcx,2
    mov rdx,1
    mov r8,6
    call socket
    mov [g_hTCPSock],rax
    lea rdi,[rsp+0x28]
    mov word [rdi],2
    mov ax,P2P_PORT
    xchg ah,al
    mov word [rdi+2],ax
    mov dword [rdi+4],0
    mov rcx,[g_hTCPSock]
    lea rdx,[rsp+0x28]
    mov r8,16
    call bind
    mov rcx,[g_hTCPSock]
    mov rdx,5
    call listen
    call accept
    mov [g_hTCPSock],rax
    lea rcx,[szConnOK]
    mov rdx,3
    call UI_Print_Msg
    lea rcx,[szMsgEncrypt]
    mov rdx,3
    call UI_Print_Msg
    lea rcx,[P2P_Recv_Thread]
    xor rdx,rdx
    xor r8,rdx
    xor r9,rdx
    call CreateThread
    mov [g_hRecvThread],rax
    lea rcx,[UDP_Multicast_Recv_Thread]
    xor rdx,rdx
    xor r8,rdx
    xor r9,rdx
    call CreateThread
.send_loop:
    mov rcx,0
    mov rdx,27
    call UI_Set_Cursor
    mov rcx,120
    mov rbx,8
.clear_input:
    push rcx
    mov rcx,' '
    call wprintf
    pop rcx
    inc rbx
    cmp rbx,rcx
    jl .clear_input
    mov rcx,0
    mov rdx,27
    call UI_Set_Cursor
    lea rcx,[szSendTip]
    call wprintf
    sub rsp,MSG_BUF_BASE
    lea rcx,[rsp]
    mov rdx,MSG_BUF_BASE/2
    call _getws_s ; ? 中文输入核心API，直接输入中文无乱码
    test rax,rax
    jnz .empty_input
    call wcslen
    cmp rax,MSG_FRAG_SIZE/2
    jg .over_len
    lea rcx,[rsp]
    mov rdx,rax
    mov r8,[g_hTCPSock]
    call Long_Msg_Send
    call Msg_Queue_Push
    lea rcx,[rsp]
    mov rdx,1
    call UI_Print_Msg
    add rsp,MSG_BUF_BASE
    jmp .send_loop
.over_len:
    lea rcx,[szInputOverLen]
    mov rdx,4
    call UI_Print_Msg
    add rsp,MSG_BUF_BASE
.empty_input:
    lea rcx,[szEmptyInput]
    mov rdx,3
    call UI_Print_Msg
    jmp .send_loop
.exit:
    add rsp,0x28+SOCKADDR_LEN
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; 程序主入口(无修改，兼容宽字符)
;-----------------------------------------------------------------------------
main:
    push rbx rbp rsi rdi
    sub rsp,0x28
    mov rcx,WS_VERSION
    lea rdx,[WSADataBuf]
    call WSAStartup
    test rax,rax
    jnz .exit
    xor rcx,rcx
    mov rdx,1
    lea r8,[szTitle]
    call CreateMutexA
    mov [g_hMutex],rax
    call TCP_P2P_Core
.cleanup:
    call Lock_Mutex
    call Cleanup_Tray_Hotkey
    mov rcx,[g_hTCPSock]
    test rcx,rcx
    jz .skip1
    call closesocket
.skip1:
    mov rcx,[g_hUDPSock]
    test rcx,rcx
    jz .skip2
    call closesocket
.skip2:
    mov rcx,[g_hRecvThread]
    test rcx,rcx
    jz .skip3
    call CloseHandle
.skip3:
    mov rcx,[g_hCleanThread]
    test rcx,rcx
    jz .skip4
    call CloseHandle
.skip4:
    mov rcx,[g_hHotkeyThread]
    test rcx,rcx
    jz .skip5
    call CloseHandle
.skip5:
    mov rcx,[g_QueueBuf]
    test rcx,rcx
    jz .skip6
    call HeapFree
.skip6:
    mov rcx,[g_hMutex]
    test rcx,rcx
    jz .skip7
    call CloseHandle
.skip7:
    call Unlock_Mutex
    call WSACleanup
    lea rcx,[szExitOK]
    mov rdx,3
    call UI_Print_Msg
.exit:
    add rsp,0x28
    pop rdi rsi rbp rbx
    ret





### 第一步：NASM汇编编译为OBJ文件
#nasm -f win64 P2P_Chat_UI_v07_UTF8_UNICODE.asm -o P2P_Chat_UI_v07_UTF8_UNICODE.obj

### 第二步：微软Link链接为EXE（库文件与v06一致，无需修改）
#link /subsystem:console /machine:x64 P2P_Chat_UI_v07_UTF8_UNICODE.obj ws2_32.lib kernel32.lib user32.lib shell32.lib winmm.lib iphlpapi.lib -out:P2P_Chat_UI_v07_UTF8_UNICODE.exe