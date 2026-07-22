param(
  [ValidateRange(60, 900)]
  [int]$HdrSeconds = 300,
  [ValidateRange(60, 900)]
  [int]$SdrDarkSeconds = 180,
  [string]$OutputDirectory = ".local/qa/fixed-quality-baseline"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$output = [System.IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
$samples = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace ".local/qa/fixed-samples")
)
New-Item -ItemType Directory -Force -Path $output | Out-Null

& (Join-Path $PSScriptRoot "generate_player_quality_samples.ps1") `
  -OutputDirectory $samples `
  -HdrDurationSeconds ($HdrSeconds + 60) `
  -SdrDurationSeconds ($SdrDarkSeconds + 60)
if ($LASTEXITCODE -ne 0) {
  throw "Fixed sample generation failed: $LASTEXITCODE"
}

<#
  对单个模式启动真实 Flutter Windows 长播；后台只读取进程计数器、NVIDIA-SMI
  和窗口像素，不创建 UIA 客户端，也不访问用户媒体库。
#>
function Invoke-QualityBaselineMode {
  param(
    [Parameter(Mandatory = $true)][string]$Mode,
    [Parameter(Mandatory = $true)][string]$SamplePath,
    [Parameter(Mandatory = $true)][int]$DurationSeconds
  )

  $modeOutput = Join-Path $output $Mode
  New-Item -ItemType Directory -Force -Path $modeOutput | Out-Null
  Get-ChildItem -LiteralPath $modeOutput -Filter "*.ready" -ErrorAction SilentlyContinue |
    Remove-Item -Force
  $donePath = Join-Path $modeOutput "baseline.done"
  Remove-Item -LiteralPath $donePath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $modeOutput "process.pid") `
    -Force -ErrorAction SilentlyContinue

  $monitorJob = Start-Job -ArgumentList $modeOutput, $Mode -ScriptBlock {
    param($Output, $Mode)
    $metrics = Join-Path $Output "system-metrics.csv"
    "timestamp,mode,pid,cpu_seconds,threads,working_set_mb,private_mb,responding,gpu_util_percent,gpu_committed_mb,nvidia_power_w,nvidia_power_limit_w,nvidia_gpu_util_percent,nvidia_memory_util_percent,nvidia_graphics_clock_mhz" |
      Set-Content -LiteralPath $metrics
    while (-not (Test-Path -LiteralPath (Join-Path $Output "baseline.done"))) {
      $sampleStarted = Get-Date
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
          $gpuPrefix = "\GPU Process Memory(pid_" + $process.Id + "_*)\"
          $gpu = Get-Counter -Counter @(
            ($gpuPrefix + "Total Committed"),
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

        $power = ""
        $powerLimit = ""
        $nvidiaUtil = ""
        $nvidiaMemory = ""
        $graphicsClock = ""
        try {
          $nvidia = (& nvidia-smi.exe `
            --query-gpu=power.draw,power.limit,utilization.gpu,utilization.memory,clocks.gr `
            --format=csv,noheader,nounits 2>$null | Select-Object -First 1) -split ","
          if ($nvidia.Count -ge 5) {
            $power = $nvidia[0].Trim()
            $powerLimit = $nvidia[1].Trim()
            $nvidiaUtil = $nvidia[2].Trim()
            $nvidiaMemory = $nvidia[3].Trim()
            $graphicsClock = $nvidia[4].Trim()
          }
        } catch {}
        $line = "{0},{1},{2},{3:F3},{4},{5:F1},{6:F1},{7},{8:F1},{9:F1},{10},{11},{12},{13},{14}" -f `
          (Get-Date -Format o), $Mode, $process.Id,
          $process.TotalProcessorTime.TotalSeconds, $process.Threads.Count,
          ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB),
          $process.Responding, $gpuUtil, ($gpuCommitted / 1MB),
          $power, $powerLimit, $nvidiaUtil, $nvidiaMemory, $graphicsClock
        Add-Content -LiteralPath $metrics -Value $line
      }
      $remainingMs = 1000 - ((Get-Date) - $sampleStarted).TotalMilliseconds
      if ($remainingMs -gt 0) { Start-Sleep -Milliseconds $remainingMs }
    }
  }

  $captureJob = Start-Job -ArgumentList $modeOutput -ScriptBlock {
    param($Output)
    Add-Type -AssemblyName System.Drawing
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpQualityWindowCapture {
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
    [LtpQualityWindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
    $captured = @{}
    while (-not (Test-Path -LiteralPath (Join-Path $Output "baseline.done"))) {
      foreach ($marker in Get-ChildItem -LiteralPath $Output -Filter "*.ready" -ErrorAction SilentlyContinue) {
        if ($captured.ContainsKey($marker.FullName)) { continue }
        $pidPath = Join-Path $Output "process.pid"
        $process = $null
        if (Test-Path -LiteralPath $pidPath) {
          $testPid = [int]((Get-Content -LiteralPath $pidPath -Raw).Trim())
          $process = Get-Process -Id $testPid -ErrorAction SilentlyContinue
        }
        if ($null -ne $process -and $process.MainWindowHandle -eq 0) {
          $process = $null
        }
        if ($null -eq $process) { continue }
        $rect = New-Object LtpQualityWindowCapture+RECT
        if (-not ([LtpQualityWindowCapture]::GetWindowRect(
            $process.MainWindowHandle, [ref]$rect))) { continue }
        $bitmap = [System.Drawing.Bitmap]::new(
          $rect.Right - $rect.Left,
          $rect.Bottom - $rect.Top)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $deviceContext = $graphics.GetHdc()
        $capturedWindow = [LtpQualityWindowCapture]::PrintWindow(
          $process.MainWindowHandle, $deviceContext, 2)
        $graphics.ReleaseHdc($deviceContext)
        $graphics.Dispose()
        if (-not $capturedWindow) {
          $bitmap.Dispose()
          throw "PrintWindow failed for isolated quality baseline."
        }
        $bitmap.Save((Join-Path $Output "$($marker.BaseName).png"))
        $bitmap.Dispose()
        $captured[$marker.FullName] = $true
      }
      Start-Sleep -Milliseconds 150
    }
  }

  $env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH = $SamplePath
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT = $modeOutput
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE = $Mode
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS = $DurationSeconds.ToString()
  try {
    Push-Location $workspace
    & flutter test integration_test/player_fixed_quality_baseline_test.dart -d windows `
      *>&1 | Tee-Object -FilePath (Join-Path $modeOutput "baseline.log")
    $testExitCode = $LASTEXITCODE
  } finally {
    Pop-Location
    New-Item -ItemType File -Force -Path $donePath | Out-Null
    Wait-Job $monitorJob, $captureJob -Timeout 20 | Out-Null
    Receive-Job $monitorJob, $captureJob
    Remove-Job $monitorJob, $captureJob -Force
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    throw "Fixed $Mode baseline failed: $testExitCode"
  }
}

Invoke-QualityBaselineMode `
  -Mode "hdr" `
  -SamplePath (Join-Path $samples "fixed-hdr10-pq-1080p.mp4") `
  -DurationSeconds $HdrSeconds
Invoke-QualityBaselineMode `
  -Mode "sdr-dark" `
  -SamplePath (Join-Path $samples "fixed-sdr-dark-1080p.mp4") `
  -DurationSeconds $SdrDarkSeconds

<# 生成两种固定样本的可比较摘要；NVIDIA-SMI 是整卡功耗，不冒充进程功耗。 #>
function Get-MetricSummary {
  param([object[]]$Rows, [string]$Property)
  $values = @($Rows | ForEach-Object {
    $parsed = 0.0
    if ([double]::TryParse($_.$Property, [ref]$parsed)) { $parsed }
  })
  if ($values.Count -eq 0) { return $null }
  $sorted = @($values | Sort-Object)
  $median = $sorted[[Math]::Floor(($sorted.Count - 1) * 0.5)]
  $p95 = $sorted[[Math]::Floor(($sorted.Count - 1) * 0.95)]
  [ordered]@{
    median = [Math]::Round($median, 2)
    p95 = [Math]::Round($p95, 2)
    max = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 2)
  }
}

