<##
.SYNOPSIS
  在正式 PlayerPage/MediaKit Texture precision QA 会话中记录匿名 DWM 可见性证据。

.DESCRIPTION
  该脚本只启动隔离 Debug QA 页面，不发送键盘或鼠标输入。它读取已经经过 DWM 合成的
  桌面中心视频区域和字幕下方区域，保存匿名 RGB 指纹及阶段时间窗，不保存截图、原始
  媒体像素、路径、标题或字幕内容。命令/资源结果来自页面 JSONL；可见性结果必须同时
  有桌面合成变化，缺少变化只记为 unknown。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Sample,
  [string]$DebugExecutable = '',
  [string]$Output = '',
  [ValidateRange(960, 7680)]
  [int]$WindowWidth = 960,
  [ValidateRange(540, 4320)]
  [int]$WindowHeight = 720,
  [ValidateRange(15, 120)]
  [int]$SampleIntervalMilliseconds = 25,
  [ValidateRange(30, 180)]
  [int]$MinimumCaptureFps = 30,
  [ValidateRange(30, 180)]
  [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'precision DWM QA 只支持 Windows。' }
if (-not (Test-Path -LiteralPath $Sample -PathType Leaf)) {
  throw 'precision DWM QA 样本不存在。'
}
if (-not $Output) {
  $Output = Join-Path $PSScriptRoot ("..\.local\qa\precision-controls-dwm-" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw '拒绝覆盖既有 precision DWM QA 证据目录。'
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

if (-not $DebugExecutable) {
  $DebugExecutable = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Debug\local_tag_player.exe'
}
$DebugExecutable = [System.IO.Path]::GetFullPath($DebugExecutable)
if (-not (Test-Path -LiteralPath $DebugExecutable -PathType Leaf)) {
  throw '缺少刚构建的 Windows Debug 可执行程序。'
}

$observerSource = @'
using System;
using System.Runtime.InteropServices;

public sealed class LocalTagPlayerPrecisionDwmFrame
{
    public long utcUs { get; set; }
    public int clientWidth { get; set; }
    public int clientHeight { get; set; }
    public int dpi { get; set; }
    public ulong centerFingerprint { get; set; }
    public ulong subtitleFingerprint { get; set; }
    public byte[] centerValues { get; set; }
    public byte[] subtitleValues { get; set; }
}

public static class LocalTagPlayerPrecisionDwmObserver
{
    // GetPixel 在部分高 DPI 桌面上成本很高；这里保留足够区分画面的匿名网格，
    // 把观测器本身限制在可用于阶段呈现节奏的采样预算内。
    private const int CenterGridWidth = 8;
    private const int CenterGridHeight = 5;
    private const int SubtitleGridWidth = 8;
    private const int SubtitleGridHeight = 2;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public uint biSize;
        public int biWidth;
        public int biHeight;
        public ushort biPlanes;
        public ushort biBitCount;
        public uint biCompression;
        public uint biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public uint biClrUsed;
        public uint biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        public uint bmiColors;
    }

    private const int SRCCOPY = 0x00CC0020;
    private const int CAPTUREBLT = 0x40000000;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateDIBSection(
        IntPtr hdc,
        ref BITMAPINFO bitmapInfo,
        uint usage,
        out IntPtr bits,
        IntPtr section,
        uint offset);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr objectHandle);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteObject(IntPtr objectHandle);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool StretchBlt(
        IntPtr hdcDest,
        int xDest,
        int yDest,
        int wDest,
        int hDest,
        IntPtr hdcSrc,
        int xSrc,
        int ySrc,
        int wSrc,
        int hSrc,
        int rop);

    public static LocalTagPlayerPrecisionDwmFrame Capture(
        string windowTitle,
        int expectedProcessId)
    {
        var window = FindWindow(null, windowTitle);
        if (window == IntPtr.Zero || !IsWindowVisible(window))
            throw new InvalidOperationException("目标窗口不可见。");
        uint processId;
        GetWindowThreadProcessId(window, out processId);
        if (expectedProcessId > 0 && processId != (uint)expectedProcessId)
            throw new InvalidOperationException("目标窗口进程不匹配。");
        RECT client;
        if (!GetClientRect(window, out client))
            throw new InvalidOperationException("无法读取目标窗口客户区。");
        var width = client.Right - client.Left;
        var height = client.Bottom - client.Top;
        if (width < 320 || height < 240)
            throw new InvalidOperationException("目标窗口客户区过小。");
        var origin = new POINT { X = 0, Y = 0 };
        if (!ClientToScreen(window, ref origin))
            throw new InvalidOperationException("无法读取目标窗口屏幕坐标。");
        var dc = GetDC(IntPtr.Zero);
        if (dc == IntPtr.Zero)
            throw new InvalidOperationException("无法读取桌面 DC。");
        try
        {
            // 一次 StretchBlt 到小型 DIB，避免逐点 GetPixel 的 GDI round-trip；DIB 只在
            // 内存中短暂存在，最终文件仍只写 RGB 指纹和尺寸。
            var fullWidth = CenterGridWidth;
            var fullHeight = CenterGridHeight + SubtitleGridHeight;
            var raw = CaptureDib(
                dc,
                origin.X + (int)Math.Round(width * 0.20),
                origin.Y + (int)Math.Round(height * 0.10),
                Math.Max(1, (int)Math.Round(width * 0.60)),
                Math.Max(1, (int)Math.Round(height * 0.80)),
                fullWidth,
                fullHeight);
            var center = ExtractRows(raw, fullWidth, 0, CenterGridHeight);
            // 字幕通常落在视频下方；只取匿名小网格，不保存任何原始像素。
            var subtitle = ExtractRows(raw, fullWidth, CenterGridHeight, SubtitleGridHeight);
            return new LocalTagPlayerPrecisionDwmFrame {
                // 与 Dart DateTime.microsecondsSinceEpoch 使用相同的 Unix epoch，才能把
                // 桌面样本和页面阶段 JSONL 放进同一时间窗。
                utcUs = (DateTime.UtcNow.Ticks - 621355968000000000L) / 10L,
                clientWidth = width,
                clientHeight = height,
                dpi = (int)GetDpiForWindow(window),
                centerFingerprint = Fingerprint(center),
                subtitleFingerprint = Fingerprint(subtitle),
                centerValues = center,
                subtitleValues = subtitle,
            };
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, dc);
        }
    }

    private static byte[] CaptureDib(
        IntPtr dc,
        int x,
        int y,
        int width,
        int height,
        int targetWidth,
        int targetHeight)
    {
        var targetDc = CreateCompatibleDC(dc);
        if (targetDc == IntPtr.Zero)
            throw new InvalidOperationException("无法创建 DIB 采样 DC。");
        var bitmapInfo = new BITMAPINFO {
            bmiHeader = new BITMAPINFOHEADER {
                biSize = (uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER)),
                biWidth = targetWidth,
                // 负高度保证内存行序与屏幕方向一致。
                biHeight = -targetHeight,
                biPlanes = 1,
                biBitCount = 32,
                biCompression = 0,
                biSizeImage = (uint)(targetWidth * targetHeight * 4),
            },
        };
        IntPtr bits;
        var bitmap = CreateDIBSection(
            targetDc,
            ref bitmapInfo,
            0,
            out bits,
            IntPtr.Zero,
            0);
        if (bitmap == IntPtr.Zero || bits == IntPtr.Zero)
        {
            DeleteDC(targetDc);
            throw new InvalidOperationException("无法创建 DIB 采样位图。");
        }
        var previousBitmap = SelectObject(targetDc, bitmap);
        try
        {
            if (!StretchBlt(
                    targetDc,
                    0,
                    0,
                    targetWidth,
                    targetHeight,
                    dc,
                    x,
                    y,
                    width,
                    height,
                    SRCCOPY | CAPTUREBLT))
            {
                throw new InvalidOperationException("桌面 DIB 复制失败。");
            }
            var raw = new byte[targetWidth * targetHeight * 4];
            Marshal.Copy(bits, raw, 0, raw.Length);
            return raw;
        }
        finally
        {
            if (previousBitmap != IntPtr.Zero) SelectObject(targetDc, previousBitmap);
            DeleteObject(bitmap);
            DeleteDC(targetDc);
        }
    }

    private static byte[] ExtractRows(
        byte[] raw,
        int width,
        int startRow,
        int rowCount)
    {
        var values = new byte[width * rowCount * 3];
        var sourceOffset = startRow * width * 4;
        var targetOffset = 0;
        for (var row = 0; row < rowCount; row++)
        {
            for (var column = 0; column < width; column++)
            {
                // 32bpp BI_RGB 内存是 BGRA；匿名输出统一为 RGB。
                var blue = raw[sourceOffset++];
                var green = raw[sourceOffset++];
                var red = raw[sourceOffset++];
                sourceOffset++; // alpha/reserved
                values[targetOffset++] = red;
                values[targetOffset++] = green;
                values[targetOffset++] = blue;
            }
        }
        return values;
    }

    private static ulong Fingerprint(byte[] values)
    {
        var hash = 1469598103934665603UL;
        foreach (var value in values)
        {
            hash ^= value;
            hash *= 1099511628211UL;
        }
        return hash;
    }
}
'@
Add-Type -TypeDefinition $observerSource -Language CSharp

