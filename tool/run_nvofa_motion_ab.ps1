param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(300, 1200)]
  [int]$VideoBitrateKbps = 650,
  [string]$OutputDirectory = ".local/qa/nvofa-motion-ab",
  [string]$CaseManifest = "",
  [string]$Workspace = "",
  [switch]$D3D11VaZeroCopyQa
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
 * 默认使用三类匿名自然片源；CaseManifest 可切换到隔离生成的连续运动压力集。
 * 插件和 R78 均来自本机 QA 路径，不安装、不复制，也不进入正式 Flutter bundle。
#>
$samplePolicy = "isolated CC BY 3.0 natural low-bitrate clips"
if ([string]::IsNullOrWhiteSpace($CaseManifest)) {
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
  if (@($cases |
        Where-Object {
          -not (Test-Path -LiteralPath $_.samplePath)
        }).Count -gt 0) {
    & (Join-Path $PSScriptRoot "run_natural_compression_quality_ab.ps1") `
      -DurationSeconds $DurationSeconds `
      -VideoBitrateKbps $VideoBitrateKbps `
      -SkipPlayback
    if ($LASTEXITCODE -ne 0) {
      throw "自然低码率样本生成失败。"
    }
  }
} else {
  $manifestPath = if ([System.IO.Path]::IsPathRooted($CaseManifest)) {
    $CaseManifest
  } else {
    Join-Path $workspace $CaseManifest
  }
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "NVOFA A/B 样本清单不存在：$manifestPath"
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
  $samplePolicy = [string]$manifest.samplePolicy
  $manifestRoot = Split-Path -Parent $manifestPath
  $cases = @($manifest.cases | ForEach-Object {
      $path = [string]$_.samplePath
      $resolvedPath = if ([System.IO.Path]::IsPathRooted($path)) {
        $path
      } else {
        Join-Path $manifestRoot $path
      }
      [ordered]@{
        name = [string]$_.name
        category = [string]$_.category
        qualityFocus = [string]$_.qualityFocus
        samplePath = [System.IO.Path]::GetFullPath($resolvedPath)
      }
    })
  if ($cases.Count -eq 0 -or
      @($cases |
        Where-Object {
          -not (Test-Path -LiteralPath $_.samplePath -PathType Leaf)
        }).Count -gt 0) {
    throw "NVOFA A/B 样本清单为空或包含缺失文件。"
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
$pluginHash = (Get-FileHash -LiteralPath $plugin -Algorithm SHA256).
  Hash.ToLowerInvariant()

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
  if ($D3D11VaZeroCopyQa) {
    # 仅在隔离 A/B 请求直接采样解码表面；正式播放默认保持 mpv 的兼容复制。
    $env:LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA = "1"
  }
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
    Remove-Item Env:LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    throw "NVOFA 插帧 A/B 失败：$($Case.name) / $Mode"
  }
  [System.IO.File]::WriteAllText(
    (Join-Path $modeOutput "plugin-sha256.txt"),
    "$pluginHash`n",
    [System.Text.UTF8Encoding]::new($false))
}

