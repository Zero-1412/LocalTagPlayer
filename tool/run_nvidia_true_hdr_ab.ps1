param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(300, 1200)]
  [int]$VideoBitrateKbps = 650,
  [string]$OutputDirectory = ".local/qa/nvidia-true-hdr-ab",
  [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"
$workspace = if ([string]::IsNullOrWhiteSpace($Workspace)) {
  Split-Path -Parent $PSScriptRoot
} else {
  [System.IO.Path]::GetFullPath($Workspace)
}
$output = [System.IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
$sampleRoot = Join-Path $workspace ".local/qa/natural-compression-ab/samples"
New-Item -ItemType Directory -Force -Path $output | Out-Null

<#
 * TrueHDR A/B 复用三类匿名自然低码率 SDR 样本，不读取用户媒体库。
 * 每个模式使用独立进程，防止 D3D11 视频处理器和掉帧计数跨样本残留。
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

# 在独立 Windows 集成测试进程中运行一个 TrueHDR 模式。
function Invoke-TrueHdrMode {
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
    throw "NVIDIA TrueHDR A/B 失败：$($Case.name) / $Mode"
  }
}

foreach ($case in $cases) {
  Invoke-TrueHdrMode -Case $case -Mode "nvidia-hdr-off"
  Invoke-TrueHdrMode -Case $case -Mode "nvidia-hdr-on"
}

# 从匿名时间序列和固定诊断字段提取驱动、滤镜与性能证据。
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
    finalDiagnostics = @($report.finalDiagnostics)
  }
}

$caseSummaries = foreach ($case in $cases) {
  $off = Get-ModeSummary -Case $case -Mode "nvidia-hdr-off"
  $on = Get-ModeSummary -Case $case -Mode "nvidia-hdr-on"
  $driverActive =
    @($on.finalDiagnostics | Where-Object {
        $_ -eq "NVIDIA HDR 驱动确认: active"
      }).Count -eq 1
  $filterLine = @($on.finalDiagnostics | Where-Object {
      $_ -like "mpv 视频滤镜:*"
    }) | Select-Object -First 1
  $filterGate =
    $filterLine -like "*nvidia-true-hdr*" -and
    $filterLine -notlike "*format=nv12*"
  $performanceGate =
    $on.maxDecoderDroppedFrames -le $off.maxDecoderDroppedFrames -and
    $on.maxOutputDroppedFrames -le $off.maxOutputDroppedFrames -and
    $on.maxTotalDroppedFrames -le $off.maxTotalDroppedFrames -and
    $on.videoStallSamples -eq 0 -and
    $on.audioStallSamples -eq 0
  [ordered]@{
    name = $case.name
    category = $case.category
    samplePath = $case.samplePath
    off = $off
    on = $on
    driverGatePassed = $driverActive
    filterGatePassed = $filterGate
    performanceGatePassed = $performanceGate
    passed = $driverActive -and $filterGate -and $performanceGate
  }
}

$summary = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  decoderPolicy = "d3d11va non-copy for both A/B modes"
  filterPolicy = "TrueHDR uses d3d11vpp without forced NV12"
  displayPolicy =
    "Driver activation is verified independently; final HDR display requires Windows HDR and 10-bit output"
  cases = @($caseSummaries)
  allGatesPassed =
    @($caseSummaries | Where-Object { -not $_.passed }).Count -eq 0
}
$summaryPath = Join-Path $output "summary.json"
$summary | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "NVIDIA TrueHDR A/B summary: $summaryPath"
if (-not $summary.allGatesPassed) {
  throw "至少一个自然片源的 NVIDIA TrueHDR 驱动、滤镜或性能门禁未通过。"
}
