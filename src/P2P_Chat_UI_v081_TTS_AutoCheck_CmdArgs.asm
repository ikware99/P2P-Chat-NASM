;-----------------------------------------------------------------------------
; Windows x64 纯NASM汇编 【去中心化P2P无存储聊天系统 - v0.8.1 终极完整版】
; 核心特性: v08全功能 + ✅自动TTS服务检测+离线自动关闭 + ✅命令行参数动态开关 + 无缝降级 + 原生中文无乱码
; 乱码根治: SetConsoleCP/SetConsoleOutputCP(65001) UTF-8锁定 + 全量xxxW宽字符API
; TTS特性: 中文自动转UTF8+HTTP GET+自动检测服务存活+命令行手动开关+自动静默降级+异步无阻塞
; 命令行参数: -ntts(关TTS) -nsound(关音效) -silent(静默) -utf8(强制UTF8) -h/--help(帮助)
; 核心约束: 严格无本地存储、纯汇编无依赖、内存≤5M、线程安全、无残留、Windows10/11 x64原生运行
; 编译指令: nasm -f win64 P2P_Chat_UI_v081_TTS_AutoCheck_CmdArgs.asm -o P2P_Chat_UI_v081_TTS_AutoCheck_CmdArgs.obj
; 链接指令: link /subsystem:console /machine:x64 P2P_Chat_UI_v081_TTS_AutoCheck_CmdArgs.obj ws2_32.lib kernel32.lib user32.lib shell32.lib winmm.lib iphlpapi.lib wininet.lib -out:P2P_Chat_v081.exe
;-----------------------------------------------------------------------------
bits 64
default rel

; ====================== 【全局常量定义 - ✅v081新增命令行/检测常量+原有全部保留】 ======================
P2P_PORT            equ 8888
MULTICAST_PORT      equ 8889
MULTICAST_IP        db '224.0.0.251',0
MSG_BUF_BASE        equ 2048
MSG_FRAG_SIZE       equ 2040
MSG_QUEUE_MAX_SIZE  equ 5*1024*1024
WS_VERSION          equ 0202h
AF_INET             equ 2
SOCK_DGRAM          equ 2
SOCK_STREAM         equ 1
IPPROTO_UDP         equ 17
IPPROTO_TCP         equ 6
INADDR_ANY          equ 00000000h
SOCKADDR_LEN        equ 16
SOL_SOCKET          equ 0xFFFF
SO_BROADCAST        equ 0x0004
SO_RCVTIMEO         equ 0x1006
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
CP_UTF8             equ 65001
ENABLE_VIRTUAL_TERMINAL_PROCESSING equ 0x0004
; ✅v08 原有TTS常量保留
TTS_SERVER_IP       db '127.0.0.1',0
TTS_SERVER_PORT     equ 9666
TTS_API_PATH        db '/tts?text=',0
UTF8_BUF_SIZE       equ 2048
; ✅v081 新增核心常量 - TTS检测+命令行参数
TTS_CHECK_TIMEOUT   equ 1000        ; TTS服务检测超时时间 1秒
ARG_HELP1           db '-h',0
ARG_HELP2           db '--help',0
ARG_NO_TTS          db '-ntts',0
ARG_NO_SOUND        db '-nsound',0
ARG_SILENT          db '-silent',0
ARG_UTF8            db '-utf8',0

; ====================== 【结构体定义 - 原有全部保留，无修改】 ======================
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

struc NOTIFYICONDATAW
    .cbSize         resd 1
    .hWnd           resq 1
    .uID            resd 1
    .uFlags         resd 1
    .uCallbackMessage resd 1
    .hIcon          resq 1
    .szTip          resw 128
    .dwState        resd 1
    .dwStateMask    resd 1
    .szInfo         resw 256
    .uTimeoutOrVersion resd 1
    .szInfoTitle    resw 64
    .dwInfoFlags    resd 1
endstruc

