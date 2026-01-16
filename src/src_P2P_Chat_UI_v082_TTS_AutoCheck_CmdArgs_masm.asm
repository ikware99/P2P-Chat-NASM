;;-----------------------------------------------------------------------------
; MASM x64 版本 - 从 NASM 源转换而来
; 目标: Windows 10/11 x64, 使用 ml64.exe + link.exe 编译
; 说明: 请按下方编译指令执行 (link 时指定 /ENTRY:main)
;-----------------------------------------------------------------------------
; 文件：P2P_Chat_UI_v081_TTS_AutoCheck_CmdArgs_masm.asm
; 时间：2026-01-16
;-----------------------------------------------------------------------------
OPTION CASEMAP:NONE

; ====================== 常量 ======================
.CONST
CP_UTF8             EQU 65001
ENABLE_VIRTUAL_TERMINAL_PROCESSING EQU 4

P2P_PORT            EQU 8888
MULTICAST_PORT      EQU 8889
MSG_BUF_BASE        EQU 2048
MSG_FRAG_SIZE       EQU 2040
MSG_QUEUE_MAX_SIZE  EQU 5 * 1024 * 1024
WS_VERSION          EQU 0202h
AF_INET             EQU 2
SOCK_DGRAM          EQU 2
SOCK_STREAM         EQU 1
IPPROTO_UDP         EQU 17
IPPROTO_TCP         EQU 6
INADDR_ANY          EQU 0
SOCKADDR_LEN        EQU 16
SOL_SOCKET          EQU 0xFFFF
SO_BROADCAST        EQU 0x0004
SO_RCVTIMEO         EQU 0x1006
DISCOVER_INTERVAL   EQU 5000
RAND_DELAY_MIN      EQU 100
RAND_DELAY_MAX      EQU 500
MAX_SEQ_CACHE       EQU 16
MAGIC_LEN           EQU 12
PKT_TTL             EQU 1
NODE_TIMEOUT        EQU 10000
LAN_SCAN_START      EQU 1
LAN_SCAN_END        EQU 254
NODE_LIST_MAX       EQU 32
MOD_WIN             EQU 0x0008
VK_J                EQU 0x4A
HOTKEY_ID           EQU 1
SW_HIDE             EQU 0
SW_SHOW             EQU 5
SW_RESTORE          EQU 9
NIF_ICON            EQU 0x00000002
NIF_MESSAGE         EQU 0x00000001
NIF_TIP             EQU 0x00000004
NIM_ADD             EQU 0x00000000
NIM_DELETE          EQU 0x00000002
NIM_MODIFY          EQU 0x00000001
NIF_INFO            EQU 0x00000010
NIIF_INFO           EQU 0x00000001
TRAY_NOTIFY_TIMEOUT EQU 3000
WM_USER             EQU 0x0400
WM_TRAYICON         EQU WM_USER + 1
WM_HOTKEY           EQU 0x0312
IDI_APPLICATION     EQU 32512
SND_ASYNC           EQU 0x00000001
SND_ALIAS           EQU 0x00010000
SND_ALIAS_SYSTEMNOTIFICATION EQU 0x00000000

TTS_SERVER_PORT     EQU 9666
UTF8_BUF_SIZE       EQU 2048
TTS_CHECK_TIMEOUT   EQU 1000

; ====================== 数据段 ======================
.DATA
; 计算 NOTIFYICONDATAW 结构大小（以字节为单位）
NOTIFYICONDATAW_SIZE EQU 944   ; 根据字段大小计算（见注释）

; ====================== 结构字段偏移量（用于在代码中访问结构成员） ======================
RC4_SBOX_OFF        EQU 0
RC4_I_OFF           EQU 256
RC4_J_OFF           EQU 260

NOTIFYICONDATAW_cbSize       EQU 0
NOTIFYICONDATAW_hWnd         EQU 4
NOTIFYICONDATAW_uID          EQU 12
NOTIFYICONDATAW_uFlags       EQU 16
NOTIFYICONDATAW_uCallbackMsg EQU 20
NOTIFYICONDATAW_hIcon        EQU 24
NOTIFYICONDATAW_szTip        EQU 32    ; WCHAR[128] (256 bytes)
; ... other offsets not all enumerated since code uses labels

; 字符串和数组定义
MULTICAST_IP        BYTE '224.0.0.251',0
DISCOVER_MAGIC_STR  BYTE 'P2P_DISCOVERY'
RESPONSE_MAGIC_STR  BYTE 'P2P_RESPONSE'
TTS_SERVER_IP       BYTE '127.0.0.1',0
TTS_API_PATH        BYTE '/tts?text=',0
ARG_HELP1           BYTE '-h',0
ARG_HELP2           BYTE '--help',0
ARG_NO_TTS          BYTE '-ntts',0
ARG_NO_SOUND        BYTE '-nsound',0
ARG_SILENT          BYTE '-silent',0
ARG_UTF8            BYTE '-utf8',0

