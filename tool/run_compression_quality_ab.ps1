param(
  [ValidateRange(20, 180)]
  [int]$DurationSeconds = 30,
  [ValidateRange(200, 1200)]
  [int]$VideoBitrateKbps = 450,
  [string]$OutputDirectory = ".local/qa/compression-quality-ab"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$output = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace $OutputDirectory)
)
$sampleDirectory = Join-Path $workspace ".local/qa/fixed-samples"
$samplePath = Join-Path $sampleDirectory `
  "fixed-low-bitrate-1080p-${VideoBitrateKbps}k.mp4"
$ffmpeg = Join-Path $workspace "windows/tools/ffmpeg/bin/ffmpeg.exe"
$ffprobe = Join-Path $workspace "windows/tools/ffmpeg/bin/ffprobe.exe"
if (-not (Test-Path -LiteralPath $ffmpeg) -or
    -not (Test-Path -LiteralPath $ffprobe)) {
  throw "Bundled FFmpeg or FFprobe is unavailable."
}
New-Item -ItemType Directory -Force -Path $output, $sampleDirectory |
  Out-Null

<#
 * 生成包含运动、渐变和细线的确定性低码率 1080P 样本。
 *
 * 样本只写入 `.local/qa`，不读取用户媒体库；低码率用于稳定复现宏块、蚊噪和
 * 渐变断层，A/B 两轮始终复用同一文件。
 *
 * 行尾保留 ASCII 注释终止行，兼容 Windows PowerShell 5.1 对无 BOM UTF-8
 * 脚本的历史解码行为。
#>
$sampleSeconds = $DurationSeconds + 30
$sampleValid = $false
if (Test-Path -LiteralPath $samplePath) {
  try {
    $duration = & $ffprobe -v error -show_entries format=duration `
      -of default=noprint_wrappers=1:nokey=1 $samplePath
    $bitRate = & $ffprobe -v error -show_entries format=bit_rate `
      -of default=noprint_wrappers=1:nokey=1 $samplePath
    $sampleValid = [double]$duration -ge ($sampleSeconds - 0.5) -and
      [double]$bitRate -le (($VideoBitrateKbps + 80) * 1000)
  } catch {
    $sampleValid = $false
  }
}
if (-not $sampleValid) {
  $temporaryPath = Join-Path $sampleDirectory `
    "fixed-low-bitrate-1080p.partial.mp4"
  Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
  $filter = "testsrc2=size=1920x1080:rate=30," +
    "drawgrid=width=96:height=96:thickness=1:color=white@0.18," +
    "format=yuv420p"
  & $ffmpeg -hide_banner -loglevel error -y `
    -f lavfi -i $filter -t $sampleSeconds -an `
    -c:v libx264 -preset veryfast `
    -b:v "${VideoBitrateKbps}k" `
    -maxrate "$($VideoBitrateKbps + 80)k" `
    -bufsize "$($VideoBitrateKbps * 2)k" `
    -g 60 -keyint_min 60 -sc_threshold 0 `
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
    -color_range tv -movflags +faststart `
    -metadata title="Local Tag Player fixed low bitrate 1080P QA sample" `
    $temporaryPath
  if ($LASTEXITCODE -ne 0) {
    throw "Low bitrate sample generation failed: $LASTEXITCODE"
  }
  Move-Item -LiteralPath $temporaryPath -Destination $samplePath -Force
}

<#
 * 在真实 Windows MediaKit 窗口中运行单个档位，并保存匿名诊断和后端视频帧。
 *
#>
function Invoke-CompressionMode {
  param([Parameter(Mandatory = $true)][string]$Mode)

  $modeOutput = Join-Path $output $Mode
  New-Item -ItemType Directory -Force -Path $modeOutput | Out-Null
  $env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH = $samplePath
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT = $modeOutput
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE = $Mode
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS = $DurationSeconds.ToString()
  try {
    Push-Location $workspace
    & flutter test integration_test/player_fixed_quality_baseline_test.dart `
      -d windows *>&1 |
      Tee-Object -FilePath (Join-Path $modeOutput "baseline.log")
    $testExitCode = $LASTEXITCODE
  } finally {
    Pop-Location
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS `
      -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    throw "Compression quality mode failed: $Mode ($testExitCode)"
  }
}

Invoke-CompressionMode -Mode "compression-off"
Invoke-CompressionMode -Mode "compression-clarity"

# 从两轮匿名时间序列提取掉帧上限，形成不包含本机路径的 A/B 摘要。
#
function Get-ModeSummary {
  param([Parameter(Mandatory = $true)][string]$Mode)

  $reportPath = Join-Path (Join-Path $output $Mode) `
    "$Mode-player-baseline.json"
  # Dart 产物固定为 UTF-8；显式指定编码，避免 Windows PowerShell 5.1 按系统代码页误读中文诊断。
  #
  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
  $samples = @($report.samples)
  $decoderMaximum = ($samples |
      Measure-Object -Property decoderDroppedFrames -Maximum).Maximum
  $outputMaximum = ($samples |
      Measure-Object -Property outputDroppedFrames -Maximum).Maximum
  $totalMaximum = ($samples |
      Measure-Object -Property totalDroppedFrames -Maximum).Maximum
  $videoStallCount = @($samples |
      Where-Object { $_.videoStalled -eq $true }).Count
  $audioStallCount = @($samples |
      Where-Object { $_.audioStalled -eq $true }).Count
  return [ordered]@{
    mode = $Mode
    sampleCount = $samples.Count
    maxDecoderDroppedFrames = $decoderMaximum
    maxOutputDroppedFrames = $outputMaximum
    maxTotalDroppedFrames = $totalMaximum
    videoStallSamples = $videoStallCount
    audioStallSamples = $audioStallCount
    finalDiagnostics = $report.finalDiagnostics
  }
}

$summary = [ordered]@{
  schemaVersion = 1
  sample = [ordered]@{
    width = 1920
    height = 1080
    frameRate = 30
    requestedVideoBitrateKbps = $VideoBitrateKbps
    captureSecond = 12
  }
  off = Get-ModeSummary -Mode "compression-off"
  clarity = Get-ModeSummary -Mode "compression-clarity"
  glslSharpenDecision = "pending visual review; not implemented"
}
$summary | ConvertTo-Json -Depth 8 |
  Set-Content -LiteralPath (Join-Path $output "compression-ab-summary.json") `
    -Encoding utf8

Write-Host "Compression quality A/B completed: $output"