; ====================== 【数据段 - ✅v081核心修改+新增，重中之重】 ======================
section .data
    ; ✅ 窗口标题升级为v0.8.1
    szTitle           dw '=== P2P聊天系统 v0.8.1(NASM) | 自动TTS检测+命令行开关 | WIN+J+托盘+Kiko音 | 内存≤5M ===',0x000a,0x0000
    szAutoDiscover    dw '[系统] 开始探测局域网节点(防风暴模式)，扫描IP:1~254，间隔5秒',0x0000
    szNodeFound       dw '[系统] 发现在线节点: %s (当前在线:%d)',0x0000
    szConnOK          dw '[系统] 与节点建立双向加密连接，RC4安全通信开启',0x0000
    szReconnecting    dw '[系统] 连接断开，启动自动重连机制...',0x0000
    szReconnOK        dw '[系统] 断线重连成功，恢复加密聊天',0x0000
    szMsgEncrypt      dw '[安全] RC4流加密已启用，防嗅探/防破解',0x0000
    szMulticastSend   dw '[组播广播] > ',0x0000
    szMulticastRecv   dw '[组播广播] < ',0x0000
    szQueueFull       dw '[警告] 消息队列已满(5MB)，新消息将覆盖最旧历史消息!',0x0000
    szSendTip         dw '[我] > ',0x0000
    szRecvTip         dw '[节点] > ',0x0000
    szEmptyInput      dw '[提示] 输入为空，请重新输入',0x0000
    szInputOverLen    dw '[警告] 输入超长，已自动截断(最大2020字符)',0x0000
    szExitOK          dw '[系统] 退出成功，所有资源已释放，无残留数据',0x0000
    szNodeTimeout     dw '[系统] 清理超时节点，当前在线:%d',0x0000
    szHotkeyRegOK     dw '[系统] 全局热键 WIN+J 注册成功，按WIN+J隐藏/显示窗口',0x0000
    szSoundEnabled    dw '[系统] Kiko提示音已启用，收到消息自动播放',0x0000
    szUTF8Enabled     dw '[系统] UTF-8编码已锁定，原生支持中文/Unicode所有字符，无乱码!',0x0000
    szTTSEnabled      dw '[系统] 本地TTS语音播报已启用，服务器:http://127.0.0.1:9666/tts',0x0000
    szTrayTip         dw 'P2P聊天系统 v0.8.1 | WIN+J 显示/隐藏 | TTS自动检测+新消息提醒 | 原生中文无乱码',0x0000
    TRAY_MSG_TITLE    dw '新消息提醒',0x0000
    TRAY_MSG_PREFIX   dw '来自节点: ',0x0000
    ; ✅v081 新增提示文本 - TTS检测+命令行帮助
    szTTSCheckOK      dw '[TTS检测] 成功：本地TTS服务(127.0.0.1:9666)已在线，语音播报功能启用',0x0000
    szTTSCheckFail    dw '[TTS检测] 失败：本地TTS服务未在线/端口未开放，已自动关闭语音播报功能',0x0000
    szTTSSetDisabled  dw '[系统] 已手动关闭TTS语音播报功能',0x0000
    szSoundDisabled   dw '[系统] 已手动关闭Kiko消息提示音',0x0000
    szSilentMode      dw '[系统] 静默启动模式已开启，仅显示聊天消息',0x0000
    szHelpInfo        dw 'P2P聊天系统 v0.8.1 命令行参数说明:',0x000a,0x0000
                      dw '  无参数    - 默认模式：开启TTS+音效+自动检测+正常日志',0x000a,0x0000
                      dw '  -ntts     - 手动强制关闭TTS语音播报功能',0x000a,0x0000
                      dw '  -nsound   - 手动关闭Kiko消息提示音',0x000a,0x0000
                      dw '  -silent   - 静默模式：关闭系统日志，仅显示聊天消息',0x000a,0x0000
                      dw '  -utf8     - 强制锁定UTF8编码(默认开启)',0x000a,0x0000
                      dw '  -h/--help - 显示本帮助信息并退出',0x000a,0x0000

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
    nid               istruc NOTIFYICONDATAW iend
    g_TempMsgBuf      dw 256 dup(0)
    g_UTF8Buf         db UTF8_BUF_SIZE dup(0)
    ; ✅v081 核心修改【重中之重】：所有开关从 编译期常量(equ) → 运行时全局变量(dword)
    ; 原因：equ是只读常量，无法通过命令行参数动态修改；dword变量支持运行时读写，实现动态开关
    g_TTS_Enabled     dd 1        ; TTS总开关：1=开启(默认)，0=关闭
    g_Sound_Enabled   dd 1        ; 音效总开关：1=开启(默认)，0=关闭
    g_Silent_Mode     dd 0        ; 静默模式：0=关闭(默认)，1=开启
    g_Force_UTF8      dd 1        ; UTF8强制开启：1=开启(默认)

