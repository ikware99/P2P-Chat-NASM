@echo off
mode con cols=85 lines=22
color 0A
title ASM虚拟USB优盘驱动 V0.1 - 一键管理 [Win10/11] - 先写后锁版
if not "%1"=="admin" (powershell start -verb runas '%0' admin & exit/b)

:menu
cls
echo ==============================================
echo           ASM虚拟USB优盘驱动 V0.1 功能菜单
echo ==============================================
echo  1 - 安装驱动+注册系统服务 (首次必装)
echo  2 - 加载驱动+插入U盘【写入模式】(初始化/拷贝文件)
echo  3 - ★特殊方式★ 永久锁定只读 (写入完成后执行，不可逆！)
echo  4 - 临时切换只读/解锁 (仅未永久锁定时可用)
echo  5 - 拔出U盘+停止驱动 (保留服务，热插拔)
echo  6 - 卸载驱动+删除服务 (彻底清理，不留文件)
echo  7 - 退出
echo ==============================================
echo 提示1: 先执行【2】写入文件/格式化，再执行【3】永久锁定！
echo 提示2: 永久锁定后，仅能读取文件，无法写入/格式化/删除！
echo ==============================================
set /p opt=请选择操作序号:
if "%opt%"=="1" goto install
if "%opt%"=="2" goto load_write
if "%opt%"=="3" goto lock_permanent
if "%opt%"=="4" goto toggle_temp
if "%opt%"=="5" goto unload
if "%opt%"=="6" goto uninstall
if "%opt%"=="7" exit/b

:install
echo 正在安装 V0.1 版驱动并注册系统服务...
pnputil /add-driver setup_V01.inf /install
sc create VirtualUsbDisk_V01 binPath= C:\Windows\System32\drivers\VirtualUsbDisk.sys type= kernel start= demand
echo 安装完成！请执行【2】加载U盘进入写入模式！
pause >nul
goto menu

:load_write
echo 正在加载驱动，插入U盘【解锁写入模式】...
sc start VirtualUsbDisk_V01
devcon rescan
echo 加载完成！U盘已插入，当前为【可写状态】！
echo 可操作：格式化U盘、拷贝文件到U盘、写入数据、修改内容！
echo 路径：D:\vf\ 下的文件已自动预加载到U盘根目录！
pause >nul
goto menu

:lock_permanent
echo ==============================================
echo ★警告★：此操作是【永久只读锁定】，不可逆！
echo 锁定后：U盘仅能读取文件，无法写入/格式化/删除！
echo 锁定后：重启/插拔/重装驱动外，无任何解锁方式！
echo ==============================================
set /p confirm=确认永久锁定只读？输入【YES】确认，其他取消：
if /i "%confirm%"=="YES" (
    echo 正在执行内核级永久只读锁定...
    sc control VirtualUsbDisk_V01 1
    devcon rescan
    echo ✅ 永久只读锁定成功！U盘已转为只读状态！
) else (
    echo 已取消锁定操作，U盘保持可写状态！
)
pause >nul
goto menu

:toggle_temp
echo 正在切换只读/解锁状态 (仅未永久锁定时有效)...
sc control VirtualUsbDisk_V01 2
devcon rescan
echo 状态切换完成！当前状态：若为只读则解锁，若为可写则临时只读！
pause >nul
goto menu

:unload
echo 正在拔出虚拟U盘并停止驱动服务...
sc stop VirtualUsbDisk_V01
devcon remove "@root\ASM_VirtualUSB64_V01" 2>nul
devcon remove "@root\ASM_VirtualUSB32_V01" 2>nul
echo 拔出完成！U盘已从系统中移除，服务保留可重新加载！
pause >nul
goto menu

:uninstall
echo 正在彻底卸载驱动并删除服务...
sc stop VirtualUsbDisk_V01
sc delete VirtualUsbDisk_V01
pnputil /delete-driver setup_V01.inf /uninstall
del /f /q C:\Windows\System32\drivers\VirtualUsbDisk.sys
echo 卸载完成！所有驱动文件和服务已清理干净！
pause >nul
goto menu