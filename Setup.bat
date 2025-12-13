@echo off
cd /d "%~dp0"
echo Starting Installer...
powershell -NoProfile -ExecutionPolicy Bypass -File "Install.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [Error] Installation script failed.
)
pause