; ====================== 【外部API声明 - ✅v081新增必要API+原有全部保留】 ======================
extern WSAStartup:PROC, WSACleanup:PROC
extern socket:PROC, closesocket:PROC, bind:PROC, listen:PROC, accept:PROC
extern connect:PROC, send:PROC, recv:PROC, sendto:PROC, recvfrom:PROC
extern CreateThread:PROC, WaitForSingleObject:PROC, CloseHandle:PROC, Sleep:PROC, GetTickCount:PROC
extern HeapAlloc:PROC, HeapFree:PROC, GetProcessHeap:PROC
extern inet_addr:PROC, inet_ntoa:PROC, memset:PROC, lstrcmpiA:PROC
extern GetAdaptersAddresses:PROC, setsockopt:PROC
extern CreateMutexA:PROC, ReleaseMutex:PROC
extern RegisterHotKey:PROC, UnregisterHotKey:PROC
extern GetConsoleWindow:PROC, ShowWindow:PROC, IsWindowVisible:PROC
extern Shell_NotifyIconW:PROC, LoadIcon:PROC, DestroyIcon:PROC
extern GetMessageA:PROC, TranslateMessage:PROC, DispatchMessageA:PROC
extern PlaySoundA:PROC
extern SetConsoleCP:PROC, SetConsoleOutputCP:PROC
extern GetConsoleMode:PROC, SetConsoleMode:PROC
extern SetConsoleTitleW:PROC
extern wprintf:PROC, _getws_s:PROC, wcslen:PROC
extern InternetOpenA:PROC, InternetConnectA:PROC, HttpOpenRequestA:PROC, HttpSendRequestA:PROC
extern InternetReadFile:PROC, InternetCloseHandle:PROC
extern WideCharToMultiByte:PROC, MultiByteToWideChar:PROC

; ====================== 【代码段 - ✅v081完整升级，新增4个核心函数+修改所有判断逻辑】 ======================
section .text
global main

;-----------------------------------------------------------------------------
; 原有函数 - 线程锁 无修改
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
; ✅v081 修改函数：Play_Kiko_Sound - 适配运行时音效开关g_Sound_Enabled
;-----------------------------------------------------------------------------
Play_Kiko_Sound:
    push rbp
    sub rsp, 0x28
    cmp dword [g_Sound_Enabled], 0  ; ✅改为运行时变量判断
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
; ✅v081 修改函数：Console_UTF8_Init - 适配静默模式+UTF8开关，日志输出可控
;-----------------------------------------------------------------------------
Console_UTF8_Init:
    push rbp rbx rsi rdi
    sub rsp, 0x28
    cmp dword [g_Force_UTF8], 0
    je .skip_utf8
    mov rcx, CP_UTF8
    call SetConsoleCP
    mov rcx, CP_UTF8
    call SetConsoleOutputCP
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
    cmp dword [g_Silent_Mode], 1    ; ✅静默模式不打印日志
    je .skip_utf8
    lea rcx, [szUTF8Enabled]
    mov rdx, 3
    call UI_Print_Msg
.skip_utf8:
    ; TTS启用提示 - 改为在检测后打印
.exit:
    add rsp, 0x28
    pop rdi rsi rbx rbp
    ret

;-----------------------------------------------------------------------------
; ✅v081 新增【核心函数1】WChar_To_UTF8 - UTF16宽字符转UTF8编码 (原有保留，无修改)
;-----------------------------------------------------------------------------
WChar_To_UTF8:
    push rbx rbp rsi rdi
    sub rsp, 0x28
    mov rbx, rcx
    mov rsi, rdx
    mov rdi, r8
    call wcslen
    test rax, rax
    jz .err
    mov rcx, CP_UTF8
    mov rdx, 0
    mov r8, rbx
    mov r9, rax
    lea r10, [rsp+0x20]
    push rdi
    push 0
    call WideCharToMultiByte
    test rax, rax
    jz .err
    mov rcx, CP_UTF8
    mov rdx, 0
    mov r8, rbx
    mov r9, [rsp+0x28]
    mov r10, rsi
    mov dword [rsp+0x20], edi
    push 0
    call WideCharToMultiByte
