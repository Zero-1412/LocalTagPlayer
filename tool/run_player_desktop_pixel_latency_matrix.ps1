<#
.SYNOPSIS
  对同一真实本地样本重复启动独立 Debug QA 会话，汇总桌面像素输入延迟 p50/p95。

.DESCRIPTION
  每次 run 都重新创建已预热至七秒以上、暂停的正式 MediaKit Texture 会话，避免一次反向
  seek 已接近零秒后继续测量而得到无效样本。单次输入不含打开耗时；独立会话之间不共享
  Player、Texture 或用户数据。输出只含匿名时延和采样率，不含媒体路径或像素。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Sample,
  [ValidateSet('click', 'progressDrag', 'forward', 'backward', 'manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')]
  [string]$Action = 'click',
  [ValidateRange(3, 15)]
  [int]$Runs = 7,
  [ValidateRange(30, 240)]
  [int]$FrameRate = 120,
  [ValidateRange(10, 240)]
  [int]$MinimumEffectiveCaptureFps = 80,
  # 每个独立实体键盘会话可等待一次人工触发；该等待不计入 input -> DWM 时延。
  [ValidateRange(3000, 30000)]
  [int]$ManualInputTimeoutMilliseconds = 30000,
  [ValidateRange(300, 10000)]
  [int]$ManualLongHoldMinimumMilliseconds = 600,
  # 仅自动化 scan-code forward/backward 对照使用；实体 manualLong* 永远不注入按键。
  [ValidateRange(0, 5000)]
  [int]$HoldMilliseconds = 0,
  [ValidateRange(0.1, 30.0)]
  [double]$PixelChangeThresholdPercent = 1.5,
  [ValidateSet('exactOnly', 'fastPreviewThenExact')]
  [string]$ProgressDragSeekMode = 'exactOnly',
  [ValidateRange(960, 7680)]
  [int]$InitialWindowWidth = 1280,
  [ValidateRange(540, 4320)]
  [int]$InitialWindowHeight = 720,
  # 真实 PlayerPage 动作使用无常驻队列的独立逻辑窗口；4K/DPI 场景可显式覆写，
  # 不把宽窗口侧栏面积错误算进主进度 Slider 的物理拖动轨道。
  [ValidateRange(960, 7680)]
  [int]$PlayerPageInitialWindowWidth = 960,
  [ValidateRange(540, 4320)]
  [int]$PlayerPageInitialWindowHeight = 720,
  # MediaKit/ANGLE 释放 D3D 表面是异步的；独立会话间给出短冷却，避免上一代退出尚未
  # 完成时下一代刚好重建造成 QA 启动不稳定。它不计入每次输入到像素的测量窗口。
  [ValidateRange(500, 10000)]
  [int]$InterRunCooldownMilliseconds = 1500,
  [string]$Output = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Sample -PathType Leaf)) {
  throw "本地样本不存在：$Sample"
}
if ($HoldMilliseconds -gt 0 -and $Action -notin @('forward', 'backward')) {
  throw 'HoldMilliseconds 仅允许用于自动化 forward/backward 对照，不得用于实体或拖动动作。'
}
if (-not $Output) {
  $Output = Join-Path $PSScriptRoot ("..\.local\qa\player-desktop-pixel-matrix\" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw "输出目录已存在，拒绝覆盖既有证据：$Output"
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

function Get-Percentile {
  param([int[]]$Values, [double]$Percentile)
  $sorted = @($Values | Sort-Object)
  if ($sorted.Count -eq 0) { throw '没有可汇总的桌面像素样本。' }
  $index = [Math]::Round(($sorted.Count - 1) * $Percentile)
  return [int]$sorted[[Math]::Max(0, [Math]::Min($sorted.Count - 1, $index))]
}

$gate = Join-Path $PSScriptRoot 'run_player_desktop_pixel_latency_gate.ps1'
$realPlayerPageAction = $Action -in @('progressDrag', 'forward', 'backward', 'manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')
$manualKeyboardAction = $Action -in @('manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')
$manualLongKeyboardAction = $Action -in @('manualLongForward', 'manualLongBackward')
$inputMode = switch ($Action) {
  'click' { 'win32-mouse-click' }
  'progressDrag' { 'win32-mouse-drag-progress-track' }
  'manualForward' { 'manual-keyboard-native-qpc' }
  'manualBackward' { 'manual-keyboard-native-qpc' }
  'manualLongForward' { 'manual-keyboard-native-qpc-long-hold' }
  'manualLongBackward' { 'manual-keyboard-native-qpc-long-hold' }
  # 正式 PlayerPage 门禁统一走 SendInput scan-code，避免 Flutter Windows 将
  # virtual-key 解析成 other；矩阵标签必须与实际探针报告一致。
  'forward' { 'win32-keyboard-scancode' }
  'backward' { 'win32-keyboard-scancode' }
  default { 'win32-keyboard-scan-code' }
}
if ($HoldMilliseconds -gt 0) {
  # 正式 PlayerPage 门禁走 SendInput scan-code，避免 Flutter Windows 将 virtual-key
  # 解析成 other；矩阵标签必须与实际探针报告一致，不能沿用旧的 virtual-key 名称。
  $inputMode = 'win32-keyboard-scancode-long-hold'
}
$requestedWindowWidth = if ($realPlayerPageAction) {
  $PlayerPageInitialWindowWidth
} else {
  $InitialWindowWidth
}
$requestedWindowHeight = if ($realPlayerPageAction) {
  $PlayerPageInitialWindowHeight
} else {
  $InitialWindowHeight
}
$records = @()
function Get-QaLifecycleEvents {
  param([string]$RunOutput)
  $lifecyclePath = Join-Path $RunOutput 'qa-lifecycle.jsonl'
  if (-not (Test-Path -LiteralPath $lifecyclePath)) { return @() }
  $events = @()
  foreach ($line in Get-Content -LiteralPath $lifecyclePath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
      $event = $line | ConvertFrom-Json
      if (-not [string]::IsNullOrWhiteSpace($event.event)) {
        $events += [string]$event.event
      }
    } catch {
      # 生命周期文件出现半行表示进程异常退出；只记录匿名分类，不能把原始内容混入报告。
      $events += 'lifecycle_line_unreadable'
    }
  }
  return @($events)
}

function Get-QaRuntimeEvidence {
  param([string]$RunOutput)

  # 每个独立会话只汇总匿名运行态：硬解、解码/VO 掉帧属性、Texture 代次/尺寸和
  # resize 状态。空属性保持 null，不把 mpv 的 empty/unavailable 猜成零；这些字段
  # 仍是后端运行态证据，不能伪装成 DWM 实际呈现帧。
  $ready = $null
  $readyPath = Join-Path $RunOutput 'ready.json'
  if (Test-Path -LiteralPath $readyPath) {
    try { $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json } catch { $ready = $null }
  }
  $generationValues = @()
  $textureSizes = @()
  $resizeStates = @()
  $rebuildEvents = 0
  $previousRendererGeneration = $null
  $rendererPath = Join-Path $RunOutput 'renderer-events.jsonl'
  if (Test-Path -LiteralPath $rendererPath) {
    foreach ($line in Get-Content -LiteralPath $rendererPath) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try { $event = $line | ConvertFrom-Json } catch { continue }
      if ($null -ne $event.textureGenerationCount) {
        $generation = [int]$event.textureGenerationCount
        $generationValues += $generation
        if ($null -ne $previousRendererGeneration -and $generation -gt $previousRendererGeneration) {
          $rebuildEvents++
        }
        $previousRendererGeneration = $generation
      }
      if ($null -ne $event.textureWidthPx -and $null -ne $event.textureHeightPx) {
        $textureSizes += ('{0}x{1}' -f $event.textureWidthPx, $event.textureHeightPx)
      }
      if (-not [string]::IsNullOrWhiteSpace([string]$event.textureResizeState)) {
        $resizeStates += [string]$event.textureResizeState
      }
    }
  }
  if ($null -ne $ready -and $null -ne $ready.textureGenerationCount) {
    $generationValues += [int]$ready.textureGenerationCount
  }

  $hwdecValues = @()
  $firstFrameEvidenceValues = @()
  $frameEvidenceValues = @()
  $decoderDropValues = @()
  $voDropValues = @()
  $totalDropValues = @()
  $runtimeSnapshotCount = 0
  $logPath = Join-Path $RunOutput 'debug-qa.stdout.log'
  if (Test-Path -LiteralPath $logPath) {
    foreach ($line in Get-Content -LiteralPath $logPath) {
      if ($line -match 'hwdec_current=(\S+)') {
        if ($Matches[1] -notin @('empty', 'unavailable')) { $hwdecValues += $Matches[1] }
      }
      if ($line -match 'first_frame_evidence=(\S+)') {
        if ($Matches[1] -notin @('empty', 'unavailable')) { $firstFrameEvidenceValues += $Matches[1] }
      }
      if ($line -match 'frame_presentation_evidence=(\S+)') {
        if ($Matches[1] -notin @('empty', 'unavailable')) { $frameEvidenceValues += $Matches[1] }
      }
      if (-not $line.Contains('snapshot_')) { continue }
      $runtimeSnapshotCount++
      foreach ($field in @(
          @{ Name = 'decoder'; Pattern = 'snapshot_decoder_drop_frames=(\d+)' },
          @{ Name = 'vo'; Pattern = 'snapshot_vo_drop_frames=(\d+)' },
          @{ Name = 'total'; Pattern = 'snapshot_total_drop_frames=(\d+)' }
        )) {
        if ($line -match $field.Pattern) {
          switch ($field.Name) {
            'decoder' { $decoderDropValues += [int]$Matches[1] }
            'vo' { $voDropValues += [int]$Matches[1] }
            'total' { $totalDropValues += [int]$Matches[1] }
          }
        }
      }
      if ($line -match 'snapshot_hwdec_current=(\S+)') {
        if ($Matches[1] -notin @('empty', 'unavailable')) { $hwdecValues += $Matches[1] }
      }
      if ($line -match 'snapshot_frame_presentation_evidence=(\S+)') {
        if ($Matches[1] -notin @('empty', 'unavailable')) { $frameEvidenceValues += $Matches[1] }
      }
      if ($line -match 'snapshot_texture_generation=(\d+)') {
        $generationValues += [int]$Matches[1]
      }
      if ($line -match 'snapshot_texture_width_px=([0-9.]+) snapshot_texture_height_px=([0-9.]+)') {
        $textureSizes += ('{0}x{1}' -f $Matches[1], $Matches[2])
      }
      if ($line -match 'snapshot_texture_resize_state=(\S+)') {
        $resizeStates += $Matches[1]
      }
    }
  }
  $uniqueGenerations = @($generationValues | Sort-Object -Unique)
  $uniqueSizes = @($textureSizes | Sort-Object -Unique)
  $uniqueResizeStates = @($resizeStates | Sort-Object -Unique)
  $uniqueHwdec = @($hwdecValues | Sort-Object -Unique)
  $uniqueFirstFrameEvidence = @($firstFrameEvidenceValues | Sort-Object -Unique)
  $uniqueFrameEvidence = @($frameEvidenceValues | Sort-Object -Unique)
  return [ordered]@{
    evidenceKind = if ($runtimeSnapshotCount -gt 0) {
      'backend-runtime-snapshot-not-desktop-pixels'
    } elseif ($null -ne $ready -or $uniqueGenerations.Count -gt 0) {
      'qa-ready-and-renderer-state-not-desktop-pixels'
    } else {
      'unavailable'
    }
    runtimeSnapshotCount = $runtimeSnapshotCount
    hwdecCurrent = $uniqueHwdec
    hwdecCurrentFinal = if ($hwdecValues.Count -gt 0) { [string]$hwdecValues[-1] } else { $null }
    framePresentationEvidence = $uniqueFrameEvidence
    firstFrameEvidence = $uniqueFirstFrameEvidence
    decoderDropFramesMax = if ($decoderDropValues.Count -gt 0) { ($decoderDropValues | Measure-Object -Maximum).Maximum } else { $null }
    voDropFramesMax = if ($voDropValues.Count -gt 0) { ($voDropValues | Measure-Object -Maximum).Maximum } else { $null }
    totalDropFramesMax = if ($totalDropValues.Count -gt 0) { ($totalDropValues | Measure-Object -Maximum).Maximum } else { $null }
    textureGenerationValues = $uniqueGenerations
    textureGenerationDelta = if ($uniqueGenerations.Count -gt 1) {
      [int]$uniqueGenerations[-1] - [int]$uniqueGenerations[0]
    } else { 0 }
    textureRebuildEventCount = $rebuildEvents
    textureSizes = $uniqueSizes
    textureResizeStates = $uniqueResizeStates
    adaptiveTextureSizingEnabled = if ($null -ne $ready -and $null -ne $ready.adaptiveTextureSizingEnabled) {
      [bool]$ready.adaptiveTextureSizingEnabled
    } else { $null }
  }
}