$summary = [ordered]@{
  schemaVersion = 1
  powerScope = "whole NVIDIA adapter, not per-process"
  hdr = [ordered]@{}
  sdrDark = [ordered]@{}
}
foreach ($entry in @(
    @{ Name = "hdr"; Key = "hdr" },
    @{ Name = "sdr-dark"; Key = "sdrDark" }
  )) {
  $rows = @(Import-Csv -LiteralPath (Join-Path $output "$($entry.Name)/system-metrics.csv"))
  $modeSummary = $summary[$entry.Key]
  $modeSummary.samples = $rows.Count
  $modeSummary.gpuUtilPercent = Get-MetricSummary $rows "gpu_util_percent"
  $modeSummary.gpuCommittedMiB = Get-MetricSummary $rows "gpu_committed_mb"
  $modeSummary.nvidiaPowerW = Get-MetricSummary $rows "nvidia_power_w"
  $modeSummary.nvidiaGpuUtilPercent = Get-MetricSummary $rows "nvidia_gpu_util_percent"
  $modeSummary.workingSetMiB = Get-MetricSummary $rows "working_set_mb"
  $modeSummary.privateMiB = Get-MetricSummary $rows "private_mb"
  $modeSummary.unresponsiveSamples = @($rows | Where-Object responding -ne "True").Count
}
$summary | ConvertTo-Json -Depth 8 |
  Set-Content -LiteralPath (Join-Path $output "baseline-summary.json") -Encoding utf8
Write-Host "Fixed HDR and SDR dark baselines are ready: $output"