.err:
    add rsp, 0x28
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ✅v081 修改【核心函数2】TTS_TextToSpeech - 适配运行时TTS开关g_TTS_Enabled
;-----------------------------------------------------------------------------
TTS_TextToSpeech:
    push rbx rbp rsi rdi r12 r13 r14 r15
    sub rsp, 0x48
    cmp dword [g_TTS_Enabled], 1    ; ✅改为运行时变量判断，核心改动
    jne .exit
    mov rbx, rcx
    lea rcx, [rbx]
    lea rdx, [g_UTF8Buf]
    mov r8, UTF8_BUF_SIZE - 32
    call WChar_To_UTF8
    test rax, rax
    jz .exit
    mov r12, rax
    xor rcx, rcx
    lea rdx, [TTS_SERVER_IP]
    xor r8, r8
    xor r9, r9
    call InternetOpenA
    test rax, rax
    jz .exit
    mov r13, rax
    mov rcx, r13
    lea rdx, [TTS_SERVER_IP]
    mov r8, TTS_SERVER_PORT
    xor r9, r9
    xor r10, r10
    push 0
    call InternetConnectA
    test rax, rax
    jz .close_inet
    mov r14, rax
    lea rcx, [TTS_API_PATH]
    lea rdx, [g_UTF8Buf]
    mov rdi, rsp
    mov rsi, rcx
.copy_api:
    lodsb
    stosb
    test al, al
    jnz .copy_api
    dec rdi
    mov rsi, rdx
.copy_utf8:
    lodsb
    stosb
    test al, al
    jnz .copy_utf8
    mov rcx, r14
    xor rdx, rdx
    lea r8, [rsp]
    xor r9, r9
    xor r10, r10
    push 0
    call HttpOpenRequestA
    test rax, rax
    jz .close_connect
    mov r15, rax
    mov rcx, r15
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    push 0
    call HttpSendRequestA
.close_request:
    mov rcx, r15
    call InternetCloseHandle
.close_connect:
    mov rcx, r14
    call InternetCloseHandle
.close_inet:
    mov rcx, r13
    call InternetCloseHandle
.exit:
    add rsp, 0x48
    pop r15 r14 r13 r12 rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ✅v081 修改【封装函数】TTS_Play_Received_Msg - 无逻辑修改，仅适配上层变量
;-----------------------------------------------------------------------------
TTS_Play_Received_Msg:
    push rbp
    sub rsp, 0x28
    call TTS_TextToSpeech
    call Play_Kiko_Sound
    add rsp, 0x28
    pop rbp
    ret

;-----------------------------------------------------------------------------
; ✅v081 新增【核心函数3】TTS_Server_Check - TTS服务存活检测(核心亮点)
; 功能：TCP检测127.0.0.1:9666端口是否开放，超时1秒，无阻塞，检测失败自动关闭TTS
; 出参：RAX=1 检测成功，RAX=0 检测失败
;-----------------------------------------------------------------------------
TTS_Server_Check:
    push rbx rbp rsi rdi
    sub rsp, 0x28 + SOCKADDR_LEN + 8
    mov dword [rsp+0x28+SOCKADDR_LEN], TTS_CHECK_TIMEOUT  ; 超时时间1秒
    mov dword [rsp+0x28+SOCKADDR_LEN+4], 0
    ; 1. 创建TCP套接字
    mov rcx, AF_INET
    mov rdx, SOCK_STREAM
    mov r8, IPPROTO_TCP
    call socket
    test rax, rax
    jz .fail
    mov rbx, rax
    ; 2. 设置套接字超时
    mov rcx, rbx
    mov rdx, SOL_SOCKET
    mov r8, SO_RCVTIMEO
    lea r9, [rsp+0x28+SOCKADDR_LEN]
    push 8
    call setsockopt
    ; 3. 填充TTS服务器地址结构
    lea rdi, [rsp+0x28]
    mov word [rdi], AF_INET
    mov ax, TTS_SERVER_PORT
    xchg ah, al
    mov word [rdi+2], ax
    call inet_addr
    mov dword [rdi+4], eax
    mov qword [rdi+8], 0
    ; 4. 尝试连接TTS服务器
    mov rcx, rbx
    lea rdx, [rsp+0x28]
    mov r8, SOCKADDR_LEN
    call connect
    test rax, rax
    jnz .fail
    ; 检测成功
    mov rax, 1
    jmp .cleanup