for ($index = 1; $index -le $Runs; $index++) {
  $runOutput = Join-Path $Output ("run-{0:D2}" -f $index)
  $gateFailure = $null
  try {
    if ($manualKeyboardAction) {
      # 不注入、不中断、不折叠为无人值守的“超时样本”。每轮均独立启动并在静态
      # 基线后等待操作者按下单次实体 J/L；QPC 起点由 FLUTTERVIEW 原生消息给出。
      Write-Output "PLAYER_DESKTOP_PIXEL_MANUAL_INPUT run=$index/$Runs action=$Action waiting_for_physical_key=true"
    }
    & $gate -Sample $Sample -Action $Action -Samples 1 -FrameRate $FrameRate `
      -MinimumEffectiveCaptureFps $MinimumEffectiveCaptureFps `
      -ManualInputTimeoutMilliseconds $ManualInputTimeoutMilliseconds `
      -ManualLongHoldMinimumMilliseconds $ManualLongHoldMinimumMilliseconds `
      -HoldMilliseconds $HoldMilliseconds `
      -PixelChangeThresholdPercent $PixelChangeThresholdPercent `
      -ProgressDragSeekMode $ProgressDragSeekMode `
      -InitialWindowWidth $InitialWindowWidth -InitialWindowHeight $InitialWindowHeight `
      -PlayerPageInitialWindowWidth $PlayerPageInitialWindowWidth `
      -PlayerPageInitialWindowHeight $PlayerPageInitialWindowHeight `
      -Output $runOutput
    if (-not $?) { throw 'gate_nonzero_exit' }
  } catch {
    # 失败原因应由匿名生命周期阶段和存在性判断表达；异常消息可能含调用环境的私有路径。
    $gateFailure = 'gate_failed'
  }
  $summaryPath = Join-Path $runOutput 'desktop-pixels\desktop-pixel-summary.json'
  $reportPath = Join-Path $runOutput 'desktop-pixels\desktop-pixel-report.json'
  $lifecycleEvents = @(Get-QaLifecycleEvents $runOutput)
  $summary = $null
  if (Test-Path -LiteralPath $summaryPath) {
    try {
      $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    } catch {
      $gateFailure = 'summary_unreadable'
    }
  }
  $desktopReport = $null
  if (Test-Path -LiteralPath $reportPath) {
    try { $desktopReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json } catch { $gateFailure = 'report_unreadable' }
  }
  $runtimeEvidence = Get-QaRuntimeEvidence $runOutput
  $manualHoldSatisfied = -not $manualLongKeyboardAction -or (
    $null -ne $desktopReport -and
    @($desktopReport.actions).Count -eq 1 -and
    [bool]$desktopReport.actions[0].manualHoldSatisfied
  )
  $valid = $null -ne $summary -and
    $summary.captureRatePassed -and
    [int]$summary.successfulSamples -eq 1 -and
    [int]$summary.timedOutSamples -eq 0 -and
    $manualHoldSatisfied -and
    $null -eq $gateFailure
  if ($valid -and $realPlayerPageAction -and -not $manualKeyboardAction -and
      $null -ne $desktopReport -and
      @($desktopReport.actions).Count -eq 1 -and
      -not [bool]$desktopReport.actions[0].inputSemanticConfirmed) {
    # 防御性门禁：即使探针/摘要未来出现回归，缺少 PlayerPage 匿名回执的
    # 自动键盘样本也不能进入独立 p95。DWM 像素变化不等于快捷键已命中播放器。
    $valid = $false
    $gateFailure = 'player_keyboard_semantic_evidence_missing'
  }
  if ($valid) {
    $records += [pscustomobject]@{
      run = $index
      status = 'valid'
      inputDownToPixelMs = [int]$summary.p50InputDownToPixelMs
      # 实体 QPC 合同只锚定 WM_KEYDOWN。松键并非 seek 提交边界，因此不能把默认零值
      # 混入 KeyUp p50/p95；自动长按若在按住期间已出现首帧，Up -> 首帧没有定义值，
      # 也必须保留 null，而不是把 PowerShell 的空值强转为 0。
      inputUpToPixelMs = if ($manualKeyboardAction -or $null -eq $summary.p50InputUpToPixelMs) { $null } else { [int]$summary.p50InputUpToPixelMs }
      effectiveCaptureFps = [double]$summary.effectiveCaptureFps
      windowDpi = [int]$summary.windowDpi
      longestUnchangedRunMs = [int]$summary.longestUnchangedRunMs
      manualHoldDurationMs = if ($manualLongKeyboardAction) { [int]$desktopReport.actions[0].physicalKeyHoldDurationMs } else { $null }
      runtimeEvidence = $runtimeEvidence
      lifecycle = $lifecycleEvents
    }
  } else {
    $records += [pscustomobject]@{
      run = $index
      status = 'invalid'
      failure = if ($null -ne $gateFailure) {
        $gateFailure
      } elseif ($null -eq $summary) {
        'summary_missing'
      } elseif (-not $summary.captureRatePassed) {
        'capture_rate_insufficient'
      } elseif (-not $manualHoldSatisfied) {
        'manual_hold_contract_invalid'
      } else {
        'pixel_evidence_invalid'
      }
      runtimeEvidence = $runtimeEvidence
      lifecycle = $lifecycleEvents
    }
  }
  if ($index -lt $Runs) {
    Start-Sleep -Milliseconds $InterRunCooldownMilliseconds
  }
}

