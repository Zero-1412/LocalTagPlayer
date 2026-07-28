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
  Get-ChildItem -LiteralPath $modeOutput -Filter "*.ready" `
    -ErrorAction SilentlyContinue | Remove-Item -Force
  Get-ChildItem -LiteralPath $modeOutput -Filter "*-window.png" `
    -ErrorAction SilentlyContinue | Remove-Item -Force
  $donePath = Join-Path $modeOutput "baseline.done"
  Remove-Item -LiteralPath $donePath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $modeOutput "process.pid") `
    -Force -ErrorAction SilentlyContinue

  <#
   * mpv 的 `screenshot video` 位于输出缩放之前：关闭组为 1080P，VSR 组为
   * 4K，不能直接代表同一窗口里的最终观感。该任务在测试写出固定 12 秒
   * `.ready` 标记后，按精确 PID 捕获完整窗口，让两组拥有相同显示像素尺寸。
  #>
  $captureJob = Start-Job -ArgumentList $modeOutput, $donePath -ScriptBlock {
    param($Output, $DonePath)
    Add-Type -AssemblyName System.Drawing
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpNvidiaVsrWindowCapture {
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
    [LtpNvidiaVsrWindowCapture]::SetProcessDpiAwarenessContext(
      [IntPtr](-4)) | Out-Null
    $captured = @{}
    while (-not (Test-Path -LiteralPath $DonePath)) {
      foreach ($marker in Get-ChildItem -LiteralPath $Output `
          -Filter "*.ready" -ErrorAction SilentlyContinue) {
        if ($captured.ContainsKey($marker.FullName)) { continue }
        $pidPath = Join-Path $Output "process.pid"
        if (-not (Test-Path -LiteralPath $pidPath)) { continue }
        $testPid = [int]((Get-Content -LiteralPath $pidPath -Raw).Trim())
        $process = Get-Process -Id $testPid -ErrorAction SilentlyContinue
        if ($null -eq $process -or $process.MainWindowHandle -eq 0) {
          continue
        }
        $rect = New-Object LtpNvidiaVsrWindowCapture+RECT
        if (-not ([LtpNvidiaVsrWindowCapture]::GetWindowRect(
            $process.MainWindowHandle, [ref]$rect))) {
          continue
        }
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -le 0 -or $height -le 0) { continue }
        $bitmap = [System.Drawing.Bitmap]::new($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $deviceContext = $graphics.GetHdc()
        $capturedWindow = [LtpNvidiaVsrWindowCapture]::PrintWindow(
          $process.MainWindowHandle, $deviceContext, 2)
        $graphics.ReleaseHdc($deviceContext)
        $graphics.Dispose()
        if (-not $capturedWindow) {
          $bitmap.Dispose()
          throw "PrintWindow failed for isolated NVIDIA VSR QA."
        }
        $windowPath = Join-Path $Output "$($marker.BaseName)-window.png"
        $bitmap.Save($windowPath)
        $bitmap.Dispose()
        $captured[$marker.FullName] = $true
      }
      Start-Sleep -Milliseconds 50
    }
  }

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
    New-Item -ItemType File -Force -Path $donePath | Out-Null
    Wait-Job $captureJob -Timeout 20 | Out-Null
    Receive-Job $captureJob
    Remove-Job $captureJob -Force
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

<#
 * 读取固定 12 秒最终窗口证据；只比较同一类别的 off/on 尺寸，不把不同输出
 * 分辨率的 mpv `screenshot video` 当作视觉 A/B。
#>
function Get-WindowCaptureEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $capturePath = Join-Path `
    (Join-Path (Join-Path $output $Case.name) $Mode) `
    "$Mode-complete-window.png"
  if (-not (Test-Path -LiteralPath $capturePath)) {
    throw "缺少固定帧窗口截图：$($Case.name) / $Mode"
  }
  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Image]::FromFile($capturePath)
  try {
    return [ordered]@{
      path = $capturePath
      width = $image.Width
      height = $image.Height
      fixedFrameSecond = 12
      captureMode = "process-bound PrintWindow(PW_RENDERFULLCONTENT)"
    }
  } finally {
    $image.Dispose()
  }
}

$caseSummaries = foreach ($case in $cases) {
  $off = Get-ModeSummary -Case $case -Mode "nvidia-off"
  $on = Get-ModeSummary -Case $case -Mode "nvidia-on"
  $offWindow = Get-WindowCaptureEvidence -Case $case -Mode "nvidia-off"
  $onWindow = Get-WindowCaptureEvidence -Case $case -Mode "nvidia-on"
  [ordered]@{
    name = $case.name
    category = $case.category
    samplePath = $case.samplePath
    off = $off
    on = $on
    visualEvidence = [ordered]@{
      off = $offWindow
      on = $onWindow
      sameWindowDimensions =
        $offWindow.width -eq $onWindow.width -and
        $offWindow.height -eq $onWindow.height
    }
    performanceGatePassed =
      $on.maxDecoderDroppedFrames -le $off.maxDecoderDroppedFrames -and
      $on.maxOutputDroppedFrames -le $off.maxOutputDroppedFrames -and
      $on.maxTotalDroppedFrames -le $off.maxTotalDroppedFrames -and
      $on.videoStallSamples -eq 0 -and
      $on.audioStallSamples -eq 0
    visualCaptureGatePassed =
      $offWindow.width -eq $onWindow.width -and
      $offWindow.height -eq $onWindow.height
  }
}

$summary = [ordered]@{
  schemaVersion = 2
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  decoderPolicy = "d3d11va non-copy for both A/B modes"
  filterPolicy = "NVIDIA d3d11vpp and CPU lavfi are mutually exclusive"
  visualPolicy =
    "fixed 12-second frame captured from the same-size final Windows surface"
  cases = @($caseSummaries)
  allPerformanceGatesPassed =
    @($caseSummaries | Where-Object { -not $_.performanceGatePassed }).Count -eq 0
  allVisualCaptureGatesPassed =
    @($caseSummaries |
      Where-Object { -not $_.visualCaptureGatePassed }).Count -eq 0
}
$summaryPath = Join-Path $output "summary.json"
$summary | ConvertTo-Json -Depth 12 |
  Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "NVIDIA A/B summary: $summaryPath"
if (-not $summary.allPerformanceGatesPassed) {
  throw "至少一个自然片源的 NVIDIA 掉帧或停滞门禁未通过。"
}
if (-not $summary.allVisualCaptureGatesPassed) {
  throw "至少一个自然片源的 NVIDIA 固定帧窗口截图尺寸不一致。"
}
