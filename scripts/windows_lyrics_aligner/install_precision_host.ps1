param(
    [string]$Root = "D:\BiliMusicAligner",
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$taskName = "BiliMusic Precision Lyrics Host"
$script = Join-Path $Root "scripts\start_precision_host.ps1"
$action = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Root `"$Root`" -Port $Port"

schtasks.exe /Create /TN $taskName /SC ONLOGON /TR $action /F | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not create the precision host startup task" }

try {
    $existing = Get-NetFirewallRule -DisplayName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule `
            -DisplayName $taskName `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $Port `
            -Profile Private | Out-Null
    }
} catch {
    Write-Warning "Could not create the Private-network firewall rule. Run this script once as Administrator."
}

schtasks.exe /Run /TN $taskName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not start the precision host task" }
Write-Output "Precision host task installed on port $Port"