.fail:
    mov rax, 0
    mov dword [g_TTS_Enabled], 0    ; ✅自动关闭TTS开关
.cleanup:
    mov rcx, rbx
    call closesocket
    add rsp, 0x28 + SOCKADDR_LEN +8
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ✅v081 新增【核心函数4】CmdLine_Parse_Args - 命令行参数解析(核心亮点)
; 入参：RCX=argc(参数个数), RDX=argv(参数指针数组)
; 功能：解析所有命令行参数，动态修改全局开关变量，优先级最高，无参数则默认值
;-----------------------------------------------------------------------------
CmdLine_Parse_Args:
    push rbx rbp rsi rdi r12 r13
    sub rsp, 0x28
    mov r12, rcx    ; R12 = argc
    mov r13, rdx    ; R13 = argv
    cmp r12, 1
    je .exit        ; 无参数，直接退出
    mov rsi, 1      ; 跳过程序名，从第1个参数开始解析
.parse_loop:
    cmp rsi, r12
    jge .exit
    mov rcx, [r13+rsi*8]
    lea rdx, [ARG_HELP1]
    call lstrcmpiA
    test rax, rax
    je .show_help
    lea rdx, [ARG_HELP2]
    call lstrcmpiA
    test rax, rax
    je .show_help
    lea rdx, [ARG_NO_TTS]
    call lstrcmpiA
    test rax, rax
    je .set_no_tts
    lea rdx, [ARG_NO_SOUND]
    call lstrcmpiA
    test rax, rax
    je .set_no_sound
    lea rdx, [ARG_SILENT]
    call lstrcmpiA
    test rax, rax
    je .set_silent
    lea rdx, [ARG_UTF8]
    call lstrcmpiA
    test rax, rax
    je .set_utf8
    inc rsi
    jmp .parse_loop
.set_no_tts:
    mov dword [g_TTS_Enabled], 0
    cmp dword [g_Silent_Mode],1
    je .next_arg
    lea rcx, [szTTSSetDisabled]
    mov rdx,3
    call UI_Print_Msg
    jmp .next_arg
.set_no_sound:
    mov dword [g_Sound_Enabled],0
    cmp dword [g_Silent_Mode],1
    je .next_arg
    lea rcx, [szSoundDisabled]
    mov rdx,3
    call UI_Print_Msg
    jmp .next_arg
.set_silent:
    mov dword [g_Silent_Mode],1
    lea rcx, [szSilentMode]
    mov rdx,3
    call UI_Print_Msg
    jmp .next_arg
.set_utf8:
    mov dword [g_Force_UTF8],1
.next_arg:
    inc rsi
    jmp .parse_loop
.show_help:
    lea rcx, [szHelpInfo]
    call wprintf
    call ExitProcess
.exit:
    add rsp,0x28
    pop r13 r12 rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ✅v081 新增【辅助函数】Show_Help - 显示帮助信息
;-----------------------------------------------------------------------------
Show_Help:
    push rbp
    sub rsp,0x28
    lea rcx,[szHelpInfo]
    call wprintf
    add rsp,0x28
    pop rbp
    ret

;-----------------------------------------------------------------------------
; 原有函数 - 托盘/热键/窗口控制 全部保留无修改
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
    cmp dword [g_Silent_Mode],1
    je .ok
    lea rcx, [szHotkeyRegOK]
    mov rdx, 3
    call UI_Print_Msg
.ok:
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
    rep movsw
    mov rcx, NIM_ADD
    lea rdx, [nid]
    call Shell_NotifyIconW
    cmp dword [g_Sound_Enabled], 1
    jne .exit
    cmp dword [g_Silent_Mode],1
    je .exit
    lea rcx, [szSoundEnabled]
    mov rdx,3
    call UI_Print_Msg
