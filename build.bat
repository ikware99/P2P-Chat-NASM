@echo off
chcp 65001 >nul
title P2P-Chat-NASM 一键编译脚本 v0.7
echo ==============================================
echo    P2P聊天系统 v0.7 (NASM x64 原生中文+无乱码)
echo    一键编译脚本 - Windows x64
echo ==============================================
echo.

:: 检查是否存在源码文件
if not exist src\P2P_Chat_UI_v07_UTF8_UNICODE.asm (
    echo ❌ 错误：未找到源码文件 src\P2P_Chat_UI_v07_UTF8_UNICODE.asm
    echo ❌ 请确认源码文件路径正确！
    pause >nul
    exit
)

:: 一键编译核心命令 (NASM编译OBJ + Link链接EXE)
nasm -f win64 src\P2P_Chat_UI_v07_UTF8_UNICODE.asm -o P2P_Chat_v07.obj
link /subsystem:console /machine:x64 P2P_Chat_v07.obj ws2_32.lib kernel32.lib user32.lib shell32.lib winmm.lib iphlpapi.lib -out:P2P_Chat_v07.exe

:: 编译完成后清理临时OBJ文件
if exist P2P_Chat_v07.obj del /f /q P2P_Chat_v07.obj

:: 编译成功提示
echo.
echo ✅ 编译成功！生成文件：P2P_Chat_v07.exe
echo ✅ 功能：原生中文+全Unicode+WIN+J热键+托盘气泡+Kiko提示音+P2P全功能
echo.
pause >nul
