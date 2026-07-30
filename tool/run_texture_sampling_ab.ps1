param(
  [ValidateRange(10, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(640, 3840)]
  [int]$SurfaceWidth = 1440,
  [ValidateRange(480, 2160)]
  [int]$SurfaceHeight = 900,
  [string]$SampleDirectory = ".local/qa/natural-compression-ab/samples",
  [string]$OutputDirectory = ".local/qa/texture-sampling-ab",
  [string]$OnlyCase = "",
  [string]$OnlyMode = "",
  [switch]$SkipPlayback
)

$ErrorActionPreference = "Stop"

<#
 * Flutter Texture 采样 A/B 复用既有 PID 绑定、固定帧截图与性能采集器，
 * 只把实验模式收敛为 low / medium / high，避免复制两套容易漂移的窗口采证逻辑。
#>
$runnerArguments = @{
  DurationSeconds = $DurationSeconds
  SurfaceWidth = $SurfaceWidth
  SurfaceHeight = $SurfaceHeight
  SampleDirectory = $SampleDirectory
  OutputDirectory = $OutputDirectory
  OnlyCase = $OnlyCase
  OnlyMode = $OnlyMode
  Experiment = "flutter-texture"
  SkipPlayback = $SkipPlayback
}

& (Join-Path $PSScriptRoot "run_downscale_quality_ab.ps1") @runnerArguments