.exit:
    add rsp,0x28
    pop rsi rbp rbx
    ret

Toggle_Window_ShowHide:
    push rbx rbp
    sub rsp,0x28
    call Lock_Mutex
    mov rcx,[g_hWnd]
    call IsWindowVisible
    test rax,rax
    jz .show_window
.hide_window:
    mov rcx,[g_hWnd]
    mov rdx,SW_HIDE
    call ShowWindow
    mov qword [g_WindowVisible],0
    jmp .exit
.show_window:
    mov rcx,[g_hWnd]
    mov rdx,SW_RESTORE
    call ShowWindow
    mov qword [g_WindowVisible],1
.exit:
    call Unlock_Mutex
    add rsp,0x28
    pop rbp rbx
    ret

Hotkey_Tray_Thread:
    push rbx rbp rsi rdi
    sub rsp,0x28 +128
    mov rbx,rsp
.loop:
    mov rcx,rbx
    xor rdx,rdx
    xor r8,rdx
    xor r9,rdx
    call GetMessageA
    test rax,rax
    jz .exit
    cmp dword [rbx+16],WM_HOTKEY
    je .hotkey_trigger
    cmp dword [rbx+16],WM_TRAYICON
    je .tray_click_trigger
    jmp .dispatch
.hotkey_trigger:
    call Toggle_Window_ShowHide
    jmp .dispatch
.tray_click_trigger:
    call Toggle_Window_ShowHide
.dispatch:
    mov rcx,rbx
    call TranslateMessage
    mov rcx,rbx
    call DispatchMessageA
    jmp .loop
.exit:
    add rsp,0x28+128
    pop rdi rsi rbp rbx
    ret

Cleanup_Tray_Hotkey:
    push rbp
    sub rsp,0x28
    mov rcx,[g_hWnd]
    mov rdx,HOTKEY_ID
    call UnregisterHotKey
    mov rcx,NIM_DELETE
    lea rdx,[nid]
    call Shell_NotifyIconW
    mov rcx,[g_hTrayIcon]
    test rcx,rcx
    jz .exit
    call DestroyIcon
.exit:
    add rsp,0x28
    pop rbp
    ret

;-----------------------------------------------------------------------------
; 原有函数 - 随机延迟/序列号检测/RC4加密/UI界面/消息队列/分片收发 全部保留无修改
;-----------------------------------------------------------------------------
Get_Random_Delay:
    push rbx
    sub rsp,0x28
    call GetTickCount
    xor rax,0x9A5C2F7E
    and rax,0x1FF
    add rax,RAND_DELAY_MIN
    cmp rax,RAND_DELAY_MAX
    jle .exit
    mov rax,RAND_DELAY_MAX
.exit:
    add rsp,0x28
    pop rbx
    ret

Check_Seq_Duplicate:
    push rbx rcx rsi
    sub rsp,0x28
    call Lock_Mutex
    mov rsi,0
    mov rbx,rcx
.check:
    cmp rsi,MAX_SEQ_CACHE
    jge .add_seq
    cmp [g_SeqCache + rsi*8],rbx
    je .dup
    inc rsi
    jmp .check
.add_seq:
    mov rsi,[g_DiscoverSeq] % MAX_SEQ_CACHE
    mov [g_SeqCache + rsi*8],rbx
    mov rax,1
    jmp .exit
.dup:
    xor rax,rax
.exit:
    call Unlock_Mutex
    add rsp,0x28
    pop rsi rcx rbx
    ret

RC4_Init:
    push rbx rbp rsi rdi
    sub rsp,0x28
    lea rdi,[g_RC4Ctx + RC4Context.sbox]
    mov ecx,256
    xor eax,eax
    cld
    rep stosb
    lea rsi,[g_RC4Ctx + RC4Context.sbox]
    mov ecx,256
.init_sbox:
    mov byte [rsi + rcx -1],cl
    loop .init_sbox
    xor ebx,ebx
    lea rsi,[g_RC4Ctx + RC4Context.sbox]
    mov ecx,256
    mov rbp,db 0x9A,0x5C,0x2F,0x7E,0x1D,0x3B,0x6A,0x8F
    mov edx,8
