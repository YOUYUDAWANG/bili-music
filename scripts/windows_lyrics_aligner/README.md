# Windows offline lyrics aligner

This experiment runs outside the iOS playback path. The precision path is:

1. BS-RoFormer vocal separation.
2. Qwen3-ASR-1.7B song diagnostics plus BF16 Qwen forced alignment.
3. A unique-line offset consensus followed by ownership-bounded line passes.
4. Japanese WhisperX CTC verification.
5. Consensus QRC export: models must agree within 0.8 seconds; otherwise the
   stable whole-song anchor owns the line. Low-confidence rhythm fallbacks are
   explicitly recorded in JSON.

Output preserves the complete display text and rejects non-monotonic lines.

The deployed runtime is isolated under `D:\BiliMusicAligner` and does not use
the machine's ComfyUI Python environment.

Validated environment:

- RTX 5070 Ti 16GB
- Qwen: Python 3.12, `qwen-asr==0.0.6`, PyTorch `2.13.0+cu130`
- Separator: `audio-separator==0.44.5`, `librosa==0.10.2.post1`, CUDA PyTorch
- WhisperX: `whisperx==3.8.6`, PyTorch `2.8.0+cu128`

Run from PowerShell:

```powershell
D:\BiliMusicAligner\scripts\run_offline.ps1 `
  -Audio D:\path\song.m4a `
  -Library D:\path\lyrics-library.json `
  -Bvid BVxxxxxxxxx
```

## App service

`precision_host_server.py` exposes the same pipeline as a serial, authenticated
LAN service. Jobs are asynchronous and deterministic: repeating the same
`bvid + cid + lyrics` request reuses the completed result. The iPhone uploads
audio only when the host does not already have that job.

Install the per-user startup task from PowerShell (run once as Administrator if
Windows also needs the Private-network firewall rule):

```powershell
D:\BiliMusicAligner\scripts\install_precision_host.ps1
```

The service listens on TCP 8765. Its bearer token stays in
`D:\BiliMusicAligner\server-token.txt`; do not commit or copy that token into
documentation. App requests skip the diagnostic whole-song ASR pass because it
does not participate in the final consensus, reducing latency without changing
the precision result.
