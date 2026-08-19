param(
    [Parameter(Mandatory = $true)][string]$Audio,
    [Parameter(Mandatory = $true)][string]$Library,
    [Parameter(Mandatory = $true)][string]$Bvid,
    [string]$JobId = "",
    [string]$Language = "Japanese",
    [switch]$SkipDiagnostics,
    [string]$Root = "D:\BiliMusicAligner"
)

$ErrorActionPreference = "Stop"
$outputKey = if ($JobId) { $JobId } else { $Bvid }
if ($outputKey -notmatch '^[A-Za-z0-9_-]+$') { throw "Invalid output key" }
$job = Join-Path $Root ("outputs\" + $outputKey)
$fullWav = Join-Path $job "source-full.wav"
$stems = Join-Path $job "stems"
$raw = Join-Path $job "raw"
$refined = Join-Path $job "refined"
$whisperx = Join-Path $job "whisperx"
$consensus = Join-Path $job "consensus"
New-Item -ItemType Directory -Force -Path $job, $stems, $raw, $refined, $whisperx, $consensus | Out-Null

ffmpeg -hide_banner -loglevel error -y -i $Audio -c:a pcm_s16le $fullWav
if ($LASTEXITCODE -ne 0) { throw "FFmpeg normalization failed" }

& "$Root\.venv-separator\Scripts\audio-separator.exe" `
    $fullWav `
    --output_dir $stems `
    --model_file_dir "$Root\separator-models" `
    --output_format WAV
if ($LASTEXITCODE -ne 0) { throw "Vocal separation failed" }
$vocals = Get-ChildItem $stems -Filter "*_(Vocals)_*.wav" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $vocals) { throw "Vocal stem was not produced" }

$env:HF_HOME = "$Root\models"
if (-not $SkipDiagnostics) {
    & "$Root\.venv\Scripts\python.exe" "$Root\scripts\run_alignment.py" `
        --audio $vocals.FullName --library $Library --bvid $Bvid --output $raw --language $Language
    if ($LASTEXITCODE -ne 0) { throw "Qwen full-song diagnostics failed" }
}

& "$Root\.venv\Scripts\python.exe" "$Root\scripts\refine_segments.py" `
    --vocals $vocals.FullName --library $Library --bvid $Bvid --output $refined --language $Language
if ($LASTEXITCODE -ne 0) { throw "Qwen segment refinement failed" }

$whisperXLanguage = switch ($Language.ToLowerInvariant()) {
    { $_ -in @("japanese", "ja") } { "ja"; break }
    { $_ -in @("chinese", "zh", "mandarin") } { "zh"; break }
    { $_ -in @("korean", "ko") } { "ko"; break }
    { $_ -in @("english", "en") } { "en"; break }
    default { throw "Unsupported language: $Language" }
}

& "$Root\.venv-whisperx\Scripts\python.exe" "$Root\scripts\run_whisperx_alignment.py" `
    --vocals $vocals.FullName `
    --qwen-report (Join-Path $refined "$Bvid-segment-refinement.json") `
    --output $whisperx `
    --model-cache "$Root\whisperx-models" `
    --language-code $whisperXLanguage
if ($LASTEXITCODE -ne 0) { throw "WhisperX verification failed" }

& "$Root\.venv\Scripts\python.exe" "$Root\scripts\build_consensus.py" `
    --qwen-report (Join-Path $refined "$Bvid-segment-refinement.json") `
    --whisperx-report (Join-Path $whisperx ($Bvid + "-whisperx.json")) `
    --output $consensus
if ($LASTEXITCODE -ne 0) { throw "Consensus export failed" }

Get-ChildItem $consensus | Select-Object FullName, Length