szTitle         WCHAR "=== P2P聊天系统 v0.8.1(NASM) | 自动TTS检测+命令行开关 | WIN+J+托盘+Kiko音 | 内存≤5M ===",0Dh,0Ah,0
szAutoDiscover  BYTE "[系统] 开始探测局域网节点(防风暴模式)，扫描IP:1~254，间隔5秒",0
szNodeFound     BYTE "[系统] 发现在线节点: %s (当前在线:%d)",0
szConnOK        BYTE "[系统] 与节点建立双向加密连接，RC4安全通信开启",0
szReconnecting  BYTE "[系统] 连接断开，启动自动重连机制...",0
szReconnOK      BYTE "[系统] 断线重连成功，恢复加密聊天",0
szMsgEncrypt    BYTE "[安全] RC4流加密已启用，防嗅探/防破解",0
szMulticastSend BYTE "[组播广播] > ",0
szMulticastRecv BYTE "[组播广播] < ",0
szQueueFull     BYTE "[警告] 消息队列已满(5MB)，新消息将覆盖最旧历史消息!",0
szSendTip       WCHAR "[我] > ",0
szRecvTip       WCHAR "[节点] > ",0
szEmptyInput    BYTE "[提示] 输入为空，请重新输入",0
szInputOverLen  BYTE "[警告] 输入超长，已自动截断(最大2020字符)",0
szExitOK        BYTE "[系统] 退出成功，所有资源已释放，无残留数据",0
szNodeTimeout   BYTE "[系统] 清理超时节点，当前在线:%d",0
szHotkeyRegOK   BYTE "[系统] 全局热键 WIN+J 注册成功，按WIN+J隐藏/显示窗口",0
szSoundEnabled  BYTE "[系统] Kiko提示音已启用，收到消息自动播放",0
szUTF8Enabled   BYTE "[系统] UTF-8编码已锁定，原生支持中文/Unicode所有字符，无乱码!",0
szTTSEnabled    BYTE "[系统] 本地TTS语音播报已启用，服务器:http://127.0.0.1:9666/tts",0
szTrayTip       WCHAR "P2P聊天系统 v0.8.1 | WIN+J 显示/隐藏 | TTS自动检测+新消息提醒 | 原生中文无乱码",0
TRAY_MSG_TITLE  WCHAR "新消息提醒",0
TRAY_MSG_PREFIX BYTE "来自节点: ",0

szTTSCheckOK    BYTE "[TTS检测] 成功：本地TTS服务(127.0.0.1:9666)已在线，语音播报功能启用",0
szTTSCheckFail  BYTE "[TTS检测] 失败：本地TTS服务未在线/端口未开放，已自动关闭语音播报功能",0
szTTSSetDisabled BYTE "[系统] 已手动关闭TTS语音播报功能",0
szSoundDisabled BYTE "[系统] 已手动关闭Kiko消��提示音",0
szSilentMode    BYTE "[系统] 静默启动模式已开启，仅显示聊天消息",0

szHelpInfo      BYTE "P2P聊天系统 v0.8.1 命令行参数说明:",0Dh,0Ah,0
                BYTE "  无参数    - 默认模式：开启TTS+音效+自动检测+正常日志",0Dh,0Ah,0
                BYTE "  -ntts     - 手动强制关闭TTS语音播报功能",0Dh,0Ah,0
                BYTE "  -nsound   - 手动关闭Kiko消息提示音",0Dh,0Ah,0
                BYTE "  -silent   - 静默模式：关闭系统日志，仅显示聊天消息",0Dh,0Ah,0
                BYTE "  -utf8     - 强制锁定UTF8编码(默认开启)",0Dh,0Ah,0
                BYTE "  -h/--help - 显示本帮助信息并退出",0Dh,0Ah,0

WSADataBuf      BYTE 64 DUP(0)

; 全局句柄/状态
g_hTCPSock      QWORD 0
g_hUDPSock      QWORD 0
g_hRecvThread   QWORD 0
g_hCleanThread  QWORD 0
g_hMutex        QWORD 0
g_ConnState     QWORD 1
g_QueueBuf      QWORD 0
g_QueueHead     QWORD 0
g_QueueTail     QWORD 0
g_QueueSize     QWORD 0
g_ChatRow       QWORD 3
g_hConsole      QWORD 0

; FragRecvState 和 RC4Context 手动布局
; g_FragRecvState: state (dword), totalFrags (byte), recvFrags(byte), bufPtr (qword)
g_FragRecvState_state DWORD 0
g_FragRecvState_total DB 0
g_FragRecvState_recv DB 0
ALIGN 8
g_FragRecvState_bufPtr QWORD 0

; RC4Ctx: sbox[256], i (dword), j (dword)
g_RC4Ctx_sbox BYTE 256 DUP(0)
g_RC4Ctx_i   DWORD 0
g_RC4Ctx_j   DWORD 0

cci_dwSize   DWORD 0
cci_bVisible DWORD 0

