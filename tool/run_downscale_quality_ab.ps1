param(
  [ValidateRange(10, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(640, 3840)]
  [int]$SurfaceWidth = 1440,
  [ValidateRange(480, 2160)]
  [int]$SurfaceHeight = 900,
  [string]$SampleDirectory = ".local/qa/natural-compression-ab/samples",
  [string]$OutputDirectory = ".local/qa/downscale-quality-ab",
  [string]$OnlyCase = "",
  [string]$OnlyMode = "",
  [ValidateSet("mpv-downscale", "flutter-texture", "native-output")]
  [string]$Experiment = "mpv-downscale",
  [switch]$RunNativeOutputGate,
  [switch]$SkipPlayback
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$samples = [System.IO.Path]::GetFullPath((Join-Path $workspace $SampleDirectory))
$output = [System.IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
New-Item -ItemType Directory -Force -Path $output | Out-Null

<#
 * 三类自然低码率样本固定为同一 650 kbps 编码结果，避免编码器随机性污染缩小 A/B。
 * 测试不读取用户媒体库；缺少样本时要求先运行既有自然片源生成脚本。
#>
$cases = @(
  [ordered]@{
    name = "live-face"
    category = "live-action face"
    path = Join-Path $samples "live-face-low-650k.mp4"
  },
  [ordered]@{
    name = "animation-gradient"
    category = "animated gradient"
    path = Join-Path $samples "animation-gradient-low-650k.mp4"
  },
  [ordered]@{
    name = "dark-scene"
    category = "dark scene"
    path = Join-Path $samples "dark-scene-low-650k.mp4"
  }
)
foreach ($case in $cases) {
  if (-not (Test-Path -LiteralPath $case.path)) {
    throw "缺少固定低码率样本：$($case.path)"
  }
}

<#
 * mpv-downscale 保留既有缩小属性实验；flutter-texture 只改变 Flutter Texture
 * 的 FilterQuality；native-output 比较固定 1080p 与稳定档位输出。三类实验
 * 复用相同片源、窗口、时点与进程指标口径。
#>
$modes = if ($Experiment -eq "flutter-texture") {
  @("texture-low", "texture-medium", "texture-high")
} elseif ($Experiment -eq "native-output") {
  @("native-output-fixed", "native-output-adaptive")
} else {
  @(
    "downscale-current",
    "downscale-lanczos",
    "downscale-lanczos-uncorrected"
  )
}

<# 返回稳定的中位数、P95 与最大值，空样本保持 null。 #>
function Get-MetricSummary {
  param([object[]]$Rows, [string]$Property)
  $values = @($Rows | ForEach-Object {
    $parsed = 0.0
    if ([double]::TryParse($_.$Property, [ref]$parsed)) { $parsed }
  })
  if ($values.Count -eq 0) { return $null }
  $sorted = @($values | Sort-Object)
  return [ordered]@{
    median = [Math]::Round($sorted[[Math]::Floor(($sorted.Count - 1) * 0.5)], 2)
    p95 = [Math]::Round($sorted[[Math]::Floor(($sorted.Count - 1) * 0.95)], 2)
    max = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 2)
  }
}

<#
 * 运行单组真实 MediaKit Texture 会话。
 *
 * 进程指标与窗口截图均绑定 integration test 写出的 PID；窗口截图只在固定 12 秒
 * 标记出现后采集，避免运动内容差异伪装成缩小算法差异。
#>
function Invoke-QualityMode {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $modeOutput = Join-Path (Join-Path $output $Case.name) $Mode
  New-Item -ItemType Directory -Force -Path $modeOutput | Out-Null
  Get-ChildItem -LiteralPath $modeOutput -Filter "*.ready" -ErrorAction SilentlyContinue |
    Remove-Item -Force
  $donePath = Join-Path $modeOutput "downscale.done"
  Remove-Item -LiteralPath $donePath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $modeOutput "process.pid") `
    -Force -ErrorAction SilentlyContinue

  $monitorJob = Start-Job -ArgumentList $modeOutput, $Mode -ScriptBlock {
    param($Output, $Mode)
    $metrics = Join-Path $Output "system-metrics.csv"
    "timestamp,mode,pid,cpu_seconds,threads,working_set_mb,private_mb,responding,gpu_util_percent,gpu_committed_mb" |
      Set-Content -LiteralPath $metrics
    while (-not (Test-Path -LiteralPath (Join-Path $Output "downscale.done"))) {
      $started = Get-Date
      $pidPath = Join-Path $Output "process.pid"
      $process = $null
      if (Test-Path -LiteralPath $pidPath) {
        $testPid = [int]((Get-Content -LiteralPath $pidPath -Raw).Trim())
        $process = Get-Process -Id $testPid -ErrorAction SilentlyContinue
      }
      if ($null -ne $process) {
        $gpuUtil = 0.0
        $gpuCommitted = 0.0
        try {
          $gpu = Get-Counter -Counter @(
            ("\GPU Process Memory(pid_" + $process.Id + "_*)\Total Committed"),
            ("\GPU Engine(pid_" + $process.Id + "_*)\Utilization Percentage")
          ) -ErrorAction Stop
          foreach ($sample in $gpu.CounterSamples) {
            if ($sample.Path -like "*\total committed") {
              $gpuCommitted += $sample.CookedValue
            } elseif ($sample.Path -like "*\utilization percentage") {
              $gpuUtil += $sample.CookedValue
            }
          }
        } catch {}
        "{0},{1},{2},{3:F3},{4},{5:F1},{6:F1},{7},{8:F1},{9:F1}" -f `
          (Get-Date -Format o), $Mode, $process.Id,
          $process.TotalProcessorTime.TotalSeconds, $process.Threads.Count,
          ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB),
          $process.Responding, $gpuUtil, ($gpuCommitted / 1MB) |
          Add-Content -LiteralPath $metrics
      }
      $remainingMs = 1000 - ((Get-Date) - $started).TotalMilliseconds
      if ($remainingMs -gt 0) { Start-Sleep -Milliseconds $remainingMs }
    }
  }

  $captureJob = Start-Job -ArgumentList $modeOutput -ScriptBlock {
    param($Output)
    Add-Type -AssemblyName System.Drawing
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpDownscaleWindowCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
    [LtpDownscaleWindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) |
      Out-Null
    $captured = @{}
    while (-not (Test-Path -LiteralPath (Join-Path $Output "downscale.done"))) {
      foreach ($marker in Get-ChildItem -LiteralPath $Output -Filter "*.ready" `
          -ErrorAction SilentlyContinue) {
        if ($captured.ContainsKey($marker.FullName)) { continue }
        $pidPath = Join-Path $Output "process.pid"
        if (-not (Test-Path -LiteralPath $pidPath)) { continue }
        $testPid = [int]((Get-Content -LiteralPath $pidPath -Raw).Trim())
        $process = Get-Process -Id $testPid -ErrorAction SilentlyContinue
        if ($null -eq $process -or $process.MainWindowHandle -eq 0) { continue }
        $rect = New-Object LtpDownscaleWindowCapture+RECT
        if (-not ([LtpDownscaleWindowCapture]::GetWindowRect(
            $process.MainWindowHandle, [ref]$rect))) { continue }
        $bitmap = [System.Drawing.Bitmap]::new(
          $rect.Right - $rect.Left,
          $rect.Bottom - $rect.Top)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $deviceContext = $graphics.GetHdc()
        $capturedWindow = [LtpDownscaleWindowCapture]::PrintWindow(
          $process.MainWindowHandle, $deviceContext, 2)
        $graphics.ReleaseHdc($deviceContext)
        $graphics.Dispose()
        if (-not $capturedWindow) {
          $bitmap.Dispose()
          throw "固定画质 A/B 的 PrintWindow 失败。"
        }
        $bitmap.Save((Join-Path $Output "$($marker.BaseName)-window.png"))
        $bitmap.Dispose()
        $captured[$marker.FullName] = $true
      }
      Start-Sleep -Milliseconds 150
    }
  }

  $env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH = $Case.path
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT = $modeOutput
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE = $Mode
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS = $DurationSeconds.ToString()
  $env:LOCAL_TAG_PLAYER_QUALITY_SURFACE_WIDTH = $SurfaceWidth.ToString()
  $env:LOCAL_TAG_PLAYER_QUALITY_SURFACE_HEIGHT = $SurfaceHeight.ToString()
  if ($RunNativeOutputGate) {
    $env:LOCAL_TAG_PLAYER_NATIVE_OUTPUT_GATE = "1"
  }
  $logPath = Join-Path $modeOutput "baseline.log"
  try {
    Push-Location $workspace
    & flutter test integration_test/player_fixed_quality_baseline_test.dart `
      -d windows *> $logPath
    $testExitCode = $LASTEXITCODE
  } finally {
    Pop-Location
    New-Item -ItemType File -Force -Path $donePath | Out-Null
    Wait-Job $monitorJob, $captureJob -Timeout 20 | Out-Null
    Receive-Job $monitorJob, $captureJob
    Remove-Job $monitorJob, $captureJob -Force
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SURFACE_WIDTH `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SURFACE_HEIGHT `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_OUTPUT_GATE `
      -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    Get-Content -LiteralPath $logPath -Tail 80
    throw "画质 A/B 失败：$($Case.name) / $Mode"
  }
}

if (-not $SkipPlayback) {
  foreach ($case in $cases |
      Where-Object { [string]::IsNullOrWhiteSpace($OnlyCase) -or
        $_.name -eq $OnlyCase }) {
    foreach ($mode in $modes |
        Where-Object { [string]::IsNullOrWhiteSpace($OnlyMode) -or
          $_ -eq $OnlyMode }) {
      Write-Host "运行画质 A/B：$($case.name) / $mode"
      Invoke-QualityMode -Case $case -Mode $mode
      # Windows integration runner 偶发延迟释放 NativeReference；组间留出短暂收敛窗口。
      Start-Sleep -Seconds 2
    }
  }
}

$caseSummaries = foreach ($case in $cases) {
  $modeSummaries = @(foreach ($mode in $modes) {
    $modeOutput = Join-Path (Join-Path $output $case.name) $mode
    $reportPath = Join-Path $modeOutput "$mode-player-baseline.json"
    $fixedFrameWindow = Join-Path $modeOutput "$mode-complete-window.png"
    # 单组门禁与断点续跑只汇总已经完整产出的模式，不能要求其它组合预先存在。
    if (-not (Test-Path -LiteralPath $reportPath) -or
        -not (Test-Path -LiteralPath $fixedFrameWindow)) {
      continue
    }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding utf8 |
      ConvertFrom-Json
    $rows = @(Import-Csv -LiteralPath (Join-Path $modeOutput "system-metrics.csv"))
    # 进程退出时 Get-Process 可能留下一个空 CPU 尾样本；空值不能按 0 参与差值。
    $cpuSeconds = @($rows |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.cpu_seconds) } |
        ForEach-Object { [double]$_.cpu_seconds })
    $cpuDelta = if ($cpuSeconds.Count -ge 2) {
      $cpuSeconds[-1] - $cpuSeconds[0]
    } else {
      0
    }
    [ordered]@{
      mode = $mode
      diagnosticSamples = @($report.samples).Count
      maxDecoderDroppedFrames = (@($report.samples) |
          Measure-Object -Property decoderDroppedFrames -Maximum).Maximum
      maxOutputDroppedFrames = (@($report.samples) |
          Measure-Object -Property outputDroppedFrames -Maximum).Maximum
      maxTotalDroppedFrames = (@($report.samples) |
          Measure-Object -Property totalDroppedFrames -Maximum).Maximum
      videoStallSamples = @($report.samples |
          Where-Object videoStalled -eq $true).Count
      audioStallSamples = @($report.samples |
          Where-Object audioStalled -eq $true).Count
      processCpuCoreEquivalentPercent =
        [Math]::Round(($cpuDelta / [Math]::Max(1, $report.actualDurationSeconds)) * 100, 2)
      gpuUtilPercent = Get-MetricSummary $rows "gpu_util_percent"
      gpuCommittedMiB = Get-MetricSummary $rows "gpu_committed_mb"
      privateMiB = Get-MetricSummary $rows "private_mb"
      unresponsiveSamples = @($rows | Where-Object responding -ne "True").Count
      finalDiagnostics = $report.finalDiagnostics
      videoSurfaceDiagnostics = $report.videoSurfaceDiagnostics
      nativeOutputResizeGate = $report.nativeOutputResizeGate
      fixedFrameWindow = $fixedFrameWindow
      fixedFrameSha256 =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $fixedFrameWindow).Hash
    }
  })
  if ($modeSummaries.Count -eq 0) {
    continue
  }
  $uniqueFrameHashes =
    @($modeSummaries.fixedFrameSha256 | Select-Object -Unique)
  [ordered]@{
    name = $case.name
    category = $case.category
    modes = @($modeSummaries)
    fixedWindowFramesByteIdentical = $uniqueFrameHashes.Count -eq 1
  }
}

$nativeOutputPerformanceGate = $null
if ($Experiment -eq "native-output") {
  $nativeOutputCaseGates = @(
    foreach ($caseSummary in $caseSummaries) {
      $fixed = @($caseSummary.modes |
          Where-Object mode -eq "native-output-fixed")
      $adaptive = @($caseSummary.modes |
          Where-Object mode -eq "native-output-adaptive")
      # 单模式断点执行没有完整对照组，不应伪造 A/B 结论。
      if ($fixed.Count -ne 1 -or $adaptive.Count -ne 1) { continue }
      $fixedMode = $fixed[0]
      $adaptiveMode = $adaptive[0]
      $surface = $adaptiveMode.videoSurfaceDiagnostics
      $droppedFramesPass =
        [int]$adaptiveMode.maxTotalDroppedFrames -le
        ([int]$fixedMode.maxTotalDroppedFrames + 1)
      $stallPass =
        [int]$adaptiveMode.videoStallSamples -eq 0 -and
        [int]$adaptiveMode.audioStallSamples -eq 0 -and
        [int]$adaptiveMode.unresponsiveSamples -eq 0
      $gpuPass =
        [double]$adaptiveMode.gpuUtilPercent.p95 -le
        ([double]$fixedMode.gpuUtilPercent.p95 + 2.0)
      # 32 MiB 容差覆盖 Windows 进程采样噪声，但禁止新策略显著扩大显存或私有内存。
      $memoryPass =
        [double]$adaptiveMode.gpuCommittedMiB.p95 -le
          ([double]$fixedMode.gpuCommittedMiB.p95 + 32.0) -and
        [double]$adaptiveMode.privateMiB.p95 -le
          ([double]$fixedMode.privateMiB.p95 + 32.0)
      $texturePass =
        $surface.textureResizeState -eq "idle" -and
        [int]$surface.textureResizeFailureCount -eq 0 -and
        [int]$surface.textureResizeRequestCount -ge 1 -and
        [int]$surface.textureGenerationCount -eq
          ([int]$surface.textureResizeRequestCount + 1) -and
        [double]$surface.textureWidthPx -le
          [double]$fixedMode.videoSurfaceDiagnostics.textureWidthPx -and
        [double]$surface.textureHeightPx -le
          [double]$fixedMode.videoSurfaceDiagnostics.textureHeightPx
      [ordered]@{
        name = $caseSummary.name
        automatedPass =
          $droppedFramesPass -and $stallPass -and $gpuPass -and
          $memoryPass -and $texturePass
        droppedFramesPass = $droppedFramesPass
        stallAndResponsivenessPass = $stallPass
        gpuP95WithinTwoPoints = $gpuPass
        memoryP95Within32MiB = $memoryPass
        textureLifecyclePass = $texturePass
        gpuCommittedP95DeltaMiB = [Math]::Round(
          [double]$adaptiveMode.gpuCommittedMiB.p95 -
          [double]$fixedMode.gpuCommittedMiB.p95,
          2)
        privateP95DeltaMiB = [Math]::Round(
          [double]$adaptiveMode.privateMiB.p95 -
          [double]$fixedMode.privateMiB.p95,
          2)
      }
    }
  )
  if ($nativeOutputCaseGates.Count -gt 0) {
    $nativeOutputPerformanceGate = [ordered]@{
      automatedPass =
        @($nativeOutputCaseGates | Where-Object automatedPass -ne $true).Count -eq 0
      scope =
        "A/B performance only; visual quality and DPI/rapid-resize gate are reported separately"
      cases = $nativeOutputCaseGates
    }
  }
}

$summaryName = switch ($Experiment) {
  "flutter-texture" { "texture-sampling-ab-summary.json" }
  "native-output" { "native-output-size-ab-summary.json" }
  default { "downscale-ab-summary.json" }
}
$samplePolicy = switch ($Experiment) {
  "flutter-texture" {
    "fixed natural 650 kbps clips; same MediaKit Texture size and fixed 12-second frame; only Flutter FilterQuality changes"
  }
  "native-output" {
    "fixed natural 650 kbps clips; fixed 12-second frame; compare fixed 1080p Texture with debounced stable output buckets"
  }
  default {
    "fixed natural 650 kbps clips; same MediaKit Texture and fixed 12-second frame"
  }
}
$summary = [ordered]@{
  schemaVersion = 1
  experiment = $Experiment
  samplePolicy = $samplePolicy
  requestedDurationSecondsPerMode = $DurationSeconds
  requestedSurfaceLogicalWidth = $SurfaceWidth
  requestedSurfaceLogicalHeight = $SurfaceHeight
  modes = $modes
  cases = @($caseSummaries)
}
if ($null -ne $nativeOutputPerformanceGate) {
  $summary.Add("nativeOutputPerformanceGate", $nativeOutputPerformanceGate)
}
$summary | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath (Join-Path $output $summaryName) `
    -Encoding utf8

Write-Host "画质 A/B 完成：$output"
