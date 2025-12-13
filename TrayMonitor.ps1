<#
.SYNOPSIS
    Clash Verge Status Monitor (Tray Icon Overlay)
#>

# Clear old variables
Remove-Variable * -ErrorAction SilentlyContinue

param(
    [string]$LogPath = "$PSScriptRoot\TrayMonitor.log"
)

function Write-Log {
    param([string]$Message)
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $LogPath -Value "$timestamp $Message"
    } catch {
        # ignore logging errors
    }
}

try {
    Write-Host "1. Loading System Components..." -ForegroundColor Cyan
    Write-Log "Loading components"
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    Write-Error "Failed to load components: $_"
    Write-Log "Failed to load components: $_"
    exit
}

# --- Config ---
$Proxy = 'http://127.0.0.1:7897'
$Url = 'http://www.gstatic.com/generate_204'
$CheckInterval = 5000 
$TimeoutSec = 2

# --- Auto Restart Config ---
$FailThreshold = 3            # Restart after 3 consecutive fails (approx 15s)
$ApiPort = 9097               # Clash Verge API Port
$ApiSecret = "set-your-secret" # API Secret
$script:AutoRestartEnabled = $true
$script:FailCount = 0

# --- Find Clash Process & Icon ---
$ClashPath = ""
$BaseIcon = $null

try {
    Write-Host "2. Searching for Clash Verge..." -ForegroundColor Cyan
    Write-Log "Searching for Clash Verge"
    $proc = Get-Process | Where-Object { $_.ProcessName -like "*clash-verge*" } | Select-Object -First 1 -ExpandProperty Path -ErrorAction SilentlyContinue
    
    if ($proc -and (Test-Path $proc)) {
        $ClashPath = $proc
        Write-Host "   Found: $ClashPath" -ForegroundColor Green
        Write-Log "Found clash path: $ClashPath"
        $BaseIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($ClashPath)
    } else {
        # Fallback path if process not running
        $fallback = "D:\Program Files\Clash Verge\clash-verge.exe"
        if (Test-Path $fallback) {
            $ClashPath = $fallback
            Write-Host "   Found (Path): $ClashPath" -ForegroundColor Green
            Write-Log "Found clash path (fallback): $ClashPath"
            $BaseIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($ClashPath)
        } else {
            Write-Warning "   Clash Verge not found. Using generic icon."
            Write-Log "Clash Verge not found"
        }
    }
} catch {
    Write-Warning "   Error finding Clash icon: $_"
    Write-Log "Error finding Clash icon: $_"
}

# --- Icon Generation Function ---
function Create-OverlayIcon {
    param($BaseIcon, $Color)
    
    $size = 32 # Use 32x32 for better quality
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

    if ($BaseIcon) {
        # Draw Clash Icon
        $g.DrawIcon($BaseIcon, 0, 0)
    } else {
        # Draw Generic Box if no icon
        $g.FillRectangle([System.Drawing.Brushes]::Gray, 4, 4, 24, 24)
    }

    # Draw Status Dot (Bottom Right)
    $dotSize = 10
    $x = $size - $dotSize - 1
    $y = $size - $dotSize - 1
    
    $brush = New-Object System.Drawing.SolidBrush($Color)
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
    
    # Draw white border for visibility
    $g.DrawEllipse($borderPen, $x, $y, $dotSize, $dotSize)
    # Draw colored dot
    $g.FillEllipse($brush, $x, $y, $dotSize, $dotSize)
    
    $hIcon = $bitmap.GetHicon()
    return [System.Drawing.Icon]::FromHandle($hIcon)
}

# --- Pre-generate Icons (Cache) ---
Write-Host "3. Generating Status Icons..." -ForegroundColor Cyan
Write-Log "Generating status icons"
try {
    $IconGood    = Create-OverlayIcon -BaseIcon $BaseIcon -Color ([System.Drawing.Color]::LimeGreen)
    $IconBad     = Create-OverlayIcon -BaseIcon $BaseIcon -Color ([System.Drawing.Color]::Red)
    $IconWait    = Create-OverlayIcon -BaseIcon $BaseIcon -Color ([System.Drawing.Color]::Orange)
    $IconRestart = Create-OverlayIcon -BaseIcon $BaseIcon -Color ([System.Drawing.Color]::Yellow)
} catch {
    Write-Error "Failed to generate icons: $_"
    Write-Log "Failed to generate icons: $_"
    exit
}

# --- Init Tray Icon ---
try {
    Write-Host "4. Initializing Tray..." -ForegroundColor Cyan
    Write-Log "Initializing tray"
    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Text = "Clash Monitor: Initializing..."
    $notifyIcon.Icon = $IconWait
    $notifyIcon.Visible = $true
    
    # Double Click -> Open Clash
    $notifyIcon.add_MouseDoubleClick({
        if ($ClashPath) {
            Write-Log "Double click: launching clash"
            Start-Process $ClashPath
        }
    })
} catch {
    Write-Error "Tray init failed: $_"
    Write-Log "Tray init failed: $_"
    exit
}

# --- Context Menu ---
$contextMenu = New-Object System.Windows.Forms.ContextMenu