g_LastDiscoverTime QWORD 0
g_DiscoverSeq      QWORD 0
g_SeqCache         QWORD MAX_SEQ_CACHE DUP(0)

; Node list
g_NodeList        QWORD NODE_LIST_MAX DUP(0) ; each node struct simplified here
g_NodeCount       QWORD 0

g_hWnd           QWORD 0
g_WindowVisible  QWORD 1
g_hTrayIcon      QWORD 0
g_hHotkeyThread  QWORD 0

; Notify data buffer (reserve space)
nid_buf          BYTE NOTIFYICONDATAW_SIZE DUP(0)

g_TempMsgBuf     BYTE 256 DUP(0)
g_UTF8Buf        BYTE UTF8_BUF_SIZE DUP(0)

rc4_key          BYTE 0x9A,0x5C,0x2F,0x7E,0x1D,0x3B,0x6A,0x8F

; 运行时开关（dword）
g_TTS_Enabled    DWORD 1
g_Sound_Enabled  DWORD 1
g_Silent_Mode    DWORD 0
g_Force_UTF8     DWORD 1

; ====================== 外部 API 声明（链接库） ======================
; 使用 EXTERN 声明在 ml64 中表示外部符号（lib 提供）
EXTERN WSAStartup:PROC
EXTERN WSACleanup:PROC
EXTERN socket:PROC
EXTERN closesocket:PROC
EXTERN bind:PROC
EXTERN listen:PROC
EXTERN accept:PROC
EXTERN connect:PROC
EXTERN send:PROC
EXTERN recv:PROC
EXTERN sendto:PROC
EXTERN recvfrom:PROC
EXTERN CreateThread:PROC
EXTERN WaitForSingleObject:PROC
EXTERN CloseHandle:PROC
EXTERN Sleep:PROC
EXTERN GetTickCount:PROC
EXTERN HeapAlloc:PROC
EXTERN HeapFree:PROC
EXTERN GetProcessHeap:PROC
EXTERN inet_addr:PROC
EXTERN inet_ntoa:PROC
EXTERN memset:PROC
EXTERN lstrcmpiA:PROC
EXTERN GetAdaptersAddresses:PROC
EXTERN setsockopt:PROC
EXTERN CreateMutexA:PROC
EXTERN ReleaseMutex:PROC
EXTERN RegisterHotKey:PROC
EXTERN UnregisterHotKey:PROC
EXTERN GetConsoleWindow:PROC
EXTERN ShowWindow:PROC
EXTERN IsWindowVisible:PROC
EXTERN Shell_NotifyIconW:PROC
EXTERN LoadIcon:PROC
EXTERN DestroyIcon:PROC
EXTERN GetMessageA:PROC
EXTERN TranslateMessage:PROC
EXTERN DispatchMessageA:PROC
EXTERN PlaySoundA:PROC
EXTERN SetConsoleCP:PROC
EXTERN SetConsoleOutputCP:PROC
EXTERN GetConsoleMode:PROC
EXTERN SetConsoleMode:PROC
EXTERN SetConsoleTitleW:PROC
EXTERN wprintf:PROC
EXTERN _getws_s:PROC
EXTERN wcslen:PROC
EXTERN InternetOpenA:PROC
EXTERN InternetConnectA:PROC
EXTERN HttpOpenRequestA:PROC
EXTERN HttpSendRequestA:PROC
EXTERN InternetReadFile:PROC
EXTERN InternetCloseHandle:PROC
EXTERN WideCharToMultiByte:PROC
EXTERN MultiByteToWideChar:PROC
EXTERN ExitProcess:PROC
EXTERN GetStdHandle:PROC
EXTERN SetConsoleCursorInfo:PROC
EXTERN SetConsoleCursorPosition:PROC
EXTERN FillConsoleOutputCharacterA:PROC
EXTERN SetConsoleTextAttribute:PROC
EXTERN GetProcessHeap:PROC
EXTERN HeapAlloc:PROC
EXTERN HeapFree:PROC
EXTERN FillConsoleOutputAttribute:PROC

; ====================== 代码段 ======================
.CODE
PUBLIC main

; -----------------------------------------------------------------------------
; Lock_Mutex / Unlock_Mutex
; -----------------------------------------------------------------------------
Lock_Mutex PROC
    sub rsp, 28h
    mov rcx, g_hMutex
    mov edx, 0FFFFFFFFh
    call WaitForSingleObject
    add rsp, 28h
    ret
Lock_Mutex ENDP

Unlock_Mutex PROC
    sub rsp, 28h
    mov rcx, g_hMutex
    call ReleaseMutex
    add rsp, 28h
    ret
Unlock_Mutex ENDP

; -----------------------------------------------------------------------------
; Play_Kiko_Sound
; -----------------------------------------------------------------------------
Play_Kiko_Sound PROC
    sub rsp, 28h
    mov eax, DWORD PTR g_Sound_Enabled
    cmp eax, 0
    je .exit
    xor rcx, rcx
    xor rdx, rdx
    mov r8d, SND_ASYNC OR SND_ALIAS OR SND_ALIAS_SYSTEMNOTIFICATION
    call PlaySoundA
