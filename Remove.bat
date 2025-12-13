@echo off
cd /d "%~dp0"
echo Starting Uninstaller...
powershell -NoProfile -ExecutionPolicy Bypass -File "Uninstall.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [Error] Uninstallation script failed.
)
pause