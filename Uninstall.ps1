<#
.SYNOPSIS
    Clash Verge Monitor Uninstaller
#>

$ErrorActionPreference = 'Stop'

function Pause-And-Exit {
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Clash Verge Monitor Uninstaller" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Stop the Monitor Process
Write-Host "Stopping Monitor Process..."
try {
    # Try to find the powershell process running TrayMonitor.ps1
    $procs = Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like "*TrayMonitor.ps1*" }
    
    if ($procs) {
        foreach ($p in $procs) {
             Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
             Write-Host "Stopped process ID: $($p.ProcessId)" -ForegroundColor Green
        }
    } else {
        Write-Host "Monitor process not found (or already stopped)."
    }
} catch {
    Write-Warning "Could not stop process automatically. Please check system tray."
}

# 2. Remove Startup Shortcut
$StartupDir = [System.Environment]::GetFolderPath('Startup')
$LnkPath = Join-Path $StartupDir "VPN_Clash_Monitor.lnk"

if (Test-Path $LnkPath) {
    try {
        Remove-Item -Path $LnkPath -Force
        Write-Host "Removed Startup Shortcut: $LnkPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to remove shortcut: $_"
    }
} else {
    Write-Host "Startup shortcut not found."
}

# 3. Remove Config File
$AppData = [System.Environment]::GetFolderPath('ApplicationData')
$ClashProfileDir = Join-Path $AppData "io.github.clash-verge-rev.clash-verge-rev\profiles"

if (-not (Test-Path $ClashProfileDir)) {
    Write-Warning "Default profile directory not found."
    Write-Host "If you installed to a custom location, please enter the path to remove stable-config.yaml (Press Enter to skip):"
    $UserInput = Read-Host
    if (-not [string]::IsNullOrWhiteSpace($UserInput)) {
        $ClashProfileDir = $UserInput
    }
}

if (Test-Path $ClashProfileDir) {
    $DestConfig = Join-Path $ClashProfileDir "stable-config.yaml"
    if (Test-Path $DestConfig) {
        try {
            Remove-Item -Path $DestConfig -Force
            Write-Host "Removed config file: $DestConfig" -ForegroundColor Green
            Write-Host "Note: Please switch to another profile in Clash Verge." -ForegroundColor Yellow
        } catch {
            Write-Error "Failed to remove config file: $_"
        }
    } else {
        Write-Host "Config file not found in: $ClashProfileDir"
    }
}

Write-Host "`nUninstallation Complete!" -ForegroundColor Cyan
Pause-And-Exit
