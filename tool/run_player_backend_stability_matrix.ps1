param(
  [string]$Flutter = 'flutter',
  [string[]]$SamplePaths = @(),
  [ValidateRange(10, 86400)]
  [int]$LongPlaySeconds = 1800,
  [ValidateRange(6, 1000)]
  [int]$RapidSwitchCount = 18,
  [ValidateRange(0, 10000)]
  [int]$MaxDroppedFrames = 5,
  [ValidateSet('auto', 'simulated', 'passed', 'failed')]
  [string]$PhysicalCrossDpiStatus = 'auto',
  # 默认保留历史的两条 Texture 对照；传入 mediaKit,hwnd 时才运行 child HWND QA。
  [ValidateSet('mediaKit', 'mpv', 'hwnd')]
  [string[]]$Backends = @('mediaKit', 'mpv'),
  # 用 Flutter Profile 构建执行集成测试；默认 Debug 保留本地快速诊断路径。
  [switch]$Profile,
  [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

# 把页面 trace 中“开始观察新帧后等待了多久”单独汇总。它不是按键/拖动到屏幕像素的
# 端到端延迟，因此字段名明确标为 observation；超时必须进入结果，不能只留在长日志。
function Get-SeekTraceSummary {
  param([string]$LogPath)
  if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    return [pscustomobject]@{
      observedFrames = 0
      observationP50Ms = $null
      observationP95Ms = $null
      framePresentationTimeouts = 0
      evidence = @()
    }
  }
  $waits = @()
  $timeouts = 0
  $evidence = @()
  $frameStagesPattern = 'native_rendered_frame|presented_frame_fallback|new_video_frame'
  $frameTimeoutStagesPattern = 'native_rendered_frame_timeout|new_video_frame_timeout'
  foreach ($line in Get-Content -LiteralPath $LogPath) {
    if ($line -notmatch 'PLAYER_SEEK_TRACE') { continue }
    # 音频门禁历史阶段仍可能写出 new_video_frame；当前统一首帧证据阶段是
    # native_rendered_frame / presented_frame_fallback。三者都必须纳入观察统计，
    # 否则有效 Texture 首帧会在矩阵报告中被误记成 0 个样本。
    if ($line -match "stage=(?:$frameTimeoutStagesPattern)") { $timeouts++ }
    if ($line -match "stage=(?:$frameStagesPattern)(?:\s|$)" -and $line -match 'wait_ms=(\d+)') {
      $waits += [int]$Matches[1]
    }
    if ($line -match 'frame_evidence=([^\s]+)') { $evidence += $Matches[1] }
  }
  $sorted = @($waits | Sort-Object)
  $p50 = if ($sorted.Count -eq 0) { $null } else { $sorted[[int][Math]::Floor(($sorted.Count - 1) * 0.5)] }
  $p95 = if ($sorted.Count -eq 0) { $null } else { $sorted[[int][Math]::Ceiling(($sorted.Count - 1) * 0.95)] }
  return [pscustomobject]@{
    observedFrames = $sorted.Count
    observationP50Ms = $p50
    observationP95Ms = $p95
    framePresentationTimeouts = $timeouts
    evidence = @($evidence | Sort-Object -Unique)
  }
}

function Get-SeekLatencyTrace {
  param([string]$LogPath)
  if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return $null }
  $latest = $null
  $prefix = 'PLAYER_SEEK_LATENCY '
  foreach ($line in Get-Content -LiteralPath $LogPath) {
    $index = $line.IndexOf($prefix, [StringComparison]::Ordinal)
    if ($index -lt 0) { continue }
    $json = $line.Substring($index + $prefix.Length).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) { continue }
    try {
      $candidate = $json | ConvertFrom-Json
      if ($null -ne $candidate) { $latest = $candidate }
    } catch {
      # 日志可能被 Flutter runner 截断；只跳过该行，不能伪造空 trace。
    }
  }
  if ($null -eq $latest -or
      $latest.PSObject.Properties.Name -notcontains 'reverseKeyframeTrace') {
    return $null
  }
  return $latest.reverseKeyframeTrace
}