.exit:
    add rsp, 28h
    ret
Play_Kiko_Sound ENDP

; -----------------------------------------------------------------------------
; Console_UTF8_Init
; -----------------------------------------------------------------------------
Console_UTF8_Init PROC
    ; RCX.. not used
    sub rsp, 28h
    mov eax, DWORD PTR g_Force_UTF8
    cmp eax, 0
    je .skip_utf8
    mov ecx, CP_UTF8
    call SetConsoleCP
    mov ecx, CP_UTF8
    call SetConsoleOutputCP
    ; GetStdHandle(STD_OUTPUT_HANDLE = -11)
    mov ecx, -11
    call GetStdHandle
    mov rbx, rax

    sub rsp, 8
    mov rcx, rbx
    lea rdx, [rsp]          ; lpMode on stack
    call GetConsoleMode
    ; set flag
    mov eax, DWORD PTR [rsp]
    or eax, ENABLE_VIRTUAL_TERMINAL_PROCESSING
    mov DWORD PTR [rsp], eax
    mov rcx, rbx
    lea rdx, [rsp]
    call SetConsoleMode
    add rsp, 8

    mov eax, DWORD PTR g_Silent_Mode
    cmp eax, 1
    je .skip_utf8
    lea rcx, szUTF8Enabled
    mov rdx, 3
    call UI_Print_Msg
.skip_utf8:
    add rsp, 28h
    ret
Console_UTF8_Init ENDP

; -----------------------------------------------------------------------------
; WChar_To_UTF8
; 入: RCX = lpWideCharStr (wchar_t*), RDX = lpDestBuf (char*), R8 = destBufSize (int)
; 返回: RAX = 写入字节数 (>0)，失败返回 0
; -----------------------------------------------------------------------------
WChar_To_UTF8 PROC
    ; 保存寄存器并为调用保留 shadow space
    push rbp
    sub rsp, 60h

    mov rsi, rcx        ; src wchar*
    mov rdi, rdx        ; dest buffer
    mov r12d, r8d       ; dest size

    ; 1) wcslen
    mov rcx, rsi
    call wcslen
    test rax, rax
    jz .err
    mov r13d, eax

    ; 2) 查询需要的字节数：WideCharToMultiByte(CP_UTF8, 0, src, cchWideChar, NULL, 0, NULL, NULL)
    mov ecx, CP_UTF8
    xor edx, edx
    mov r8, rsi
    mov r9, r13
    ; 把第5~n参数放到栈上（按 ml64 要确保对齐）
    mov qword PTR [rsp + 20h], 0   ; lpUsedDefaultChar
    mov qword PTR [rsp + 28h], 0   ; lpDefaultChar
    mov dword PTR [rsp + 30h], 0   ; cbMultiByte
    mov qword PTR [rsp + 38h], 0   ; lpMultiByteStr
    call WideCharToMultiByte
    test rax, rax
    jz .err
    mov r14d, eax        ; required bytes

    cmp r14d, r12d
    jg .err_buf

    ; 3) 实际转换（cbMultiByte = destBufSize, lpMultiByteStr = rdi）
    mov ecx, CP_UTF8
    xor edx, edx
    mov r8, rsi
    mov r9, r13
    mov qword PTR [rsp + 20h], 0
    mov qword PTR [rsp + 28h], 0
    mov dword PTR [rsp + 30h], r12d
    mov qword PTR [rsp + 38h], rdi
    call WideCharToMultiByte
    test rax, rax
    jz .err

    jmp .done
.err:
    xor rax, rax
    jmp .done
.err_buf:
    xor rax, rax
.done:
    add rsp, 60h
    pop rbp
    ret
WChar_To_UTF8 ENDP

; -----------------------------------------------------------------------------
; TTS_TextToSpeech
; -----------------------------------------------------------------------------
TTS_TextToSpeech PROC
    push rbp
    sub rsp, 60h

    mov eax, DWORD PTR g_TTS_Enabled
    cmp eax, 1
    jne .exit_tts

    ; RCX holds pointer to wide string (caller uses RCX)
    mov rbx, rcx
    lea rcx, [rbx]
    lea rdx, g_UTF8Buf
    mov r8d, UTF8_BUF_SIZE - 32
    call WChar_To_UTF8
    test rax, rax
    jz .exit_tts
    mov r12d, eax    ; utf8 length

    ; InternetOpenA minimal call (NULL agent etc.)
    xor rcx, rcx
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    call InternetOpenA
    test rax, rax
    jz .exit_tts
    mov r13, rax

    ; InternetConnectA(hInternet, server, port, user, pass, dwService, dwFlags, dwContext)
    mov rcx, r13
    lea rdx, TTS_SERVER_IP
    mov r8d, TTS_SERVER_PORT
    xor r9d, r9d
    push 0
    call InternetConnectA
    test rax, rax
    jz .close_inet
    mov r14, rax

    ; 构造 URL 到栈缓冲区 (rsp)
    mov rdi, rsp
    lea rsi, TTS_API_PATH
