param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(300, 1200)]
  [int]$VideoBitrateKbps = 650,
  [string]$OutputDirectory = ".local/qa/nvidia-scaling-ab",
  [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"
$workspace = if ([string]::IsNullOrWhiteSpace($Workspace)) {
  Split-Path -Parent $PSScriptRoot
} else {
  [System.IO.Path]::GetFullPath($Workspace)
}
$output = [System.IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
$naturalRoot = Join-Path $workspace ".local/qa/natural-compression-ab"
$sampleRoot = Join-Path $naturalRoot "samples"
New-Item -ItemType Directory -Force -Path $output | Out-Null

<#
 * NVIDIA A/B 只消费仓库 QA 脚本生成的三类匿名自然样本，不读取用户媒体库。
 * 缺少样本时复用既有生成器；`SkipPlayback` 保证不会顺带运行压缩增强基线。
#>
$cases = @(
  [ordered]@{
    name = "live-face"
    category = "真人面部"
    samplePath = Join-Path $sampleRoot "live-face-low-${VideoBitrateKbps}k.mp4"
  },
  [ordered]@{
    name = "animation-gradient"
    category = "动画渐变"
    samplePath = Join-Path $sampleRoot "animation-gradient-low-${VideoBitrateKbps}k.mp4"
  },
  [ordered]@{
    name = "dark-scene"
    category = "暗场"
    samplePath = Join-Path $sampleRoot "dark-scene-low-${VideoBitrateKbps}k.mp4"
  }
)
if (@($cases | Where-Object { -not (Test-Path -LiteralPath $_.samplePath) }).Count -gt 0) {
  & (Join-Path $PSScriptRoot "run_natural_compression_quality_ab.ps1") `
    -DurationSeconds $DurationSeconds `
    -VideoBitrateKbps $VideoBitrateKbps `
    -SkipPlayback
  if ($LASTEXITCODE -ne 0) {
    throw "自然低码率样本生成失败。"
  }
}

<#
 * 每个模式运行独立 Windows 集成测试进程，确保 mpv 滤镜和掉帧计数不会跨样本残留。
#>
function Invoke-NvidiaMode {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $modeOutput = Join-Path (Join-Path $output $Case.name) $Mode
  New-Item -ItemType Directory -Force -Path $modeOutput | Out-Null
  $env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH = $Case.samplePath
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
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    throw "NVIDIA A/B 失败：$($Case.name) / $Mode"
  }
}

foreach ($case in $cases) {
  Invoke-NvidiaMode -Case $case -Mode "nvidia-off"
  Invoke-NvidiaMode -Case $case -Mode "nvidia-on"
}

<# 从匿名时间序列提取累计掉帧、停滞和最终滤镜证据。 #>
function Get-ModeSummary {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $reportPath = Join-Path `
    (Join-Path (Join-Path $output $Case.name) $Mode) `
    "$Mode-player-baseline.json"
  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
  $samples = @($report.samples)
  return [ordered]@{
    mode = $Mode
    sampleCount = $samples.Count
    maxDecoderDroppedFrames = ($samples |
        Measure-Object -Property decoderDroppedFrames -Maximum).Maximum
    maxOutputDroppedFrames = ($samples |
        Measure-Object -Property outputDroppedFrames -Maximum).Maximum
    maxTotalDroppedFrames = ($samples |
        Measure-Object -Property totalDroppedFrames -Maximum).Maximum
    videoStallSamples = @($samples |
        Where-Object { $_.videoStalled -eq $true }).Count
    audioStallSamples = @($samples |
        Where-Object { $_.audioStalled -eq $true }).Count
    finalDiagnostics = $report.finalDiagnostics
  }
}

$caseSummaries = foreach ($case in $cases) {
  $off = Get-ModeSummary -Case $case -Mode "nvidia-off"
  $on = Get-ModeSummary -Case $case -Mode "nvidia-on"
  [ordered]@{
    name = $case.name
    category = $case.category
    samplePath = $case.samplePath
    off = $off
    on = $on
    performanceGatePassed =
      $on.maxDecoderDroppedFrames -le $off.maxDecoderDroppedFrames -and
      $on.maxOutputDroppedFrames -le $off.maxOutputDroppedFrames -and
      $on.maxTotalDroppedFrames -le $off.maxTotalDroppedFrames -and
      $on.videoStallSamples -eq 0 -and
      $on.audioStallSamples -eq 0
  }
}

$summary = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  decoderPolicy = "d3d11va non-copy for both A/B modes"
  filterPolicy = "NVIDIA d3d11vpp and CPU lavfi are mutually exclusive"
  cases = @($caseSummaries)
  allPerformanceGatesPassed =
    @($caseSummaries | Where-Object { -not $_.performanceGatePassed }).Count -eq 0
}
$summaryPath = Join-Path $output "summary.json"
$summary | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "NVIDIA A/B summary: $summaryPath"
if (-not $summary.allPerformanceGatesPassed) {
  throw "至少一个自然片源的 NVIDIA 掉帧或停滞门禁未通过。"
}
