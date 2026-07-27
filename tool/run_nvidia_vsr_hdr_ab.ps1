param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(300, 1200)]
  [int]$VideoBitrateKbps = 650,
  [string]$OutputDirectory = ".local/qa/nvidia-vsr-hdr-ab",
  [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"

<#
 * 组合门禁复用 TrueHDR 的三类自然片源、独立进程和掉帧统计，
 * 但要求 VSR 与 TrueHDR 在同一 d3d11va non-copy 会话中同时被驱动确认。
#>
& (Join-Path $PSScriptRoot "run_nvidia_true_hdr_ab.ps1") `
  -DurationSeconds $DurationSeconds `
  -VideoBitrateKbps $VideoBitrateKbps `
  -OutputDirectory $OutputDirectory `
  -Workspace $Workspace `
  -CombinedVsr
if ($LASTEXITCODE -ne 0) {
  throw "NVIDIA VSR + TrueHDR 组合 A/B 未通过。"
}
