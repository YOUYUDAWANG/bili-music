param(
    [string]$Root = "D:\BiliMusicAligner",
    [int]$Port = 8765
)

$ErrorActionPreference = "Continue"
$logDirectory = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$logFile = Join-Path $logDirectory "precision-host.log"
& "$Root\.venv\Scripts\python.exe" "$Root\scripts\precision_host_server.py" `
    --root $Root `
    --host 0.0.0.0 `
    --port $Port `
    --token-file (Join-Path $Root "server-token.txt") *>> $logFile