function Get-ReverseDirectionExperiment {
  param([string]$LogPath)
  if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return $null }
  $latest = $null
  $prefix = 'PLAYER_SEEK_LATENCY '
  foreach ($line in Get-Content -LiteralPath $LogPath) {
    $index = $line.IndexOf($prefix, [StringComparison]::Ordinal)
    if ($index -lt 0) { continue }
    $json = $line.Substring($index + $prefix.Length).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) { continue }
    try {
      $candidate = $json | ConvertFrom-Json
      if ($null -ne $candidate) { $latest = $candidate }
    } catch {
      # Flutter runner 可能截断长 JSON；只跳过当前行，不能把实验失败改写成未运行。
    }
  }
  if ($null -eq $latest -or
      $latest.PSObject.Properties.Name -notcontains 'reverseDirectionExperiment') {
    return $null
  }
  return $latest.reverseDirectionExperiment
}

function Get-StabilityFailureCategory {
  param([string]$LogPath)
  if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    return 'integration_log_missing'
  }
  $content = Get-Content -LiteralPath $LogPath -Raw
  if ($content -match 'PLAYER_EXACT_SEEK_UNCONFIRMED') {
    return 'exact_seek_position_unconfirmed'
  }
  if ($content -match 'Guarded function conflict|TestAsyncUtils') {
    return 'flutter_test_guarded_async_conflict'
  }
  if ($content -match 'TimeoutException') {
    return 'integration_timeout'
  }
  return 'integration_test_failed'
}

if ($SamplePaths.Count -eq 0) {
  # 本机自然片源只作为便捷默认值；仓库不分发这些文件，CI 或其它开发机必须显式传入。
  $SamplePaths = @(
    (Join-Path $repoRoot '.local\qa\natural-compression-ab\samples\live-face-low-650k.mp4'),
    (Join-Path $repoRoot '.local\qa\natural-compression-ab\samples\animation-gradient-low-650k.mp4'),
    (Join-Path $repoRoot '.local\qa\natural-compression-ab\samples\dark-scene-low-650k.mp4')
  )
}
if ($SamplePaths.Count -lt 3) {
  throw '双后端稳定性矩阵至少需要三段真实片源。'
}
if ($Backends.Count -lt 2 -or @($Backends | Sort-Object -Unique).Count -ne $Backends.Count) {
  throw '后端对照至少需要两个且互不重复的 backend；可选值为 mediaKit、mpv、hwnd。'
}
$resolvedSamples = @()
foreach ($sample in $SamplePaths) {
  if (-not (Test-Path -LiteralPath $sample -PathType Leaf)) {
    throw "稳定性矩阵片源不存在：$sample"
  }
  $resolvedSamples += [System.IO.Path]::GetFullPath($sample)
}

if (-not $Output) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $Output = Join-Path $repoRoot ".local\qa\player-backend-stability\$stamp"
}
if (-not [System.IO.Path]::IsPathRooted($Output)) {
  $Output = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
}
if (Test-Path -LiteralPath $Output) {
  throw "稳定性矩阵输出目录已存在，拒绝覆盖：$Output"
}
New-Item -ItemType Directory -Force -Path $Output | Out-Null

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens

# 只读取当前显示器的 Windows 显示模式，用于把“4K/高刷新率/DPI”环境写进报告。
# 这是显示器 inventory，不等同于窗口已经跨屏移动；跨屏仍由 physicalCrossDpiStatus
# 和人工实机证据裁决，避免把单屏自动跑误报成物理跨 DPI 通过。
if (-not ('LocalTagPlayerDisplayProbe' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class LocalTagPlayerDisplayProbe
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(
        string deviceName,
        int modeNum,
        ref DevMode devMode);
}
'@
}