$readyPath = Join-Path $Output 'ready.json'
$precisionPath = Join-Path $Output 'precision-controls.jsonl'
$shutdownPath = Join-Path $Output 'shutdown.request'
$lifecyclePath = Join-Path $Output 'qa-lifecycle.jsonl'
$dwmSamplesPath = Join-Path $Output 'precision-dwm-samples.jsonl'
$summaryPath = Join-Path $Output 'precision-controls-dwm-summary.json'
$stdoutPath = Join-Path $Output 'debug-qa.stdout.log'
$stderrPath = Join-Path $Output 'debug-qa.stderr.log'
# PlayerPage QA 的正式窗口标题由 Dart/WindowOptions 固定；环境变量只用于其它探针的
# 记录，不把一个不存在的 precision 专用标题当作 DWM 目标。
$windowTitle = 'LocalTagPlayer Real PlayerPage QA'
$testProcess = $null
$environmentNames = @(
  'LOCAL_TAG_PLAYER_PIXEL_SAMPLE',
  'LOCAL_TAG_PLAYER_PIXEL_OUTPUT',
  'LOCAL_TAG_PLAYER_PIXEL_WINDOW_TITLE',
  'LOCAL_TAG_PLAYER_PIXEL_WINDOW_WIDTH',
  'LOCAL_TAG_PLAYER_PIXEL_WINDOW_HEIGHT',
  'LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA',
  'LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA',
  'LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA',
  'LOCAL_TAG_PLAYER_PRECISION_CONTROLS_QA',
  'LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Get-JsonLines {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $values = @()
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $values += ($line | ConvertFrom-Json) } catch { }
  }
  return @($values)
}