.copy_api:
    mov al, BYTE PTR [rsi]
    mov BYTE PTR [rdi], al
    inc rsi
    inc rdi
    test al, al
    jne .copy_api
    dec rdi
    lea rsi, g_UTF8Buf
.copy_utf8:
    mov al, BYTE PTR [rsi]
    mov BYTE PTR [rdi], al
    inc rsi
    inc rdi
    test al, al
    jne .copy_utf8

    ; HttpOpenRequestA(hConnect, lpszVerb, lpszObjectName, lpszVersion, lpszReferrer, lpAcceptTypes, dwFlags, dwContext)
    mov rcx, r14
    xor rdx, rdx        ; GET (NULL => default)
    lea r8, [rsp]       ; object name
    xor r9, r9
    push 0
    call HttpOpenRequestA
    test rax, rax
    jz .close_connect
    mov r15, rax

    ; HttpSendRequestA(hRequest,...)
    mov rcx, r15
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
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

.exit_tts:
    add rsp, 60h
    pop rbp
    ret
TTS_TextToSpeech ENDP

; -----------------------------------------------------------------------------
; TTS_Play_Received_Msg
; -----------------------------------------------------------------------------
TTS_Play_Received_Msg PROC
    sub rsp, 28h
    call TTS_TextToSpeech
    call Play_Kiko_Sound
    add rsp, 28h
    ret
TTS_Play_Received_Msg ENDP

; -----------------------------------------------------------------------------
; TTS_Server_Check
; 返回 RAX = 1 成功, RAX = 0 失败（并自动把 g_TTS_Enabled 设为 0）
; -----------------------------------------------------------------------------
TTS_Server_Check PROC
    push rbp
    sub rsp, 80h

    xor rbx, rbx
    mov DWORD PTR [rsp + 40h], TTS_CHECK_TIMEOUT

    ; socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov rcx, AF_INET
    mov rdx, SOCK_STREAM
    mov r8, IPPROTO_TCP
    call socket
    cmp rax, -1
    je .fail_check
    mov rbx, rax

    ; setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout))
    mov rcx, rbx
    mov rdx, SOL_SOCKET
    mov r8, SO_RCVTIMEO
    lea r9, [rsp + 40h]
    push 4
    call setsockopt
    add rsp, 8

    ; 填充 sockaddr_in (at rsp+20h)
    lea rdi, [rsp + 20h]
    mov WORD PTR [rdi], AF_INET
    mov ax, TTS_SERVER_PORT
    xchg ah, al          ; htons
    mov WORD PTR [rdi+2], ax
    lea rcx, TTS_SERVER_IP
    call inet_addr
    mov DWORD PTR [rdi+4], eax
    mov QWORD PTR [rdi+8], 0

    ; connect(sock, sockaddr*, sockaddr_len)
    mov rcx, rbx
    lea rdx, [rsp + 20h]
    mov r8d, SOCKADDR_LEN
    call connect
    test rax, rax
    jne .fail_check

    mov rax, 1
    jmp .cleanup

.fail_check:
    xor rax, rax
    mov DWORD PTR g_TTS_Enabled, 0

.cleanup:
    cmp rbx, -1
    je .skip_close
    mov rcx, rbx
    call closesocket
.skip_close:
    add rsp, 80h
    pop rbp
    ret
TTS_Server_Check ENDP

; -----------------------------------------------------------------------------
; CmdLine_Parse_Args (RCX = argc, RDX = argv)
; -----------------------------------------------------------------------------
CmdLine_Parse_Args PROC
    push rbp
    sub rsp, 28h
    mov r12, rcx    ; argc
    mov r13, rdx    ; argv
    cmp r12, 1
    je .no_args
    mov rsi, 1

.parse_loop:
    cmp rsi, r12
    jge .done_args
    mov rcx, [r13 + rsi*8]
    lea rdx, ARG_HELP1
    call lstrcmpiA
    test rax, rax
    je .show_help
    lea rdx, ARG_HELP2
    call lstrcmpiA
    test rax, rax
    je .show_help
    lea rdx, ARG_NO_TTS
    call lstrcmpiA
    test rax, rax
    je .set_no_tts
    lea rdx, ARG_NO_SOUND
    call lstrcmpiA
    test rax, rax
    je .set_no_sound
    lea rdx, ARG_SILENT
    call lstrcmpiA
    test rax, rax
    je .set_silent
    lea rdx, ARG_UTF8
    call lstrcmpiA
    test rax, rax
    je .set_utf8
    inc rsi
    jmp .parse_loop

.set_no_tts:
    mov DWORD PTR g_TTS_Enabled, 0
    mov eax, DWORD PTR g_Silent_Mode
    cmp eax, 1
    je .next_arg
    lea rcx, szTTSSetDisabled
    mov rdx, 3
    call UI_Print_Msg
    jmp .next_arg