function Test-MotionModeComplete {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $modeOutput = Join-Path (Join-Path $output $Case.name) $Mode
  $report = Join-Path $modeOutput "$Mode-player-baseline.json"
  $screenshot = Join-Path $modeOutput "$Mode-complete-video.png"
  $log = Join-Path $modeOutput "baseline.log"
  $hashMarker = Join-Path $modeOutput "plugin-sha256.txt"
  if (-not (Test-Path -LiteralPath $report -PathType Leaf) -or
      -not (Test-Path -LiteralPath $screenshot -PathType Leaf) -or
      -not (Test-Path -LiteralPath $log -PathType Leaf) -or
      -not (Test-Path -LiteralPath $hashMarker -PathType Leaf)) {
    return $false
  }

  # Windows 真实窗口连续启动偶发在 native holder 尚未完全释放时退出。
  # 只有同一插件二进制的完整单组证据可以复用，旧 hash、失败或不完整组仍重跑。
  $recordedHash = (Get-Content -LiteralPath $hashMarker -Raw).Trim().
    ToLowerInvariant()
  $recordedReport = Get-Content -LiteralPath $report -Raw -Encoding UTF8 |
    ConvertFrom-Json
  $zeroCopyEvidenceMatches = -not $D3D11VaZeroCopyQa -or
    [string]$recordedReport.d3d11vaZeroCopy -eq "yes"
  return $recordedHash -eq $pluginHash -and
    $zeroCopyEvidenceMatches -and
    [bool](Select-String -LiteralPath $log `
        -SimpleMatch "All tests passed!" -Quiet)
}

foreach ($case in $cases) {
  foreach ($mode in @("nvofa-motion-off", "nvofa-motion-on")) {
    if (Test-MotionModeComplete -Case $case -Mode $mode) {
      Write-Host "复用已通过的 NVOFA A/B 单组证据：$($case.name) / $mode"
      continue
    }
    Invoke-MotionMode -Case $case -Mode $mode
  }
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
  $decoderDrops = @($samples |
      ForEach-Object { $_.decoderDroppedFrames } |
      Where-Object { $null -ne $_ })
  $outputDrops = @($samples |
      ForEach-Object { $_.outputDroppedFrames } |
      Where-Object { $null -ne $_ })
  return [ordered]@{
    mode = $Mode
    estimatedFps = [double](($fpsLine -split ": ")[-1])
    # 原生 mpv 某些构建不暴露分项计数；保留 null，不能把“不可用”伪装成 0。
    maxDecoderDroppedFrames = if ($decoderDrops.Count -gt 0) {
      ($decoderDrops | Measure-Object -Maximum).Maximum
    } else {
      $null
    }
    maxOutputDroppedFrames = if ($outputDrops.Count -gt 0) {
      ($outputDrops | Measure-Object -Maximum).Maximum
    } else {
      $null
    }
    maxTotalDroppedFrames = ($samples |
        Measure-Object -Property totalDroppedFrames -Maximum).Maximum
    videoStallSamples = @($samples |
        Where-Object { $_.videoStalled -eq $true }).Count
    audioStallSamples = @($samples |
        Where-Object { $_.audioStalled -eq $true }).Count
    activeAdapterStatus = [string]$report.activeAdapter.probeStatus
    activeAdapterSource = [string]$report.activeAdapter.detectionSource
    activeAdapterLuid = [string]$report.activeAdapter.adapterLuid
    d3d11vaZeroCopy = [string]$report.d3d11vaZeroCopy
    screenshot = Join-Path $modeRoot "$Mode-complete-video.png"
  }
}

$caseSummaries = foreach ($case in $cases) {
  $off = Get-MotionSummary -Case $case -Mode "nvofa-motion-off"
  $on = Get-MotionSummary -Case $case -Mode "nvofa-motion-on"
  $fpsGate = $off.estimatedFps -ge 23.5 -and $off.estimatedFps -le 24.5 -and
    $on.estimatedFps -ge 47.5
  $decoderDropGate =
    ($null -eq $off.maxDecoderDroppedFrames -and
      $null -eq $on.maxDecoderDroppedFrames) -or
    ($null -ne $off.maxDecoderDroppedFrames -and
      $null -ne $on.maxDecoderDroppedFrames -and
      $on.maxDecoderDroppedFrames -le $off.maxDecoderDroppedFrames)
  $outputDropGate =
    ($null -eq $off.maxOutputDroppedFrames -and
      $null -eq $on.maxOutputDroppedFrames) -or
    ($null -ne $off.maxOutputDroppedFrames -and
      $null -ne $on.maxOutputDroppedFrames -and
      $on.maxOutputDroppedFrames -le $off.maxOutputDroppedFrames)
  $performanceGate =
    $decoderDropGate -and
    $outputDropGate -and
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
  $zeroCopyGate = -not $D3D11VaZeroCopyQa -or
    ($off.d3d11vaZeroCopy -eq "yes" -and
      $on.d3d11vaZeroCopy -eq "yes")
  $caseSummary = [ordered]@{
    name = $case.name
    category = $case.category
    off = $off
    on = $on
    frameRateGatePassed = $fpsGate
    performanceGatePassed = $performanceGate
    adapterLuidGatePassed = $adapterGate
    d3d11vaZeroCopyGatePassed = $zeroCopyGate
    passed = $fpsGate -and $performanceGate -and $adapterGate -and $zeroCopyGate
  }
  if (-not [string]::IsNullOrWhiteSpace($case.qualityFocus)) {
    $caseSummary["qualityFocus"] = $case.qualityFocus
  }
  $caseSummary
}

$summary = [ordered]@{
  schemaVersion = 6
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  runtimePolicy = "local-only VapourSynth R78 and NVOFA plugin; no install"
  samplePolicy = $samplePolicy
  pluginSha256 = $pluginHash
  d3d11vaZeroCopyQa = [bool]$D3D11VaZeroCopyQa
  interpolationPolicy =
    "24fps to 48fps with exact D3D11/CUDA LUID, forward/backward validation, local flow infill, image-domain hole fill, conservative blending, and scene-cut protection"
  productEnablement =
    "blocked; runtime gates do not replace multi-frame visual review"
  cases = @($caseSummaries)
  allRuntimeGatesPassed =
    @($caseSummaries | Where-Object { -not $_.passed }).Count -eq 0
  allGatesPassed =
    @($caseSummaries | Where-Object { -not $_.passed }).Count -eq 0
}
$summaryPath = Join-Path $output "summary.json"
$summary | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "NVOFA motion A/B summary: $summaryPath"
if (-not $summary.allGatesPassed) {
  throw "至少一个 NVOFA A/B 片源的帧率或性能门禁未通过。"
}