function Get-StageEvent {
  param(
    [object[]]$Events,
    [string]$Stage
  )
  return @($Events | Where-Object { [string]$_.stage -eq $Stage } | Select-Object -First 1)
}

function Get-StageSamples {
  param(
    [object[]]$Samples,
    [long]$StartUs,
    [long]$EndUs
  )
  if ($null -eq $Samples -or @($Samples).Count -eq 0) { return @() }
  return @($Samples | Where-Object {
      [long]$_.utcUs -ge $StartUs -and
      ($EndUs -le 0 -or [long]$_.utcUs -lt $EndUs)
    })
}

function Get-NextStageUs {
  param(
    [object[]]$Events,
    [long]$StartUs
  )
  $next = @($Events | Where-Object { [long]$_.utcUs -gt $StartUs } |
      Sort-Object {[long]$_.utcUs} | Select-Object -First 1)
  if ($next.Count -eq 0) { return 0L }
  return [long]$next[0].utcUs
}

function Get-RegionDifferencePercent {
  param(
    [byte[]]$Baseline,
    [byte[]]$Current
  )
  if ($null -eq $Baseline -or $null -eq $Current -or
      $Baseline.Length -eq 0 -or $Baseline.Length -ne $Current.Length) {
    return 0.0
  }
  $sum = 0.0
  for ($index = 0; $index -lt $Baseline.Length; $index++) {
    $sum += [Math]::Abs([int]$Baseline[$index] - [int]$Current[$index])
  }
  return ($sum / ($Baseline.Length * 255.0)) * 100.0
}