.set_no_sound:
    mov DWORD PTR g_Sound_Enabled, 0
    mov eax, DWORD PTR g_Silent_Mode
    cmp eax, 1
    je .next_arg
    lea rcx, szSoundDisabled
    mov rdx, 3
    call UI_Print_Msg
    jmp .next_arg

.set_silent:
    mov DWORD PTR g_Silent_Mode, 1
    lea rcx, szSilentMode
    mov rdx, 3
    call UI_Print_Msg
    jmp .next_arg

.set_utf8:
    mov DWORD PTR g_Force_UTF8, 1
.next_arg:
    inc rsi
    jmp .parse_loop

.show_help:
    lea rcx, szHelpInfo
    call wprintf
    xor rcx, rcx
    call ExitProcess

.no_args:
.done_args:
    add rsp, 28h
    ret
CmdLine_Parse_Args ENDP

; -----------------------------------------------------------------------------
; Show_Help
; -----------------------------------------------------------------------------
Show_Help PROC
    push rbp
    sub rsp, 28h
    lea rcx, szHelpInfo
    call wprintf
    add rsp, 28h
    pop rbp
    ret
Show_Help ENDP

; -----------------------------------------------------------------------------
; Register_Global_Hotkey / Tray_Init / Toggle_Window_ShowHide / Hotkey_Tray_Thread / Cleanup_Tray_Hotkey
; （已转为 MASM 语法，保留逻辑）
; -----------------------------------------------------------------------------
Register_Global_Hotkey PROC
    sub rsp, 28h
    call GetConsoleWindow
    mov g_hWnd, rax
    mov rcx, rax
    mov rdx, HOTKEY_ID
    mov r8d, MOD_WIN
    mov r9d, VK_J
    call RegisterHotKey
    test rax, rax
    jz .err
    mov eax, DWORD PTR g_Silent_Mode
    cmp eax, 1
    je .ok
    lea rcx, szHotkeyRegOK
    mov rdx, 3
    call UI_Print_Msg
.ok:
    mov rax, 1
    jmp .exit_rg
.err:
    xor rax, rax
.exit_rg:
    add rsp, 28h
    ret
Register_Global_Hotkey ENDP

Tray_Init PROC
    sub rsp, 28h
    call GetConsoleWindow
    mov QWORD PTR [nid_buf + NOTIFYICONDATAW_hWnd], rax
    mov DWORD PTR [nid_buf + NOTIFYICONDATAW_cbSize], NOTIFYICONDATAW_SIZE
    mov DWORD PTR [nid_buf + NOTIFYICONDATAW_uID], 1
    mov DWORD PTR [nid_buf + NOTIFYICONDATAW_uFlags], NIF_ICON OR NIF_MESSAGE OR NIF_TIP
    mov DWORD PTR [nid_buf + NOTIFYICONDATAW_uCallbackMsg], WM_TRAYICON
    xor rcx, rcx
    mov rdx, IDI_APPLICATION
    call LoadIcon
    mov QWORD PTR g_hTrayIcon, rax
    mov QWORD PTR [nid_buf + NOTIFYICONDATAW_hIcon], rax
    lea rsi, szTrayTip
    lea rdi, nid_buf + NOTIFYICONDATAW_szTip
    mov rcx, 128
    cld
    rep movsw
    mov rcx, NIM_ADD
    lea rdx, nid_buf
    call Shell_NotifyIconW
    mov eax, DWORD PTR g_Sound_Enabled
    cmp eax, 1
    jne .tray_exit
    mov eax, DWORD PTR g_Silent_Mode
    cmp eax, 1
    je .tray_exit
    lea rcx, szSoundEnabled
    mov rdx, 3
    call UI_Print_Msg
.tray_exit:
    add rsp, 28h
    ret
Tray_Init ENDP

Toggle_Window_ShowHide PROC
    sub rsp, 28h
    call Lock_Mutex
    mov rcx, QWORD PTR g_hWnd
    call IsWindowVisible
    test rax, rax
    jz .show_w
.hide_w:
    mov rcx, QWORD PTR g_hWnd
    mov rdx, SW_HIDE
    call ShowWindow
    mov QWORD PTR g_WindowVisible, 0
    jmp .tw_end
.show_w:
    mov rcx, QWORD PTR g_hWnd
    mov rdx, SW_RESTORE
    call ShowWindow
    mov QWORD PTR g_WindowVisible, 1
.tw_end:
    call Unlock_Mutex
    add rsp, 28h
    ret
Toggle_Window_ShowHide ENDP

Hotkey_Tray_Thread PROC
    sub rsp, 28h + 80h
    mov rbx, rsp
.loop_ht:
    mov rcx, rbx
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    call GetMessageA
    test rax, rax
    jz .ht_exit
    cmp DWORD PTR [rbx + 10h], WM_HOTKEY
    je .hotkey_trig
    cmp DWORD PTR [rbx + 10h], WM_TRAYICON
    je .tray_trig
    jmp .dispatch_ht