# Auto Restart Toggle
$menuItemAutoRestart = New-Object System.Windows.Forms.MenuItem
$menuItemAutoRestart.Text = "Enable Auto Restart"
$menuItemAutoRestart.Checked = $true
$menuItemAutoRestart.add_Click({
    $menuItemAutoRestart.Checked = -not $menuItemAutoRestart.Checked
    $script:AutoRestartEnabled = $menuItemAutoRestart.Checked
    Write-Log "Auto Restart Toggled: $($script:AutoRestartEnabled)"
})
$contextMenu.MenuItems.Add($menuItemAutoRestart) | Out-Null

$menuItemExit = New-Object System.Windows.Forms.MenuItem
$menuItemExit.Text = "Exit Monitor"
$menuItemExit.add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.MenuItems.Add($menuItemExit) | Out-Null
$notifyIcon.ContextMenu = $contextMenu

# --- Restart Logic ---
function Restart-ClashApp {
    Write-Log "Attempting to restart Clash Application..."
    
    # Set icon to Yellow (Restarting)
    $notifyIcon.Icon = $IconRestart
    
    if (-not $ClashPath -or -not (Test-Path $ClashPath)) {
        Write-Log "Clash executable path not found. Cannot restart."
        $notifyIcon.BalloonTipTitle = "Clash Monitor"
        $notifyIcon.BalloonTipText = "Cannot restart: Clash path not found."
        $notifyIcon.ShowBalloonTip(3000)
        return $false
    }

    try {
        # Stop existing processes
        $procs = Get-Process | Where-Object { $_.ProcessName -like "*clash-verge*" }
        if ($procs) {
            Write-Log "Stopping $($procs.Count) Clash processes..."
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        # Start application
        Write-Log "Starting Clash Verge from: $ClashPath"
        Start-Process -FilePath $ClashPath
        
        $notifyIcon.BalloonTipTitle = "Clash Monitor"
        $notifyIcon.BalloonTipText = "Connection failed. Restarting Clash App..."
        $notifyIcon.ShowBalloonTip(3000)
        return $true
    } catch {
        Write-Log "Restart failed: $($_.Exception.Message)"
        return $false
    }
}

# --- Check Logic ---
$CurrentStatus = "Unknown"

function Check-Connection {
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -Proxy $Proxy -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        
        # Reset fail count on success
        if ($script:FailCount -gt 0) {
            $script:FailCount = 0
            Write-Log "Connection recovered"
        }

        # Only update if status changed (reduce flicker)
        if ($script:CurrentStatus -ne "OK") {
            $notifyIcon.Icon = $IconGood
            $script:CurrentStatus = "OK"
            Write-Host "." -NoNewline -ForegroundColor Green
            Write-Log "Status OK"
        }
        $notifyIcon.Text = "Clash Status: Connected`nTime: $(Get-Date -Format 'HH:mm:ss')"
    }
    catch {
        # 1. Check Internal Network (Ping AliDNS) to rule out ISP failure
        # Use Quiet to return bool. Timeout is default (usually 1s per ping)
        $NetUp = Test-Connection -ComputerName "223.5.5.5" -Count 1 -Quiet -ErrorAction SilentlyContinue
        
        if (-not $NetUp) {
            # Network is down completely
            if ($script:CurrentStatus -ne "NoNet") {
                $notifyIcon.Icon = $IconWait # Use Orange/Wait icon for No Net
                $script:CurrentStatus = "NoNet"
                Write-Host "x" -NoNewline -ForegroundColor Gray
                Write-Log "Status: Network Down (Ping Failed)"
            }
            $notifyIcon.Text = "System Network Down`nCheck your internet connection."
            return # Skip proxy restart logic
        }

        # 2. Network is UP, but Proxy Failed -> Real Proxy Issue
        $script:FailCount++
        
        if ($script:CurrentStatus -ne "Fail") {
            $notifyIcon.Icon = $IconBad
            $script:CurrentStatus = "Fail"
            Write-Host "!" -NoNewline -ForegroundColor Red
            Write-Log "Status FAIL: $($_.Exception.Message)"
        }
        
        $statusMsg = "Clash Status: Disconnected`nFail Count: $($script:FailCount)/$FailThreshold"
        
        if ($script:AutoRestartEnabled -and $script:FailCount -ge $FailThreshold) {
            $statusMsg += "`nRestarting App..."
            Write-Host "R" -NoNewline -ForegroundColor Yellow
            Restart-ClashApp
            $script:FailCount = 0 # Reset count to give it time to restart
            # Optional: Pause timer briefly?
        }
        
        $notifyIcon.Text = $statusMsg
    }
}

# --- Timer ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $CheckInterval
$timer.add_Tick({
    $timer.Stop()
    Check-Connection
    $timer.Start()
})

Write-Host "5. Starting Loop..." -ForegroundColor Cyan
Write-Log "Starting loop"
$timer.Start()

# First Run
try { Check-Connection } catch {}

Write-Host "`nRunning. Close this window to keep running in background (if launched via bat)." -ForegroundColor Gray
Write-Log "Run loop entered"
[System.Windows.Forms.Application]::Run()

