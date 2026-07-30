param(
  [ValidateRange(10, 120)]
  [int]$DurationSeconds = 20,
  [string]$SampleDirectory = ".local/qa/natural-compression-ab/samples",
  [string]$OutputDirectory = ".local/qa/downscale-quality-ab",
  [string]$OnlyCase = "",
  [string]$OnlyMode = "",
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
 * A 是打包 mpv 0.36 的真实当前行为；B 评估高质量卷积缩小；C 关闭 correct-downscaling，
 * 用于隔离滤镜半径校正的画质与性能影响。
#>
$modes = @(
  "downscale-current",
  "downscale-lanczos",
  "downscale-lanczos-uncorrected"
)

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
function Invoke-DownscaleMode {
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
          throw "固定缩小 A/B 的 PrintWindow 失败。"
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
  }
  if ($testExitCode -ne 0) {
    Get-Content -LiteralPath $logPath -Tail 80
    throw "缩小 A/B 失败：$($Case.name) / $Mode"
  }
}

if (-not $SkipPlayback) {
  foreach ($case in $cases |
      Where-Object { [string]::IsNullOrWhiteSpace($OnlyCase) -or
        $_.name -eq $OnlyCase }) {
    foreach ($mode in $modes |
        Where-Object { [string]::IsNullOrWhiteSpace($OnlyMode) -or
          $_ -eq $OnlyMode }) {
      Write-Host "运行缩小 A/B：$($case.name) / $mode"
      Invoke-DownscaleMode -Case $case -Mode $mode
      # Windows integration runner 偶发延迟释放 NativeReference；组间留出短暂收敛窗口。
      Start-Sleep -Seconds 2
    }
  }
}

$caseSummaries = foreach ($case in $cases) {
  $modeSummaries = @(foreach ($mode in $modes) {
    $modeOutput = Join-Path (Join-Path $output $case.name) $mode
    $report = Get-Content -LiteralPath `
      (Join-Path $modeOutput "$mode-player-baseline.json") -Raw -Encoding utf8 |
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
    $fixedFrameWindow = Join-Path $modeOutput "$mode-complete-window.png"
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
      fixedFrameWindow = $fixedFrameWindow
      fixedFrameSha256 =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $fixedFrameWindow).Hash
    }
  })
  $uniqueFrameHashes =
    @($modeSummaries.fixedFrameSha256 | Select-Object -Unique)
  [ordered]@{
    name = $case.name
    category = $case.category
    modes = @($modeSummaries)
    fixedWindowFramesByteIdentical = $uniqueFrameHashes.Count -eq 1
  }
}

[ordered]@{
  schemaVersion = 1
  samplePolicy = "fixed natural 650 kbps clips; same MediaKit Texture and fixed 12-second frame"
  requestedDurationSecondsPerMode = $DurationSeconds
  modes = $modes
  cases = @($caseSummaries)
} | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath (Join-Path $output "downscale-ab-summary.json") `
    -Encoding utf8

Write-Host "缩小画质 A/B 完成：$output"