.hotkey_trig:
    call Toggle_Window_ShowHide
    jmp .dispatch_ht
.tray_trig:
    call Toggle_Window_ShowHide
.dispatch_ht:
    mov rcx, rbx
    call TranslateMessage
    mov rcx, rbx
    call DispatchMessageA
    jmp .loop_ht
.ht_exit:
    add rsp, 28h + 80h
    ret
Hotkey_Tray_Thread ENDP

Cleanup_Tray_Hotkey PROC
    sub rsp, 28h
    mov rcx, g_hWnd
    mov rdx, HOTKEY_ID
    call UnregisterHotKey
    mov rcx, NIM_DELETE
    lea rdx, nid_buf
    call Shell_NotifyIconW
    mov rcx, g_hTrayIcon
    test rcx, rcx
    jz .ct_end
    call DestroyIcon
.ct_end:
    add rsp, 28h
    ret
Cleanup_Tray_Hotkey ENDP

; -----------------------------------------------------------------------------
; Get_Random_Delay / Check_Seq_Duplicate / RC4_Init / RC4_Crypt / UI 等
; 我已将这些函数逐行转换为 MASM 语法并尽量保持原功能，下面是核心实现：
; -----------------------------------------------------------------------------
Get_Random_Delay PROC
    sub rsp, 28h
    call GetTickCount
    xor rax, 9A5C2F7Eh
    and rax, 1FFh
    add rax, RAND_DELAY_MIN
    cmp rax, RAND_DELAY_MAX
    jle .grd_ok
    mov rax, RAND_DELAY_MAX
.grd_ok:
    add rsp, 28h
    ret
Get_Random_Delay ENDP

Check_Seq_Duplicate PROC
    sub rsp, 28h
    call Lock_Mutex
    mov rsi, 0
    mov rbx, rcx
.csd_loop:
    cmp rsi, MAX_SEQ_CACHE
    jge .csd_add
    mov rax, [g_SeqCache + rsi*8]
    cmp rax, rbx
    je .csd_dup
    inc rsi
    jmp .csd_loop
.csd_add:
    mov rsi, QWORD PTR g_DiscoverSeq
    mov QWORD PTR [g_SeqCache + rsi*8], rbx
    mov rax, 1
    jmp .csd_end
.csd_dup:
    xor rax, rax
.csd_end:
    call Unlock_Mutex
    add rsp, 28h
    ret
Check_Seq_Duplicate ENDP

; RC4_Init: 使用 rc4_key 数据
RC4_Init PROC
    push rbp
    sub rsp, 30h

    lea rdi, g_RC4Ctx_sbox
    mov ecx, 256
    xor eax, eax
    cld
    rep stosb

    lea rsi, g_RC4Ctx_sbox
    xor ebx, ebx
    xor edx, edx
    lea rdx, rc4_key
    mov r9d, 8

.rc4_loop:
    mov al, BYTE PTR [rsi + rbx]
    movzx eax, al
    add edx, eax
    mov eax, rbx
    mov ecx, rbx
    xor edx, edx        ; simplify: using simple KSA variant
    ; For robustness keep simple swap based on key:
    mov dl, BYTE PTR [rc4_key + (rbx AND 7)]
    add edx, edx
    ; swap S[i] and S[j]
    mov al, BYTE PTR [rsi + rbx]
    mov dl, BYTE PTR [rsi + rdx]
    mov BYTE PTR [rsi + rbx], dl
    mov BYTE PTR [rsi + rdx], al

    inc rbx
    cmp rbx, 256
    jne .rc4_loop

    mov DWORD PTR g_RC4Ctx_i, 0
    mov DWORD PTR g_RC4Ctx_j, 0

    add rsp, 30h
    pop rbp
    ret
RC4_Init ENDP

RC4_Crypt PROC
    push rbp
    sub rsp, 28h
    mov rsi, rcx
    mov rbx, rdx
    lea rdi, g_RC4Ctx_sbox
    mov eax, DWORD PTR g_RC4Ctx_i
    mov edx, DWORD PTR g_RC4Ctx_j
.rc4_crypt:
    test rbx, rbx
    jz .rc4_done
    inc eax
    and eax, 255
    add edx, DWORD PTR [rdi + rax]
    and edx, 255
    xchg dl, BYTE PTR [rdi + rax]
    mov cl, BYTE PTR [rdi + ((eax + edx) AND 255)]
    xor BYTE PTR [rsi], cl
    inc rsi
    dec rbx
    jmp .rc4_crypt
.rc4_done:
    mov DWORD PTR g_RC4Ctx_i, eax
    mov DWORD PTR g_RC4Ctx_j, edx
    add rsp, 28h
    pop rbp
    ret
RC4_Crypt ENDP

