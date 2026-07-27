param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(300, 1200)]
  [int]$VideoBitrateKbps = 650,
  [string]$OutputDirectory = ".local/qa/nvofa-motion-ab",
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
$runtime = Join-Path $workspace `
  "build\vapoursynth-r78\installed\Lib\site-packages\vapoursynth"
$motionScript = Join-Path $workspace "tool\vapoursynth_nvofa_interpolation.vpy"
$plugin = Join-Path $workspace `
  "build\windows\x64\nvidia_optical_flow_probe\ltp_nvofa_vapoursynth.dll"
New-Item -ItemType Directory -Force -Path $output | Out-Null

<#
 * 本机 NVOFA 插帧 A/B 只使用仓库生成的匿名自然片源。插件和 R78 均来自隔离
 * QA 路径；脚本不安装、不复制，也不把它们加入正式 Flutter bundle。
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

# 先用一条真实 1080P 片源完成构建、硬件 execute、2× 帧率和零新增掉帧门禁。
& (Join-Path $PSScriptRoot "run_nvofa_vapoursynth_interpolation_probe.ps1") `
  -Configuration Release `
  -SamplePath $cases[0].samplePath `
  -PerformanceGate
if ($LASTEXITCODE -ne 0) {
  throw "NVOFA 插帧前置门禁未通过。"
}

function Invoke-MotionMode {
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
  $env:LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR = $runtime
  $env:LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH = $motionScript
  $env:LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH = $plugin
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
    Remove-Item Env:LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    throw "NVOFA 插帧 A/B 失败：$($Case.name) / $Mode"
  }
}

foreach ($case in $cases) {
  Invoke-MotionMode -Case $case -Mode "nvofa-motion-off"
  Invoke-MotionMode -Case $case -Mode "nvofa-motion-on"
}

function Get-MotionSummary {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $modeRoot = Join-Path (Join-Path $output $Case.name) $Mode
  $reportPath = Join-Path $modeRoot "$Mode-player-baseline.json"
  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
  $samples = @($report.samples)
  $fpsLine = @($report.finalDiagnostics |
      Where-Object { $_ -like "mpv 估算视频 FPS:*" }) |
    Select-Object -First 1
  return [ordered]@{
    mode = $Mode
    estimatedFps = [double](($fpsLine -split ": ")[-1])
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
    activeAdapterStatus = [string]$report.activeAdapter.probeStatus
    activeAdapterSource = [string]$report.activeAdapter.detectionSource
    activeAdapterLuid = [string]$report.activeAdapter.adapterLuid
    screenshot = Join-Path $modeRoot "$Mode-complete-video.png"
  }
}

$caseSummaries = foreach ($case in $cases) {
  $off = Get-MotionSummary -Case $case -Mode "nvofa-motion-off"
  $on = Get-MotionSummary -Case $case -Mode "nvofa-motion-on"
  $fpsGate = $off.estimatedFps -ge 23.5 -and $off.estimatedFps -le 24.5 -and
    $on.estimatedFps -ge 47.5
  $performanceGate =
    $on.maxDecoderDroppedFrames -le $off.maxDecoderDroppedFrames -and
    $on.maxOutputDroppedFrames -le $off.maxOutputDroppedFrames -and
    $on.maxTotalDroppedFrames -le $off.maxTotalDroppedFrames -and
    $on.videoStallSamples -eq 0 -and
    $on.audioStallSamples -eq 0
  $adapterGate =
    $off.activeAdapterStatus -eq "ready" -and
    $on.activeAdapterStatus -eq "ready" -and
    $off.activeAdapterSource -eq
      "windows-native-mpv-selected-d3d11-adapter" -and
    $on.activeAdapterSource -eq
      "windows-native-mpv-selected-d3d11-adapter" -and
    -not [string]::IsNullOrWhiteSpace($off.activeAdapterLuid) -and
    $off.activeAdapterLuid -eq $on.activeAdapterLuid
  [ordered]@{
    name = $case.name
    category = $case.category
    off = $off
    on = $on
    frameRateGatePassed = $fpsGate
    performanceGatePassed = $performanceGate
    adapterLuidGatePassed = $adapterGate
    passed = $fpsGate -and $performanceGate -and $adapterGate
  }
}

$summary = [ordered]@{
  schemaVersion = 2
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  runtimePolicy = "local-only VapourSynth R78 and NVOFA plugin; no install"
  interpolationPolicy =
    "24fps to 48fps with exact D3D11/CUDA LUID, forward/backward NVOFA, D3D11 compute warp, and scene-cut protection"
  cases = @($caseSummaries)
  allGatesPassed =
    @($caseSummaries | Where-Object { -not $_.passed }).Count -eq 0
}
$summaryPath = Join-Path $output "summary.json"
$summary | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "NVOFA motion A/B summary: $summaryPath"
if (-not $summary.allGatesPassed) {
  throw "至少一个自然片源的 NVOFA 帧率或性能门禁未通过。"
}
