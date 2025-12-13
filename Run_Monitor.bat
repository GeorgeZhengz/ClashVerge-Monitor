@echo off
chcp 65001 >nul
setlocal

:: 日志文件（记录自启动执行情况）
set "LOG=%~dp0startup.log"
echo ========= %date% %time% =========>>"%LOG%"
echo [INFO] batch started>>"%LOG%"

:: 延时启动以等待系统就绪（可选）
timeout /t 10 /nobreak >nul
echo [INFO] after delay, switching dir...>>"%LOG%"

:: 切换到脚本所在目录（关键修复）
cd /d "%~dp0"
echo [INFO] cwd=%cd%>>"%LOG%"

:: 创建一个临时的 VBS 脚本来静默启动 PowerShell
set "TMP_VBS=%temp%\start_monitor.vbs"
echo Set WshShell = CreateObject("WScript.Shell") > "%TMP_VBS%"
echo WshShell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%~dp0TrayMonitor.ps1"" -LogPath ""%LOG%""", 0, False >> "%TMP_VBS%"
echo [INFO] vbs written: %TMP_VBS%>>"%LOG%"

:: 运行 VBS 脚本
wscript "%TMP_VBS%"
echo [INFO] wscript launched, exitcode=%errorlevel%>>"%LOG%"

:: 清理临时文件
del "%TMP_VBS%" 2>nul
echo [INFO] cleanup done>>"%LOG%"
exit