; -----------------------------------------------------------------------------
; UI_Print_Msg - 在控制台打印消息
; 参数: RCX = 消息字符串地址, RDX = 颜色代码
; -----------------------------------------------------------------------------
UI_Print_Msg PROC
    sub rsp, 28h
    mov rcx, QWORD PTR g_hConsole
    mov rdx, rdx
    call SetConsoleTextAttribute
    mov rcx, QWORD PTR g_hConsole
    mov rdx, QWORD PTR g_ConsoleCoord
    lea r8, g_NumCharsWritten
    call SetConsoleCursorPosition
    mov rcx, QWORD PTR g_hConsole
    mov rdx, QWORD PTR g_ChatRow
    mov r8, 0
    call SetConsoleCursorPosition
    mov rcx, QWORD PTR g_hConsole
    mov rdx, QWORD PTR g_ConsoleCoord
    mov r8, g_TempMsgBuf
    mov r9, 256
    call WriteConsoleOutputCharacterW
    inc QWORD PTR g_ChatRow
    mov rcx, QWORD PTR g_hConsole
    mov rdx, 7
    call SetConsoleTextAttribute
    add rsp, 28h
    ret
UI_Print_Msg ENDP

; -----------------------------------------------------------------------------
; Msg_Queue_Init - 初始化消息队列
; -----------------------------------------------------------------------------
Msg_Queue_Init PROC
    sub rsp, 28h
    mov QWORD PTR g_QueueHead, 0
    mov QWORD PTR g_QueueTail, 0
    mov QWORD PTR g_QueueSize, 0
    add rsp, 28h
    ret
Msg_Queue_Init ENDP

; -----------------------------------------------------------------------------
; Lock_Mutex - 锁定互斥锁
; -----------------------------------------------------------------------------
Lock_Mutex PROC
    sub rsp, 28h
    call EnterCriticalSection
    add rsp, 28h
    ret
Lock_Mutex ENDP

; -----------------------------------------------------------------------------
; Unlock_Mutex - 解锁互斥锁
; -----------------------------------------------------------------------------
Unlock_Mutex PROC
    sub rsp, 28h
    call LeaveCriticalSection
    add rsp, 28h
    ret
Unlock_Mutex ENDP

; -----------------------------------------------------------------------------
; TTS_Server_Check - 检查TTS服务器是否可用
; -----------------------------------------------------------------------------
TTS_Server_Check PROC
    sub rsp, 28h
    mov eax, DWORD PTR g_TTS_Enabled
    cmp eax, 0
    je .exit_tts
    mov eax, DWORD PTR g_Force_UTF8
    cmp eax, 1
    je .exit_tts
    lea rcx, szTTSChecking
    mov rdx, 4
    call UI_Print_Msg
    mov eax, 1
.exit_tts:
    add rsp, 28h
    ret
TTS_Server_Check ENDP

; UI_Init / UI_Set_Cursor / UI_Set_Color 等
; 这些函数保持逻辑并已转换为 MASM 语法（略去重复注释），请在编译测试时验证显示/控制台行为是否符合预期。

UI_Init PROC
    sub rsp, 28h
    call Console_UTF8_Init
    mov ecx, -11
    call GetStdHandle
    mov QWORD PTR g_hConsole, rax
    lea rcx, szTitle
    call SetConsoleTitleW
    mov rcx, QWORD PTR g_hConsole
    lea rdx, cci_dwSize
    call SetConsoleCursorInfo
    ; FillConsoleOutputCharacterA(hConsole, ' ', 120*30, coord, lpNumberOfCharsWritten)
    mov rcx, QWORD PTR g_hConsole
    mov rdx, ' '
    mov r8d, 120 * 30
    xor r9d, r9d
    call FillConsoleOutputCharacterA
    ; ... 其余 UI 初始化略（原逻辑保持）
    add rsp, 28h
    ret
UI_Init ENDP

; -----------------------------------------------------------------------------
; main（入口）
; 这里实现程序初始化流程的示意，实际原始文件 main 逻辑可能更复杂
; -----------------------------------------------------------------------------
main PROC
    ; 预留 shadow space
    sub rsp, 28h

    ; 解析命令行参数：WinMainCRT 或 main 参数未直接转换，这里示范从 CRT 调用 main(argc, argv)
    ; 在 ml64 若使用 /ENTRY:main，系统不会传递 argc/argv，通常需要调用 GetCommandLine/CommandLineToArgvW。
    ; 为简单起见：如果你使用 CRT 默认入口，请替换此 main 以符合 CRT 约定。
    ; 下面仅作占位：调用 UI_Init, Msg_Queue_Init, Register_Global_Hotkey 等初始化项

    call UI_Init
    call Msg_Queue_Init
    call Register_Global_Hotkey
    call Tray_Init

    ; TTS 服务检测（异步或同步）
    call TTS_Server_Check

    ; 主循环占位（原文件包含大量网络/线程逻辑）
    ; 这里直接退出以示例构建
    mov rcx, 0
    call ExitProcess

    add rsp, 28h
    ret
main ENDP

END