function Get-DisplayInventory {
  $inventory = @()
  foreach ($screen in $screens) {
    $mode = New-Object LocalTagPlayerDisplayProbe+DevMode
    $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)
    $hasMode = [LocalTagPlayerDisplayProbe]::EnumDisplaySettings(
      $screen.DeviceName,
      -1,
      [ref]$mode)
    $inventory += [ordered]@{
      deviceName = $screen.DeviceName
      primary = $screen.Primary
      bounds = [ordered]@{
        x = $screen.Bounds.X
        y = $screen.Bounds.Y
        width = $screen.Bounds.Width
        height = $screen.Bounds.Height
      }
      workingArea = [ordered]@{
        x = $screen.WorkingArea.X
        y = $screen.WorkingArea.Y
        width = $screen.WorkingArea.Width
        height = $screen.WorkingArea.Height
      }
      bitsPerPixel = $screen.BitsPerPixel
      displayModeObserved = [bool]$hasMode
      nativeWidth = if ($hasMode) { $mode.dmPelsWidth } else { $null }
      nativeHeight = if ($hasMode) { $mode.dmPelsHeight } else { $null }
      refreshRateHz = if ($hasMode) { $mode.dmDisplayFrequency } else { $null }
      logicalDpi = if ($hasMode) { $mode.dmLogPixels } else { $null }
    }
  }
  return @($inventory)
}

$displayInventory = @(Get-DisplayInventory)
$displayEvidenceScope = [ordered]@{
  source = 'windows-forms-screen-enum-display-settings'
  evidenceKind = 'display-inventory-only'
  refreshRateAndDpiObserved = @($displayInventory | Where-Object {
      $_.displayModeObserved -eq $true
    } | ForEach-Object { $_.deviceName })
  physicalWindowMoveConfirmed = $false
  note = '显示器模式可观测；窗口跨屏、不同缩放和全屏切换仍需实机证据。'
}
if ($PhysicalCrossDpiStatus -eq 'simulated') {
  # 单屏模拟只验证 Flutter metrics、Surface 重算和状态机，不声称发生了物理跨屏。
  $effectivePhysicalDpiStatus = 'simulated-single-monitor'
} elseif ($PhysicalCrossDpiStatus -eq 'auto') {
  # 自动测试无法在单显示器上证明真实跨 DPI；多显示器也需要确认两块屏幕缩放不同并实际移窗。
  $effectivePhysicalDpiStatus = if ($screens.Count -lt 2) {
    'not-run-single-monitor'
  } else {
    'pending-physical-cross-display'
  }
} else {
  $effectivePhysicalDpiStatus = $PhysicalCrossDpiStatus
}

$env:LOCAL_TAG_PLAYER_STABILITY_SAMPLES = $resolvedSamples -join '|'
$env:LOCAL_TAG_PLAYER_STABILITY_LONG_SECONDS = $LongPlaySeconds.ToString()
$env:LOCAL_TAG_PLAYER_STABILITY_SWITCHES = $RapidSwitchCount.ToString()
$env:LOCAL_TAG_PLAYER_STABILITY_MAX_DROPPED_FRAMES = $MaxDroppedFrames.ToString()
$env:LOCAL_TAG_PLAYER_STABILITY_PHYSICAL_DPI_STATUS = $effectivePhysicalDpiStatus