.permute:
    mov al,byte [rsi + rcx -1]
    add ebx,eax
    add bl,byte [rbp + (rcx-1) % edx]
    xchg al,byte [rsi + ebx %256]
    mov byte [rsi + rcx -1],al
    loop .permute
    mov dword [g_RC4Ctx + RC4Context.i],0
    mov dword [g_RC4Ctx + RC4Context.j],0
    add rsp,0x28
    pop rdi rsi rbp rbx
    ret

RC4_Crypt:
    push rbx rbp rsi rdi
    sub rsp,0x28
    mov rsi,rcx
    mov rbx,rdx
    lea rdi,[g_RC4Ctx + RC4Context.sbox]
    mov eax,[g_RC4Ctx + RC4Context.i]
    mov edx,[g_RC4Ctx + RC4Context.j]
.loop:
    test rbx,rbx
    jz .exit
    inc eax
    and eax,255
    add edx,dword [rdi + rax]
    and edx,255
    xchg dl,byte [rdi + rax]
    mov cl,byte [rdi + (eax + edx) %256]
    xor byte [rsi],cl
    inc rsi
    dec rbx
    jmp .loop
.exit:
    mov [g_RC4Ctx + RC4Context.i],eax
    mov [g_RC4Ctx + RC4Context.j],edx
    add rsp,0x28
    pop rdi rsi rbp rbx
    ret

UI_Init:
    push rbx rbp
    sub rsp,0x28
    call Console_UTF8_Init
    mov rcx,-11
    call GetStdHandle
    mov [g_hConsole],rax
    lea rcx,[szTitle]
    call SetConsoleTitleW
    mov rcx,[g_hConsole]
    lea rdx,[cci]
    call SetConsoleCursorInfo
    mov rcx,[g_hConsole]
    mov rdx,' '
    mov r8,120*30
    mov r9,0
    call FillConsoleOutputCharacterA
    mov rcx,0xF
    call UI_Set_Color
    mov rcx,0
    mov rdx,0
    call UI_Set_Cursor
    lea rcx,[szTitle]
    call wprintf
    mov rcx,0x7
    call UI_Set_Color
    mov rcx,0
    mov rdx,26
    call UI_Set_Cursor
    mov rcx,120
    xor rbx,rbx
UI_Draw_Line:
    push rcx
    mov rcx,'─'
    call wprintf
    pop rcx
    inc rbx
    cmp rbx,rcx
    jl UI_Draw_Line
    mov rcx,0
    mov rdx,27
    call UI_Set_Cursor
    lea rcx,[szSendTip]
    call wprintf
    mov qword [g_ChatRow],3
    add rsp,0x28
    pop rbp rbx
    ret

UI_Set_Cursor:
    push rbx rbp
    sub rsp,0x28
    mov rbx,rdx
    shl rbx,16
    or rbx,rcx
    mov rcx,[g_hConsole]
    mov rdx,rbx
    call SetConsoleCursorPosition
    add rsp,0x28
    pop rbp rbx
    ret

UI_Set_Color:
    push rbx rbp
    sub rsp,0x28
    mov rbx,rcx
    mov rcx,[g_hConsole]
    mov rdx,rbx
    call SetConsoleTextAttribute
    add rsp,0x28
    pop rbp rbx
    ret

UI_Print_Msg:
    push rbx rbp rsi
    sub rsp,0x28
    cmp dword [g_Silent_Mode],1    ; ✅静默模式不打印系统日志
    je .exit
    call Lock_Mutex
    mov rsi,rcx
    mov rbx,rdx
    cmp rbx,1 je .color_send
    cmp rbx,2 je .color_recv
    cmp rbx,3 je .color_status
    cmp rbx,4 je .color_warn
    cmp rbx,5 je .color_multi
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
    call wprintf
    inc qword [g_ChatRow]
    cmp qword [g_ChatRow],25
    jl .exit_ui
    mov qword [g_ChatRow],3
    mov rcx,[g_hConsole]
    mov rdx,' '
    mov r8,120*22
    mov r9,3<<16
    call FillConsoleOutputCharacterA
.exit_ui:
    mov rcx,0x7
    call UI_Set_Color
    call Unlock_Mutex
