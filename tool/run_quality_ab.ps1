param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('mpv-downscale', 'flutter-texture', 'native-output')]
  [string]$Preset,
  [ValidateRange(10, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(0, 3840)]
  [int]$SurfaceWidth = 0,
  [ValidateRange(0, 2160)]
  [int]$SurfaceHeight = 0,
  [string]$SampleDirectory = '.local/qa/natural-compression-ab/samples',
  [string]$OutputDirectory = '',
  [string]$OnlyCase = '',
  [string]$OnlyMode = '',
  [switch]$RunResizeGate,
  [switch]$SkipPlayback
)

$ErrorActionPreference = 'Stop'

<#
 * 三类画质实验只声明 preset 和少量覆盖参数；固定片源、窗口采证、PID 绑定、
 * 性能采样与结果格式统一由 run_downscale_quality_ab.ps1 拥有，避免 wrapper 漂移。
#>
$presets = @{
  'mpv-downscale' = @{
    experiment = 'mpv-downscale'
    width = 1440
    height = 900
    output = '.local/qa/downscale-quality-ab'
  }
  'flutter-texture' = @{
    experiment = 'flutter-texture'
    width = 1440
    height = 900
    output = '.local/qa/texture-sampling-ab'
  }
  'native-output' = @{
    experiment = 'native-output'
    width = 700
    height = 520
    output = '.local/qa/native-output-size-ab'
  }
}
$selected = $presets[$Preset]
$effectiveWidth = if ($SurfaceWidth -gt 0) { $SurfaceWidth } else { $selected.width }
$effectiveHeight = if ($SurfaceHeight -gt 0) { $SurfaceHeight } else { $selected.height }
$effectiveOutput = if ($OutputDirectory) { $OutputDirectory } else { $selected.output }

$runnerArguments = @{
  DurationSeconds = $DurationSeconds
  SurfaceWidth = $effectiveWidth
  SurfaceHeight = $effectiveHeight
  SampleDirectory = $SampleDirectory
  OutputDirectory = $effectiveOutput
  OnlyCase = $OnlyCase
  OnlyMode = $OnlyMode
  Experiment = $selected.experiment
  RunNativeOutputGate = ($Preset -eq 'native-output' -and $RunResizeGate)
  SkipPlayback = $SkipPlayback
}

& (Join-Path $PSScriptRoot 'run_downscale_quality_ab.ps1') @runnerArguments
