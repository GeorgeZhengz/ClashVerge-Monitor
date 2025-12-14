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
$FailThreshold = 6            # Restart after 6 consecutive fails (approx 30s)
$ApiPort = 9097               # Default updated to 9097 based on common config
$ApiSecret = "set-your-secret" # Default updated
$script:AutoRestartEnabled = $true
$script:FailCount = 0

# --- Auto-Discover Clash Config (Port & Secret) ---
function Get-ClashConfig {
    $paths = @(
        "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev\config.yaml",
        "$env:APPDATA\clash-verge\config.yaml",
        "$env:USERPROFILE\.config\clash-verge\config.yaml"
    )
    
    foreach ($path in $paths) {
        Write-Log "Checking config path: $path"
        if (Test-Path $path) {
            Write-Log "Found Clash Config: $path"
            try {
                # Force UTF8 to handle any characters correctly
                $content = Get-Content $path -Raw -Encoding UTF8
                
                # Parse Secret
                # Regex handles quoted or unquoted secrets
                if ($content -match "secret:\s*['`"]?([^'`"\r\n]+)['`"]?") {
                    $foundSecret = $matches[1].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($foundSecret)) {
                        $global:ApiSecret = $foundSecret
                        Write-Log "Auto-detected API Secret: $global:ApiSecret"
                    }
                }
                
                # Parse Port (external-controller: 127.0.0.1:9090)
                if ($content -match "external-controller:\s*.*?(\d{4,5})") {
                    $global:ApiPort = $matches[1]
                    Write-Log "Auto-detected API Port: $global:ApiPort"
                }
                return
            } catch {
                Write-Log "Error reading config: $_"
            }
        }
    }
    Write-Log "No Clash config found in standard locations. Using defaults: Port=$global:ApiPort, Secret=$global:ApiSecret"
}

# Run discovery
Get-ClashConfig

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

# Start on Boot Toggle
$menuItemStartOnBoot = New-Object System.Windows.Forms.MenuItem
$menuItemStartOnBoot.Text = "Start on Boot"
$StartupLnkPath = Join-Path ([System.Environment]::GetFolderPath('Startup')) "VPN_Clash_Monitor.lnk"
$menuItemStartOnBoot.Checked = (Test-Path $StartupLnkPath)

$menuItemStartOnBoot.add_Click({
    $menuItemStartOnBoot.Checked = -not $menuItemStartOnBoot.Checked
    if ($menuItemStartOnBoot.Checked) {
        # Enable Start on Boot
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($StartupLnkPath)
            $Shortcut.TargetPath = Join-Path $PSScriptRoot "Run_Monitor.bat"
            $Shortcut.WorkingDirectory = $PSScriptRoot
            $Shortcut.WindowStyle = 7 # Minimized
            $Shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,18"
            $Shortcut.Description = "Clash Monitor AutoStart"
            $Shortcut.Save()
            Write-Log "Start on Boot Enabled"
        } catch {
            Write-Log "Failed to enable Start on Boot: $_"
            $menuItemStartOnBoot.Checked = $false # Revert if failed
        }
    } else {
        # Disable Start on Boot
        try {
            if (Test-Path $StartupLnkPath) {
                Remove-Item $StartupLnkPath -Force
                Write-Log "Start on Boot Disabled"
            }
        } catch {
            Write-Log "Failed to disable Start on Boot: $_"
            $menuItemStartOnBoot.Checked = $true # Revert if failed
        }
    }
})
$contextMenu.MenuItems.Add($menuItemStartOnBoot) | Out-Null

# Show Report
$menuItemReport = New-Object System.Windows.Forms.MenuItem
$menuItemReport.Text = "Show Daily Report"
$menuItemReport.add_Click({
    Show-Report
})
$contextMenu.MenuItems.Add($menuItemReport) | Out-Null

# Debug Info
$menuItemDebug = New-Object System.Windows.Forms.MenuItem
$menuItemDebug.Text = "Show Debug Info"
$menuItemDebug.add_Click({
    $msg = "API Port: $global:ApiPort`nAPI Secret: $global:ApiSecret`nClash Path: $ClashPath`nLast Status: $script:CurrentStatus`nFail Count: $script:FailCount"
    [System.Windows.Forms.MessageBox]::Show($msg, "Debug Info")
})
$contextMenu.MenuItems.Add($menuItemDebug) | Out-Null

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

# --- Statistics & Reporting ---
$StatsPath = "$PSScriptRoot\NodeStats.json"
$script:StatsCache = @{}
$script:LastSaveTime = Get-Date
$script:LastChartTime = Get-Date
$script:ProviderMap = @{}
$script:LastProviderMapTime = [DateTime]::MinValue

# Load existing stats
if (Test-Path $StatsPath) {
    try {
        # Use .NET directly to avoid PowerShell encoding issues
        $jsonContent = [System.IO.File]::ReadAllText($StatsPath, [System.Text.Encoding]::UTF8)
        if ($jsonContent) {
            $script:StatsCache = $jsonContent | ConvertFrom-Json -AsHashtable
        }
    } catch {
        Write-Log "Error loading stats: $_"
    }
}

function Get-ProviderForNode {
    param($NodeName)
    
    if ([string]::IsNullOrEmpty($NodeName)) { return "Unknown-Provider" }

    # Update map every 10 minutes or if empty
    if ($script:ProviderMap.Count -eq 0 -or (Get-Date) -gt $script:LastProviderMapTime.AddMinutes(10)) {
        try {
            $headers = @{}
            if ($ApiSecret -ne "") { $headers["Authorization"] = "Bearer $ApiSecret" }
            $uri = "http://127.0.0.1:$ApiPort/providers/proxies"
            # Removed -TimeoutSec for PS 5.1 compatibility
            $json = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            
            if ($json -and $json.providers) {
                $newMap = @{}
                # Handle PSObject properties safely
                $providers = $json.providers
                if ($providers -is [System.Management.Automation.PSCustomObject]) {
                    $propNames = $providers.PSObject.Properties.Name
                } elseif ($providers -is [System.Collections.IDictionary]) {
                    $propNames = $providers.Keys
                } else {
                    $propNames = @()
                }

                foreach ($providerName in $propNames) {
                    if ($providerName -eq "default" -or $providerName -eq "compatible") { continue }
                    $proxies = $providers.$providerName.proxies
                    if ($proxies) {
                        foreach ($proxy in $proxies) {
                            $newMap[$proxy.name] = $providerName
                        }
                    }
                }
                $script:ProviderMap = $newMap
                $script:LastProviderMapTime = Get-Date
                Write-Log "Provider Map Updated. Count: $($newMap.Count)"
            }
        } catch {
            Write-Log "Failed to update provider map: $_"
        }
    }
    
    if ($script:ProviderMap.ContainsKey($NodeName)) {
        return $script:ProviderMap[$NodeName]
    }
    return "Unknown-Provider"
}

function Update-Stats {
    param($Status, $NodeName, $ProviderName, $DurationInc)
    
    $Today = Get-Date -Format 'yyyy-MM-dd'
    if (-not $script:StatsCache.ContainsKey($Today)) {
        $script:StatsCache[$Today] = @{}
    }
    
    if (-not $script:StatsCache[$Today].ContainsKey($ProviderName)) {
        $script:StatsCache[$Today][$ProviderName] = @{ 
            SuccessCount = 0; 
            FailCount = 0; 
            TotalDuration = 0;
            Nodes = @{} 
        }
    }
    
    $pStats = $script:StatsCache[$Today][$ProviderName]
    
    # Update Provider Stats
    if ($Status -eq "Success") {
        $pStats.SuccessCount++
        $pStats.TotalDuration += $DurationInc
    } else {
        $pStats.FailCount++
    }
    
    # Update Node Stats (Nested)
    if (-not $pStats.Nodes.ContainsKey($NodeName)) {
        $pStats.Nodes[$NodeName] = @{ Success = 0; Fail = 0; Duration = 0 }
    }
    $nStats = $pStats.Nodes[$NodeName]
    if ($Status -eq "Success") {
        $nStats.Success++
        $nStats.Duration += $DurationInc
    } else {
        $nStats.Fail++
    }
    
    # Save every 5 minutes (Update Panel)
    if ((Get-Date) -gt $script:LastSaveTime.AddMinutes(5)) {
        try {
            # Use .NET directly to ensure strict UTF-8 writing
            $jsonStr = $script:StatsCache | ConvertTo-Json -Depth 5
            if ($jsonStr -is [array]) { $jsonStr = $jsonStr -join "`r`n" }
            [System.IO.File]::WriteAllText($StatsPath, $jsonStr, [System.Text.Encoding]::UTF8)
            
            $script:LastSaveTime = Get-Date
            Write-Log "Stats saved to disk (5 min update)."
        } catch {
            Write-Log "Error saving stats: $_"
        }
    }
}

function Generate-Chart {
    $Today = Get-Date -Format 'yyyy-MM-dd'
    if (-not $script:StatsCache.ContainsKey($Today)) { return }
    
    # Create Daily Report Folder
    $ReportDir = "$PSScriptRoot\Reports\$Today"
    if (-not (Test-Path $ReportDir)) {
        New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    }

    $TimeStr = Get-Date -Format 'HH-mm'
    $ReportPath = "$ReportDir\Report_$TimeStr.html"
    $JsonPath = "$ReportDir\Stats_$TimeStr.json"
    
    $Data = $script:StatsCache[$Today]
    
    # Save Raw JSON Snapshot
    try {
        $jsonStr = $Data | ConvertTo-Json -Depth 5
        if ($jsonStr -is [array]) { $jsonStr = $jsonStr -join "`r`n" }
        [System.IO.File]::WriteAllText($JsonPath, $jsonStr, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Log "Failed to save JSON snapshot: $_"
    }

    # Calculate Best Provider
    $BestProvider = "None"
    $BestScore = -1
    
    $Rows = ""
    foreach ($pName in $Data.Keys) {
        $p = $Data[$pName]
        $Total = $p.SuccessCount + $p.FailCount
        $Rate = 0
        if ($Total -gt 0) { $Rate = [math]::Round(($p.SuccessCount / $Total) * 100, 1) }
        $DurationMins = [math]::Round($p.TotalDuration / 60, 1)
        
        # Simple Score: Rate * Duration (Favor stability over time)
        $Score = $Rate * $DurationMins
        if ($Score -gt $BestScore) {
            $BestScore = $Score
            $BestProvider = $pName
        }
        
        $Rows += "<tr><td><strong>$pName</strong></td><td>$($p.SuccessCount)</td><td>$($p.FailCount)</td><td>$Rate%</td><td>$DurationMins min</td></tr>"
        
        # Add Node Details
        if ($p.Nodes) {
            foreach ($nName in $p.Nodes.Keys) {
                $n = $p.Nodes[$nName]
                $nTotal = $n.Success + $n.Fail
                $nRate = 0
                if ($nTotal -gt 0) { $nRate = [math]::Round(($n.Success / $nTotal) * 100, 1) }
                $nDuration = [math]::Round($n.Duration / 60, 1)
                
                $Rows += "<tr class='node-row'><td class='node-name'>&#9492;&#9472; $nName</td><td>$($n.Success)</td><td>$($n.Fail)</td><td>$nRate%</td><td>$nDuration min</td></tr>"
            }
        }
    }
    
    $Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Clash Proxy Report</title>
<style>
body { font-family: 'Segoe UI', sans-serif; padding: 20px; background: #f0f0f0; }
.container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
table { border-collapse: collapse; width: 100%; margin-top: 20px; }
th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
th { background-color: #0078d4; color: white; }
tr:nth-child(even) { background-color: #f9f9f9; }
.best { color: #107c10; font-weight: bold; font-size: 1.2em; margin: 10px 0; }
.timestamp { color: #666; font-size: 0.9em; }
.node-row { background-color: #f0f8ff; font-size: 0.9em; color: #555; }
.node-name { padding-left: 30px; }
</style>
</head>
<body>
<div class="container">
<h2>Clash Proxy Daily Report ($Today)</h2>
<p class="timestamp">Generated at: $(Get-Date -Format 'HH:mm:ss')</p>
<div class="best">&#127942; Best Performing Provider: $BestProvider</div>
<table>
<tr><th>Provider / Node</th><th>Success Checks</th><th>Fail Checks</th><th>Success Rate</th><th>Connected Duration</th></tr>
$Rows
</table>
</div>
</body>
</html>
"@
    # Use .NET directly to ensure strict UTF-8 writing (Fixes Emoji/Chinese issues)
    [System.IO.File]::WriteAllText($ReportPath, $Html, [System.Text.Encoding]::UTF8)
    Write-Log "Chart Generated: $ReportPath"
}

function Show-Report {
    # Open the Daily Report Folder
    $Today = Get-Date -Format 'yyyy-MM-dd'
    $ReportDir = "$PSScriptRoot\Reports\$Today"
    
    if (Test-Path $ReportDir) {
        Invoke-Item $ReportDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("No reports generated for today yet. Wait for the next update (every 10 mins).", "Clash Monitor")
    }
}

function Get-CurrentNode {
    # Try to get the selected proxy from the "节点选择" group
    $url = "http://127.0.0.1:$ApiPort/proxies/节点选择"
    try {
        $headers = @{}
        if ($ApiSecret -ne "") { $headers["Authorization"] = "Bearer $ApiSecret" }
        
        # Removed -TimeoutSec for PS 5.1 compatibility
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        if ($response -and $response.now) {
            return $response.now
        }
        return "UnknownNode"
    } catch {
        return "UnknownNode"
    }
}

# --- Check Logic ---
$CurrentStatus = "Unknown"

# --- Helper for Web Request with Timeout (PS 5.1 Compatible) ---
function Invoke-HttpReq {
    param($Uri, $Method="HEAD", $ProxyUrl=$null, $TimeoutSec=3)
    try {
        $request = [System.Net.WebRequest]::Create($Uri)
        $request.Method = $Method
        $request.Timeout = $TimeoutSec * 1000
        if ($ProxyUrl) {
            $request.Proxy = New-Object System.Net.WebProxy($ProxyUrl)
        }
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

# --- Helper for API Request with Timeout ---
function Invoke-ApiReq {
    param($Uri, $TimeoutSec=2)
    try {
        $request = [System.Net.WebRequest]::Create($Uri)
        $request.Method = "GET"
        $request.Timeout = $TimeoutSec * 1000
        if ($ApiSecret -ne "") { $request.Headers.Add("Authorization", "Bearer $ApiSecret") }
        
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $json = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        
        return $json | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-CurrentNode {
    $url = "http://127.0.0.1:$ApiPort/proxies"
    $json = Invoke-ApiReq -Uri $url -TimeoutSec 2
    
    if (-not $json -or -not $json.proxies) { return "UnknownNode" }
    
    $proxies = $json.proxies
    
    # Dynamic Discovery: Find the Main Selector
    # Heuristic: The selector with the most proxies is likely the main one.
    # This avoids encoding issues with hardcoded Chinese names.
    
    $target = "GLOBAL"
    $maxCount = -1
    
    # Get keys safely
    $keys = @()
    if ($proxies -is [System.Management.Automation.PSCustomObject]) {
        $keys = $proxies.PSObject.Properties.Name
    } elseif ($proxies -is [System.Collections.IDictionary]) {
        $keys = $proxies.Keys
    }

    foreach ($key in $keys) {
        if ($key -eq "GLOBAL") { continue }
        
        $p = $proxies.$key
        if ($p.type -eq "Selector") {
            $count = 0
            if ($p.all) { $count = $p.all.Count }
            
            # Exclude small selectors that are likely just rule groups (usually 2-3 items like DIRECT/REJECT)
            # But keep track of the biggest one regardless
            if ($count -gt $maxCount) {
                $maxCount = $count
                $target = $key
            }
        }
    }
    
    # Resolve chain (max 5 hops to find leaf node)
    $curr = $target
    for ($i = 0; $i -lt 5; $i++) {
        if (-not $proxies.PSObject.Properties[$curr]) { return $curr }
        $nodeData = $proxies.$curr
        
        if ($nodeData.now) {
            $curr = $nodeData.now
        } else {
            return $curr
        }
    }
    return $curr
}

function Get-ProviderForNode {
    param($NodeName)
    if ([string]::IsNullOrEmpty($NodeName)) { return "Unknown-Provider" }
    
    # Special handling for System/Built-in nodes
    if ($NodeName -eq "DIRECT" -or $NodeName -eq "REJECT") { return "System" }

    # Update map every 10 minutes or if empty
    if ($script:ProviderMap.Count -eq 0 -or (Get-Date) -gt $script:LastProviderMapTime.AddMinutes(10)) {
        $uri = "http://127.0.0.1:$ApiPort/providers/proxies"
        $json = Invoke-ApiReq -Uri $uri -TimeoutSec 2
        
        if ($json -and $json.providers) {
            $newMap = @{}
            $providers = $json.providers
            # Handle different object types from ConvertFrom-Json
            if ($providers -is [System.Management.Automation.PSCustomObject]) {
                $propNames = $providers.PSObject.Properties.Name
            } elseif ($providers -is [System.Collections.IDictionary]) {
                $propNames = $providers.Keys
            } else {
                $propNames = @()
            }

            foreach ($providerName in $propNames) {
                if ($providerName -eq "default" -or $providerName -eq "compatible") { continue }
                $proxies = $providers.$providerName.proxies
                if ($proxies) {
                    foreach ($proxy in $proxies) {
                        # Skip built-in types in provider map to avoid overwriting real providers
                        if ($proxy.name -eq "DIRECT" -or $proxy.name -eq "REJECT") { continue }
                        $newMap[$proxy.name] = $providerName
                    }
                }
            }
            $script:ProviderMap = $newMap
            $script:LastProviderMapTime = Get-Date
            Write-Log "Provider Map Updated. Count: $($newMap.Count)"
        }
    }
    
    if ($script:ProviderMap.ContainsKey($NodeName)) {
        return $script:ProviderMap[$NodeName]
    }
    return "Unknown-Provider"
}

# --- Check Logic ---
$CurrentStatus = "Unknown"

function Check-Connection {
    try {
        # Get current node name from Clash API
        $CurrentNode = Get-CurrentNode
        if ([string]::IsNullOrEmpty($CurrentNode)) { $CurrentNode = "UnknownNode" }
        
        $CurrentProvider = Get-ProviderForNode -NodeName $CurrentNode

        $success = $false
        
        # Primary Check (Google)
        if (Invoke-HttpReq -Uri $Url -ProxyUrl $Proxy -TimeoutSec 3) {
            $success = $true
        } else {
            # Fallback Check (Baidu)
            if (Invoke-HttpReq -Uri "http://www.baidu.com" -ProxyUrl $Proxy -TimeoutSec 3) {
                $success = $true
            }
        }
        
        if ($success) {
            # Success: Add CheckInterval (converted to seconds) to duration
            Update-Stats -Status "Success" -NodeName $CurrentNode -ProviderName $CurrentProvider -DurationInc ($CheckInterval / 1000)

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
                Write-Log "Status OK ($CurrentProvider - $CurrentNode)"
            }
            
            # Truncate text to fit Tray Icon limit (63 chars)
            $shortProvider = $CurrentProvider
            if ($shortProvider.Length -gt 15) { $shortProvider = $shortProvider.Substring(0,12) + "..." }
            
            $shortNode = $CurrentNode
            if ($shortNode.Length -gt 25) { $shortNode = $shortNode.Substring(0,22) + "..." }

            $txt = "OK: $shortProvider`n$shortNode`n$(Get-Date -Format 'HH:mm:ss')"
            if ($txt.Length -gt 63) { $txt = $txt.Substring(0, 60) + "..." }
            $notifyIcon.Text = $txt
        }
        else {
            # Failure Logic
            # 1. Check Internal Network (Ping AliDNS) to rule out ISP failure
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
            
            Update-Stats -Status "Fail" -NodeName $CurrentNode -ProviderName $CurrentProvider -DurationInc 0

            if ($script:CurrentStatus -ne "Fail") {
                $notifyIcon.Icon = $IconBad
                $script:CurrentStatus = "Fail"
                Write-Host "!" -NoNewline -ForegroundColor Red
                Write-Log "Status FAIL ($CurrentProvider)"
            }
            
            $statusMsg = "Clash Status: Disconnected`nFail Count: $($script:FailCount)/$FailThreshold"
            
            if ($script:AutoRestartEnabled -and $script:FailCount -ge $FailThreshold) {
                $statusMsg += "`nRestarting App..."
                Write-Host "R" -NoNewline -ForegroundColor Yellow
                Restart-ClashApp
                $script:FailCount = 0 # Reset count to give it time to restart
            }
            
            $notifyIcon.Text = $statusMsg
        }
        
        # Hourly Chart Generation
        if ((Get-Date) -gt $script:LastChartTime.AddHours(1)) {
            Generate-Chart
            $script:LastChartTime = Get-Date
        }
    } catch {
        Write-Log "Critical Error in Check-Connection: $_"
        $errTxt = "Monitor Error:`n$($_.Exception.Message)"
        if ($errTxt.Length -gt 63) { $errTxt = $errTxt.Substring(0, 60) + "..." }
        $notifyIcon.Text = $errTxt
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
try { 
    $notifyIcon.Text = "Clash Monitor: Starting..."
    Check-Connection 
} catch {
    Write-Log "First run failed: $_"
}

Write-Host "`nRunning. Close this window to keep running in background (if launched via bat)." -ForegroundColor Gray
Write-Log "Run loop entered"
[System.Windows.Forms.Application]::Run()

