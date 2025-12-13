<#
.SYNOPSIS
    Clash Verge Configuration & Monitor Installer
#>

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

function Pause-And-Exit {
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Clash Verge Monitor Installer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Find Clash Verge Profile Directory
$AppData = [System.Environment]::GetFolderPath('ApplicationData')
$ClashProfileDir = Join-Path $AppData "io.github.clash-verge-rev.clash-verge-rev\profiles"

Write-Host "Searching for Clash Verge profile directory..."
if (-not (Test-Path $ClashProfileDir)) {
    Write-Warning "Default profile directory not found: $ClashProfileDir"
    Write-Host "Please manually enter your Clash Verge profiles directory path (Press Enter to exit):"
    $UserInput = Read-Host
    if ([string]::IsNullOrWhiteSpace($UserInput)) {
        Write-Error "No path provided. Installation aborted."
        Pause-And-Exit
    }
    $ClashProfileDir = $UserInput
}

if (-not (Test-Path $ClashProfileDir)) {
    Write-Error "Directory does not exist: $ClashProfileDir"
    Pause-And-Exit
}

Write-Host "Target Directory: $ClashProfileDir" -ForegroundColor Green

# 2. Copy Config File
$SourceConfig = Join-Path $ScriptDir "stable-config.yaml"
$DestConfig = Join-Path $ClashProfileDir "stable-config.yaml"

Write-Host "`nInstalling configuration file..."
try {
    Copy-Item -Path $SourceConfig -Destination $DestConfig -Force
    Write-Host "Config copied to: $DestConfig" -ForegroundColor Green
    Write-Host "Please go to Clash Verge -> Right click 'Profiles' -> 'Refresh', then select 'stable-config'." -ForegroundColor Yellow
} catch {
    Write-Error "Failed to copy config file: $_"
    Pause-And-Exit
}

# 3. Setup Startup Shortcut
Write-Host "`nSetting up startup shortcut..."
$StartupDir = [System.Environment]::GetFolderPath('Startup')
$TargetBat = Join-Path $ScriptDir "Run_Monitor.bat"
$LnkPath = Join-Path $StartupDir "VPN_Clash_Monitor.lnk"

if (-not (Test-Path $TargetBat)) {
    Write-Error "Startup script not found: $TargetBat"
    Pause-And-Exit
}

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($LnkPath)
    $Shortcut.TargetPath = $TargetBat
    $Shortcut.WorkingDirectory = $ScriptDir
    $Shortcut.WindowStyle = 7 # Minimized
    $Shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,18" # Network Icon
    $Shortcut.Description = "Clash Monitor AutoStart"
    $Shortcut.Save()
    
    Write-Host "Startup shortcut created: $LnkPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to create shortcut: $_"
    Pause-And-Exit
}

# 4. Start Monitor Now
Write-Host "`nStart the monitor now? (Y/N)"
$RunNow = Read-Host
if ($RunNow -eq 'Y' -or $RunNow -eq 'y') {
    Start-Process $TargetBat
    Write-Host "Monitor started (Check your system tray)" -ForegroundColor Green
}

Write-Host "`nInstallation Complete!" -ForegroundColor Cyan
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