function Get-RegionBaseline {
  param(
    [object[]]$Samples,
    [string]$PropertyName
  )
  if ($null -eq $Samples -or @($Samples).Count -eq 0) { return $null }
  $usable = @($Samples | Where-Object {
      $property = $_.PSObject.Properties[$PropertyName]
      if ($null -eq $property) { return $false }
      $value = $property.Value
      $null -ne $value -and $value.Length -gt 0
    } | Select-Object -Last 8)
  if ($usable.Count -eq 0) { return $null }
  $firstProperty = $usable[0].PSObject.Properties[$PropertyName]
  if ($null -eq $firstProperty -or $null -eq $firstProperty.Value) { return $null }
  $length = $firstProperty.Value.Length
  $average = New-Object byte[] $length
  for ($index = 0; $index -lt $length; $index++) {
    $total = 0
    foreach ($sample in $usable) {
      $property = $sample.PSObject.Properties[$PropertyName]
      if ($null -ne $property -and $null -ne $property.Value) {
        $total += [int]$property.Value[$index]
      }
    }
    $average[$index] = [byte][Math]::Round($total / $usable.Count)
  }
  return $average
}

function Get-DwmMetric {
  param(
    [object[]]$BaselineSamples,
    [object[]]$PresentedSamples,
    [string]$DifferencePropertyName
  )
  if ($null -eq $BaselineSamples -or $null -eq $PresentedSamples) {
    return [ordered]@{
      status = 'unknown'
      baselineSampleCount = 0
      presentedSampleCount = 0
      presentedChangeCount = 0
      maxDifferencePercent = 0.0
      thresholdPercent = 1.5
      evidenceKind = 'insufficient-dwm-change'
    }
  }
  $differences = @()
  foreach ($sample in $PresentedSamples) {
    $property = $sample.PSObject.Properties[$DifferencePropertyName]
    $current = if ($null -eq $property) { $null } else { $property.Value }
    if ($null -ne $current) { $differences += [double]$current }
  }
  $consecutive = 0
  $maxConsecutive = 0
  foreach ($difference in $differences) {
    if ($difference -ge 1.5) {
      $consecutive++
      $maxConsecutive = [Math]::Max($maxConsecutive, $consecutive)
    } else {
      $consecutive = 0
    }
  }
  $maxDifference = if ($differences.Count -eq 0) { 0.0 } else {
    [double](($differences | Measure-Object -Maximum).Maximum)
  }
  $status = if ($BaselineSamples.Count -eq 0 -or $PresentedSamples.Count -eq 0) {
    'unknown'
  } elseif ($maxConsecutive -ge 2) {
    'pass'
  } else {
    'unknown'
  }
  return [ordered]@{
    status = $status
    baselineSampleCount = $BaselineSamples.Count
    presentedSampleCount = $PresentedSamples.Count
    presentedChangeCount = @($differences | Where-Object { $_ -ge 1.5 }).Count
    maxDifferencePercent = [Math]::Round($maxDifference, 3)
    thresholdPercent = 1.5
    evidenceKind = if ($status -eq 'pass') { 'desktop-composited-pixel-change' } else { 'insufficient-dwm-change' }
  }
}

