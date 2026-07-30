param(
  [ValidateRange(10, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(640, 3840)]
  [int]$SurfaceWidth = 700,
  [ValidateRange(480, 2160)]
  [int]$SurfaceHeight = 520,
  [string]$SampleDirectory = ".local/qa/natural-compression-ab/samples",
  [string]$OutputDirectory = ".local/qa/native-output-size-ab",
  [string]$OnlyCase = "",
  [string]$OnlyMode = "",
  [switch]$RunResizeGate,
  [switch]$SkipPlayback
)

$ErrorActionPreference = "Stop"

<#
 * 原生输出尺寸 A/B 复用固定自然片源、PID 绑定、窗口截图和 GPU/内存采样器。
 * 对照组保持 1920×1080，实验组只启用带去抖与实际 Texture 确认的稳定档位。
#>
$runnerArguments = @{
  DurationSeconds = $DurationSeconds
  SurfaceWidth = $SurfaceWidth
  SurfaceHeight = $SurfaceHeight
  SampleDirectory = $SampleDirectory
  OutputDirectory = $OutputDirectory
  OnlyCase = $OnlyCase
  OnlyMode = $OnlyMode
  Experiment = "native-output"
  RunNativeOutputGate = $RunResizeGate
  SkipPlayback = $SkipPlayback
}

& (Join-Path $PSScriptRoot "run_downscale_quality_ab.ps1") @runnerArguments