$validRecords = @($records | Where-Object status -eq 'valid')
$invalidRecords = @($records | Where-Object status -eq 'invalid')
$down = @($validRecords | ForEach-Object inputDownToPixelMs)
$up = @($validRecords | ForEach-Object inputUpToPixelMs | Where-Object { $null -ne $_ })
$matrix = [ordered]@{
  evidence = 'desktop-composited-pixel-change'
  inputMode = $inputMode
  manualLongHoldMinimumMilliseconds = $ManualLongHoldMinimumMilliseconds
  holdMilliseconds = $HoldMilliseconds
  runs = $Runs
  frameRateRequested = $FrameRate
  minimumEffectiveCaptureFps = $MinimumEffectiveCaptureFps
  pixelChangeThresholdPercent = $PixelChangeThresholdPercent
  progressDragSeekMode = $ProgressDragSeekMode
  surface = if ($realPlayerPageAction) { 'product-player-page' } else { 'minimal-texture-qa' }
  requestedWindowWidth = $requestedWindowWidth
  requestedWindowHeight = $requestedWindowHeight
  windowDpi = if ($validRecords.Count -gt 0) {
    @($validRecords | Select-Object -ExpandProperty windowDpi | Sort-Object -Unique)
  } else { @() }
  interRunCooldownMilliseconds = $InterRunCooldownMilliseconds
  successfulRuns = $validRecords.Count
  failedRuns = $invalidRecords.Count
  p95Eligible = $invalidRecords.Count -eq 0 -and $validRecords.Count -eq $Runs
  inputDownToPixel = if ($validRecords.Count -gt 0) { [ordered]@{
    p50Ms = Get-Percentile $down 0.50
    p95Ms = Get-Percentile $down 0.95
    maxMs = ($down | Measure-Object -Maximum).Maximum
  } } else { $null }
  inputUpToPixel = if ($up.Count -gt 0) { [ordered]@{
    p50Ms = Get-Percentile $up 0.50
    p95Ms = Get-Percentile $up 0.95
    maxMs = ($up | Measure-Object -Maximum).Maximum
  } } else { $null }
  longestUnchangedRunMs = if ($validRecords.Count -gt 0) {
    ($validRecords | Measure-Object -Property longestUnchangedRunMs -Maximum).Maximum
  } else { $null }
  manualHoldDurationsMs = if ($manualLongKeyboardAction -and $validRecords.Count -gt 0) {
    @($validRecords | ForEach-Object manualHoldDurationMs)
  } else { @() }
  runtimeEvidence = @($records | ForEach-Object runtimeEvidence)
  records = $records
}
$matrixJson = $matrix | ConvertTo-Json -Depth 5 -Compress
[System.IO.File]::WriteAllText(
  (Join-Path $Output 'desktop-pixel-matrix-summary.json'),
  $matrixJson,
  [System.Text.UTF8Encoding]::new($false)
)
Write-Output "PLAYER_DESKTOP_PIXEL_MATRIX $matrixJson"
if (-not $matrix.p95Eligible) {
  throw "独立矩阵未形成 $Runs/$Runs 次有效样本；已保留匿名生命周期，不得生成 p95 结论。"
}
