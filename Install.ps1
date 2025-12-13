<#
.SYNOPSIS
    Clash Verge 配置与监控一键安装脚本
#>

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Clash Verge 稳定配置 & 监控安装程序" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. 查找 Clash Verge 配置目录
$AppData = [System.Environment]::GetFolderPath('ApplicationData')
$ClashProfileDir = Join-Path $AppData "io.github.clash-verge-rev.clash-verge-rev\profiles"

Write-Host "正在查找 Clash Verge 配置目录..."
if (-not (Test-Path $ClashProfileDir)) {
    Write-Warning "未找到默认配置目录: $ClashProfileDir"
    Write-Host "请手动输入您的 Clash Verge profiles 目录路径 (直接回车退出):"
    $UserInput = Read-Host
    if ([string]::IsNullOrWhiteSpace($UserInput)) {
        Write-Error "未提供路径，安装终止。"
        exit
    }
    $ClashProfileDir = $UserInput
}

if (-not (Test-Path $ClashProfileDir)) {
    Write-Error "目录不存在: $ClashProfileDir"
    exit
}

Write-Host "目标目录: $ClashProfileDir" -ForegroundColor Green

# 2. 复制配置文件
$SourceConfig = Join-Path $ScriptDir "stable-config.yaml"
$DestConfig = Join-Path $ClashProfileDir "stable-config.yaml"

Write-Host "`n正在安装配置文件..."
try {
    Copy-Item -Path $SourceConfig -Destination $DestConfig -Force
    Write-Host "配置文件已复制到: $DestConfig" -ForegroundColor Green
    Write-Host "请在 Clash Verge 中右键 'Profiles' -> 'Refresh'，然后选择 'stable-config'。" -ForegroundColor Yellow
} catch {
    Write-Error "复制配置文件失败: $_"
    exit
}

# 3. 设置开机自启监控
Write-Host "`n正在设置监控程序开机自启..."
$StartupDir = [System.Environment]::GetFolderPath('Startup')
$TargetBat = Join-Path $ScriptDir "Run_Monitor.bat"
$LnkPath = Join-Path $StartupDir "VPN_Clash_Monitor.lnk"

if (-not (Test-Path $TargetBat)) {
    Write-Error "找不到启动脚本: $TargetBat"
    exit
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
    
    Write-Host "开机自启快捷方式已创建: $LnkPath" -ForegroundColor Green
} catch {
    Write-Error "创建快捷方式失败: $_"
    exit
}

# 4. 立即启动监控
Write-Host "`n是否立即启动监控程序? (Y/N)"
$RunNow = Read-Host
if ($RunNow -eq 'Y' -or $RunNow -eq 'y') {
    Start-Process $TargetBat
    Write-Host "监控程序已启动 (请检查托盘图标)" -ForegroundColor Green
}

Write-Host "`n安装完成！" -ForegroundColor Cyan
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