function Get-StageMetric {
  param(
    [object[]]$Events,
    [object[]]$Samples,
    [string]$CommandStage,
    [string]$BeforeStage,
    [string]$AfterStage,
    [string]$DifferencePropertyName,
    [bool]$UseNextEventForAfter = $true,
    [string]$BaselineEndStage = '',
    [string]$PresentedStartStage = ''
  )
  $command = Get-StageEvent -Events $Events -Stage $CommandStage
  if ($command.Count -eq 0) {
    return [ordered]@{ status = 'unknown'; commandStatus = $null; reason = 'missing-command-stage' }
  }
  $commandSuccess = $command[0].PSObject.Properties['success']
  $commandStatus = if ($null -eq $commandSuccess) { $null } else { [bool]$commandSuccess.Value }
  if ($commandStatus -eq $false) {
    return [ordered]@{ status = 'fail'; commandStatus = $false; reason = 'command-stage-failed' }
  }
  $before = Get-StageEvent -Events $Events -Stage $BeforeStage
  if ($before.Count -eq 0) {
    return [ordered]@{ status = 'unknown'; commandStatus = $commandStatus; reason = 'missing-baseline-stage' }
  }
  $startUs = [long]$before[0].utcUs
  $commandUs = [long]$command[0].utcUs
  $baselineEndUs = $commandUs
  if (-not [string]::IsNullOrWhiteSpace($BaselineEndStage)) {
    $baselineEnd = Get-StageEvent -Events $Events -Stage $BaselineEndStage
    if ($baselineEnd.Count -gt 0) { $baselineEndUs = [long]$baselineEnd[0].utcUs }
  }
  $presentedStartUs = $commandUs
  if (-not [string]::IsNullOrWhiteSpace($PresentedStartStage)) {
    $presentedStart = Get-StageEvent -Events $Events -Stage $PresentedStartStage
    if ($presentedStart.Count -gt 0) { $presentedStartUs = [long]$presentedStart[0].utcUs }
  }
  $nextUs = if ($UseNextEventForAfter) {
    Get-NextStageUs -Events $Events -StartUs $commandUs
  } else { 0L }
  $baselineSamples = Get-StageSamples -Samples $Samples -StartUs $startUs -EndUs $baselineEndUs
  $presentedSamples = Get-StageSamples -Samples $Samples -StartUs $presentedStartUs -EndUs $nextUs
  $metric = Get-DwmMetric -BaselineSamples $baselineSamples -PresentedSamples $presentedSamples -DifferencePropertyName $DifferencePropertyName
  $metric.commandStatus = $commandStatus
  $metric.commandStage = $CommandStage
  $metric.baselineStage = $BeforeStage
  $metric.baselineEndStage = if ([string]::IsNullOrWhiteSpace($BaselineEndStage)) { $CommandStage } else { $BaselineEndStage }
  $metric.presentedStartStage = if ([string]::IsNullOrWhiteSpace($PresentedStartStage)) { $CommandStage } else { $PresentedStartStage }
  $metric.presentedWindowEndUs = $nextUs
  return $metric
}