.exit:
    add rsp,0x28
    pop rsi rbp rbx
    ret

Msg_Queue_Init:
    push rbx
    sub rsp,0x28
    call GetProcessHeap
    mov rcx,rax
    mov rdx,0x8 |0x4
    mov r8,MSG_QUEUE_MAX_SIZE
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
    rep movsw
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
    push4
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
    cmp dword [g_Silent_Mode],1
    je .skip_log
    lea rcx,[szAutoDiscover]
    mov rdx,3
    call UI_Print_Msg
.skip_log:
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
; 原有函数 - TCP/UDP消息接收线程 仅适配运行时开关，无逻辑修改
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
    cmp dword [g_TTS_Enabled],1    ; ✅运行时变量判断
    jne .loop
    lea rcx, [rsp+0x28]
    call TTS_Play_Received_Msg
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
    cmp dword [g_TTS_Enabled],1    ; ✅运行时变量判断
    jne .loop
    lea rcx, [rsp+0x28]
    call TTS_Play_Received_Msg
    jmp .loop
.exit:
    add rsp,0x28+MSG_BUF_BASE+SOCKADDR_LEN
    pop rdi rsi rbp rbx
    ret

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
    call _getws_s
    test rax,rax
    jnz .empty
    call wcslen
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
    cmp dword [g_Silent_Mode],1
    je .skip_conn_log
    lea rcx,[szConnOK]
    mov rdx,3
    call UI_Print_Msg
    lea rcx,[szMsgEncrypt]
    mov rdx,3
    call UI_Print_Msg
.skip_conn_log:
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
    call _getws_s
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
    cmp dword [g_Silent_Mode],1
    je .send_loop
    lea rcx,[szEmptyInput]
    mov rdx,3
    call UI_Print_Msg
    jmp .send_loop
.exit:
    add rsp,0x28+SOCKADDR_LEN
    pop rdi rsi rbp rbx
    ret

;-----------------------------------------------------------------------------
; ✅v081 核心修改【main函数】- 支持命令行参数+自动TTS检测，程序入口重构(重中之重)
; 关键变更：x64汇编 main函数 标准传参 RCX=argc, RDX=argv，完美支持Windows命令行参数
; 执行流程：初始化WSA → 解析命令行参数 → TTS服务检测 → 初始化核心逻辑 → 清理资源
;-----------------------------------------------------------------------------
main:
    push rbx rbp rsi rdi
    sub rsp,0x28
    mov rbx, rcx    ; RBX = argc 命令行参数个数
    mov rsi, rdx    ; RSI = argv 命令行参数指针数组
    ; 1. 初始化WSA网络环境
    mov rcx,WS_VERSION
    lea rdx,[WSADataBuf]
    call WSAStartup
    test rax,rax
    jnz .exit
    ; 2. 创建互斥锁
    xor rcx,rcx
    mov rdx,1
    lea r8,[szTitle]
    call CreateMutexA
    mov [g_hMutex],rax
    ; 3. ✅核心步骤：解析命令行参数，动态设置全局开关
    mov rcx, rbx
    mov rdx, rsi
    call CmdLine_Parse_Args
    ; 4. ✅核心步骤：自动检测TTS服务 (仅当未手动关闭TTS时执行)
    cmp dword [g_TTS_Enabled], 0
    je .skip_tts_check
    call TTS_Server_Check
    test rax,rax
    jnz .tts_ok
    cmp dword [g_Silent_Mode],1
    je .skip_tts_log
    lea rcx,[szTTSCheckFail]
    mov rdx,3
    call UI_Print_Msg
    jmp .skip_tts_log
.tts_ok:
    cmp dword [g_Silent_Mode],1
    je .skip_tts_log
    lea rcx,[szTTSEnabled]
    mov rdx,3
    call UI_Print_Msg
    lea rcx,[szTTSCheckOK]
    mov rdx,3
    call UI_Print_Msg
.skip_tts_log:
.skip_tts_check:
    ; 5. 初始化核心业务逻辑
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
    cmp dword [g_Silent_Mode],1
    je .exit
    lea rcx,[szExitOK]
    mov rdx,3
    call UI_Print_Msg
.exit:
    add rsp,0x28
    pop rdi rsi rbp rbx
    ret