$runResults = @()
try {
  foreach ($backend in $Backends) {
    $backendOutput = Join-Path $Output $backend
    New-Item -ItemType Directory -Force -Path $backendOutput | Out-Null
    $env:LOCAL_TAG_PLAYER_STABILITY_BACKEND = $backend
    $env:LOCAL_TAG_PLAYER_STABILITY_OUTPUT = $backendOutput
    $logPath = Join-Path $backendOutput 'integration.log'

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($Profile) {
      & $Flutter drive `
        --profile `
        --driver (Join-Path $repoRoot 'test_driver\integration_test.dart') `
        --target (Join-Path $repoRoot 'integration_test\player_backend_stability_matrix_test.dart') `
        -d windows *>&1 |
        Tee-Object -FilePath $logPath
    } else {
      & $Flutter test `
        integration_test/player_backend_stability_matrix_test.dart `
        -d windows *>&1 |
        Tee-Object -FilePath $logPath
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference

    $reportPath = Join-Path $backendOutput "$backend-stability.json"
    $report = if (Test-Path -LiteralPath $reportPath) {
      Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    } else {
      $null
    }
    $traceSummary = Get-SeekTraceSummary -LogPath $logPath
    $reverseKeyframeTrace = Get-SeekLatencyTrace -LogPath $logPath
    $reverseDirectionExperiment = Get-ReverseDirectionExperiment -LogPath $logPath
    if ($null -ne $report) {
      $report | Add-Member -NotePropertyName 'qaSeekFrameObservation' `
        -NotePropertyValue $traceSummary -Force
      $report | Add-Member -NotePropertyName 'qaReverseKeyframeTrace' `
        -NotePropertyValue $reverseKeyframeTrace -Force
      $report | Add-Member -NotePropertyName 'qaReverseDirectionExperiment' `
        -NotePropertyValue $reverseDirectionExperiment -Force
      # 单 backend 报告也必须保留增强后的证据；只挂到内存中的总矩阵会让后续
      # 直接审查 reportPath 时丢失当前首帧阶段与反向运行态 trace。
      $report | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $reportPath -Encoding utf8
    } else {
      # 集成测试可能在报告写回前因精确定位或 teardown 失败；仍生成匿名失败报告，
      # 让同机 Texture/HWND 对照保留失败阶段和已有 trace，而不是让 reportPath 指向空文件。
      $report = [pscustomobject]@{
        schemaVersion = 1
        platform = 'windows'
        playerBackend = $backend
        backendAvailability = 'unknown'
        automatedPass = $false
        releaseGate = 'failed'
        status = 'failed-no-report'
        failureCategory = Get-StabilityFailureCategory -LogPath $logPath
        qaSeekFrameObservation = $traceSummary
        qaReverseKeyframeTrace = $reverseKeyframeTrace
        qaReverseDirectionExperiment = $reverseDirectionExperiment
        scenarios = @{}
      }
      $report | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $reportPath -Encoding utf8
    }
    $runResults += [PSCustomObject]@{
      backend = $backend
      exitCode = $exitCode
      reportPath = $reportPath
      report = $report
      seekFrameObservation = $traceSummary
      reverseKeyframeTrace = $reverseKeyframeTrace
      reverseDirectionExperiment = $reverseDirectionExperiment
    }
  }
} finally {
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_BACKEND -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_SAMPLES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_LONG_SECONDS -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_SWITCHES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_MAX_DROPPED_FRAMES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_PHYSICAL_DPI_STATUS -ErrorAction SilentlyContinue
}

$backendReports = @{}
foreach ($run in $runResults) {
  $backendReports[$run.backend] = $run.report
}
$automatedPass = ($runResults | Where-Object {
    $_.exitCode -ne 0 -or $null -eq $_.report -or $_.report.automatedPass -ne $true
  }).Count -eq 0
$releaseGate = if (-not $automatedPass) {
  'failed'
} elseif ($effectivePhysicalDpiStatus -eq 'simulated-single-monitor') {
  'passed-simulated-cross-dpi'
} elseif ($effectivePhysicalDpiStatus -eq 'passed') {
  'passed'
} else {
  'pending-physical-cross-dpi'
}

$matrix = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  platform = 'windows'
  automatedPass = $automatedPass
  releaseGate = $releaseGate
  physicalCrossDpiStatus = $effectivePhysicalDpiStatus
  displayCount = $screens.Count
  displayInventory = $displayInventory
  physicalCrossDpiEvidence = $displayEvidenceScope
  requestedLongPlaySecondsPerBackend = $LongPlaySeconds
  requestedRapidSwitchesPerBackend = $RapidSwitchCount
  maxDroppedFramesPerBackend = $MaxDroppedFrames
  backends = $backendReports
  platformGates = [ordered]@{
    windows = [ordered]@{
      mediaKit = 'available'
      mpv = 'available-libmpv-flutter-texture'
      hwnd = 'available-qa-only-child-hwnd'
    }
    macos = [ordered]@{
      mediaKit = 'available'
      mpv = 'blocked-native-backend-not-implemented'
    }
    linux = [ordered]@{
      mediaKit = 'available'
      mpv = 'blocked-native-backend-not-implemented'
    }
  }
}
$matrixPath = Join-Path $Output 'player-backend-stability-matrix.json'
$matrix | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath $matrixPath -Encoding utf8

Write-Host "稳定性矩阵：$matrixPath"
Write-Host "自动门禁：$automatedPass；发布门禁：$releaseGate；真实跨 DPI：$effectivePhysicalDpiStatus"
if (-not $automatedPass) {
  exit 1
}