try {
  $env:LOCAL_TAG_PLAYER_PIXEL_SAMPLE = $Sample
  $env:LOCAL_TAG_PLAYER_PIXEL_OUTPUT = $Output
  $env:LOCAL_TAG_PLAYER_PIXEL_WINDOW_TITLE = $windowTitle
  $env:LOCAL_TAG_PLAYER_PIXEL_WINDOW_WIDTH = "$WindowWidth"
  $env:LOCAL_TAG_PLAYER_PIXEL_WINDOW_HEIGHT = "$WindowHeight"
  $env:LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA = '1'
  $env:LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA = '1'
  $env:LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA = '1'
  $env:LOCAL_TAG_PLAYER_PRECISION_CONTROLS_QA = '1'
  Remove-Item Env:LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA -ErrorAction SilentlyContinue

  $testProcess = Start-Process -FilePath $DebugExecutable -PassThru `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while (-not (Test-Path -LiteralPath $readyPath) -and
         -not $testProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 100
  }
  if ($testProcess.HasExited) { throw 'Debug precision QA 在 ready 握手前退出。' }
  if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Debug precision QA 未在时限内 ready。' }
  $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
  if ($ready.surface -ne 'product-player-page' -or
      $ready.backend -ne 'media-kit-flutter-texture' -or
      -not [bool]$ready.precisionControlsQa) {
    throw 'ready 握手未确认正式 PlayerPage precision QA。'
  }

  $sampleObjects = @()
  # 采样循环只保留匿名行，结束后一次性写盘，避免同步 I/O 反过来扰动 DWM 采样率。
  $dwmSampleRows = New-Object 'System.Collections.Generic.List[object]'
  $previousFrame = $null
  $lastSampleUs = 0L
  $completionUs = 0L
  while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    $nowUs = ([DateTime]::UtcNow.Ticks - 621355968000000000L) / 10L
    if ($lastSampleUs -eq 0L -or $nowUs - $lastSampleUs -ge ($SampleIntervalMilliseconds * 1000L)) {
      try {
        $frame = [LocalTagPlayerPrecisionDwmObserver]::Capture($windowTitle, $testProcess.Id)
        $sampleObjects += $frame
        $centerDifference = if ($null -eq $previousFrame) { $null } else {
          Get-RegionDifferencePercent -Baseline $previousFrame.centerValues -Current $frame.centerValues
        }
        $subtitleDifference = if ($null -eq $previousFrame) { $null } else {
          Get-RegionDifferencePercent -Baseline $previousFrame.subtitleValues -Current $frame.subtitleValues
        }
        $dwmSampleRows.Add([ordered]@{
            utcUs = [long]$frame.utcUs
            clientWidth = [int]$frame.clientWidth
            clientHeight = [int]$frame.clientHeight
            dpi = [int]$frame.dpi
            centerFingerprint = [string]$frame.centerFingerprint
            subtitleFingerprint = [string]$frame.subtitleFingerprint
            centerDifferenceFromPreviousPercent = if ($null -eq $centerDifference) { $null } else { [Math]::Round([double]$centerDifference, 3) }
            subtitleDifferenceFromPreviousPercent = if ($null -eq $subtitleDifference) { $null } else { [Math]::Round([double]$subtitleDifference, 3) }
          })
        $lastSampleUs = [long]$frame.utcUs
        $previousFrame = $frame
      } catch {
        # 窗口短暂重建/最小化只留下采样空洞；后续门禁会把证据判为 unknown，
        # 不把失败采样补成 DWM 帧。
      }
    }
    $events = @(Get-JsonLines $precisionPath)
    $complete = @($events | Where-Object { $_.stage -eq 'external_subtitle_complete' -and $_.success -eq $true })
    if ($complete.Count -gt 0 -and $completionUs -eq 0L) {
      $completionUs = [long]$complete[0].utcUs
    }
    if ($completionUs -gt 0L -and $nowUs - $completionUs -ge 900000L) { break }
    Start-Sleep -Milliseconds 10
  }
  if ($completionUs -eq 0L) { throw 'precision controls QA 未完成。' }

  $events = @(Get-JsonLines $precisionPath | Sort-Object {[long]$_.utcUs})
  $sampleObjects = @($sampleObjects | Sort-Object {[long]$_.utcUs})
  $dwmSampleJsonLines = @($dwmSampleRows | ForEach-Object { $_ | ConvertTo-Json -Compress })
  $dwmSampleJson = if ($dwmSampleJsonLines.Count -eq 0) {
    ''
  } else {
    ($dwmSampleJsonLines -join [Environment]::NewLine) + [Environment]::NewLine
  }
  [System.IO.File]::WriteAllText(
    $dwmSamplesPath,
    $dwmSampleJson,
    [System.Text.UTF8Encoding]::new($false)
  )
  $sampleRows = @(Get-JsonLines $dwmSamplesPath | Sort-Object {[long]$_.utcUs})
  [System.IO.File]::WriteAllText(
    $shutdownPath,
    'dispose-before-exit',
    [System.Text.UTF8Encoding]::new($false)
  )
  $releaseDeadline = [DateTime]::UtcNow.AddSeconds(20)
  while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $releaseDeadline) {
    Start-Sleep -Milliseconds 100
  }
  $lifecycle = @(Get-JsonLines $lifecyclePath | ForEach-Object { [string]$_.event })

  $frameMetric = Get-StageMetric -Events $events -Samples $sampleRows `
    -CommandStage 'frame_step_complete' -BeforeStage 'frame_step_before' `
    -AfterStage 'frame_step_complete' `
    -DifferencePropertyName 'centerDifferenceFromPreviousPercent'
  $playbackRateMetric = Get-StageMetric -Events $events -Samples $sampleRows `
    -CommandStage 'playback_rate_complete' -BeforeStage 'playback_rate_before' `
    -AfterStage 'playback_rate_complete' `
    -DifferencePropertyName 'centerDifferenceFromPreviousPercent'
  $loopMetric = Get-StageMetric -Events $events -Samples $sampleRows `
    -CommandStage 'ab_loop_cycle_complete' -BeforeStage 'ab_loop_b' `
    -AfterStage 'ab_loop_cycle_complete' `
    -DifferencePropertyName 'centerDifferenceFromPreviousPercent' `
    -BaselineEndStage 'ab_loop_playback_started' `
    -PresentedStartStage 'ab_loop_playback_started'
  $subtitleMetric = Get-StageMetric -Events $events -Samples $sampleRows `
    -CommandStage 'external_subtitle_complete' -BeforeStage 'external_subtitle_before' `
    -AfterStage 'external_subtitle_complete' `
    -DifferencePropertyName 'subtitleDifferenceFromPreviousPercent' `
    -BaselineEndStage 'external_subtitle_load_started' `
    -PresentedStartStage 'external_subtitle_load_started'
  $stageMetrics = [ordered]@{
    frameStep = $frameMetric
    playbackRate = $playbackRateMetric
    abLoop = $loopMetric
    externalSubtitle = $subtitleMetric
  }
  $captureElapsedSeconds = if ($sampleObjects.Count -ge 2) {
    ([long]$sampleObjects[-1].utcUs - [long]$sampleObjects[0].utcUs) / 1000000.0
  } else { 0.0 }
  $captureFps = if ($captureElapsedSeconds -gt 0) {
    [Math]::Round($sampleObjects.Count / $captureElapsedSeconds, 1)
  } else { 0.0 }
  $captureRateStatus = if ($captureFps -ge $MinimumCaptureFps) { 'pass' } else { 'unknown' }
  $resourceReleaseStatus = if ($lifecycle -contains 'player_resources_released') { 'pass' } else { 'fail' }
  $statuses = @($stageMetrics.Values | ForEach-Object { [string]$_.status }) +
    @($captureRateStatus, $resourceReleaseStatus)
  $overall = if ($statuses -contains 'fail') { 'fail' }
    elseif ($statuses -contains 'unknown') { 'unknown' }
    else { 'pass' }
  $summary = [ordered]@{
    schemaVersion = 1
    evidence = 'real-player-page-dwm-precision-controls'
    overall = $overall
    surface = 'product-player-page'
    backend = 'media-kit-flutter-texture'
    commandResourceEvidence = 'precision-controls.jsonl'
    dwmEvidence = 'precision-dwm-samples.jsonl'
    stageMetrics = $stageMetrics
    capture = [ordered]@{
      sampleCount = $sampleObjects.Count
      effectiveFps = $captureFps
      minimumFps = $MinimumCaptureFps
      captureRateStatus = $captureRateStatus
      firstDwmEvidenceKind = 'desktop-composited-pixel-change'
      thresholdPercent = 1.5
    }
    resourceReleaseConfirmed = $lifecycle -contains 'player_resources_released'
    resourceReleaseStatus = $resourceReleaseStatus
    lifecycle = $lifecycle
    pathOrMediaContentRetained = $false
  }
  [System.IO.File]::WriteAllText(
    $summaryPath,
    ($summary | ConvertTo-Json -Depth 20),
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Output ('PLAYER_PRECISION_CONTROLS_DWM_QA ' + ($summary | ConvertTo-Json -Compress -Depth 20))
} finally {
  if ($null -ne $testProcess -and -not $testProcess.HasExited) {
    [System.IO.File]::WriteAllText(
      $shutdownPath,
      'dispose-before-exit',
      [System.Text.UTF8Encoding]::new($false)
    )
    try { $testProcess.WaitForExit(20000) } catch { }
    if (-not $testProcess.HasExited) { $testProcess.Kill() }
  }
  foreach ($name in $environmentNames) {
    $value = $previousEnvironment[$name]
    if ($null -eq $value) {
      Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    } else {
      Set-Item "Env:$name" $value
    }
  }
}
