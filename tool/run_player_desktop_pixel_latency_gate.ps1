<#
.SYNOPSIS
  启动正式 MediaKit Texture Debug QA 程序，并以 Win32 输入/桌面像素完成单次门禁。

.DESCRIPTION
  刚构建的 Debug 可执行程序创建一个已暂停的正式 Texture 会话并写出 PID/窗口标题握手
  文件；随后本脚本才调用桌面像素探针。click/fullscreen 走最小 MediaKit 表面 QA，
  playerFullscreen 走正式 PlayerPage；真实
  PlayerPage 的 progressDrag/forward/backward 走产品页面、快捷键和 Slider，不加载资料库
  或写用户播放数据。两类动作均只测一次；p50/p95 必须来自独立进程矩阵。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Sample,
  [ValidateSet('click', 'fullscreen', 'playerFullscreen', 'progressDrag', 'forward', 'backward', 'manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')]
  [string]$Action = 'click',
  [ValidateRange(1, 7)]
  [int]$Samples = 1,
  [ValidateRange(30, 240)]
  [int]$FrameRate = 120,
  [ValidateRange(10, 240)]
  [int]$MinimumEffectiveCaptureFps = 80,
  # 实体键盘门禁在静态基线后等待操作者的单次真实 J/L；等待本身不参与 QPC 延迟。
  [ValidateRange(3000, 30000)]
  [int]$ManualInputTimeoutMilliseconds = 30000,
  [ValidateRange(300, 10000)]
  [int]$ManualLongHoldMinimumMilliseconds = 600,
  # 仅自动化 virtual-key 对照使用；实体 manualLong* 永远不注入按键。
  [ValidateRange(0, 5000)]
  [int]$HoldMilliseconds = 0,
  # 4K 中心裁剪的画面切换可能只覆盖采样栅格的一小部分；阈值必须显式记录，不能
  # 因一次失败而暗中修改探针默认值。静止基线和连续两帧变化仍是必要条件。
  [ValidateRange(0.1, 30.0)]
  [double]$PixelChangeThresholdPercent = 1.5,
  # 默认等同正式单次精确定位；fastPreviewThenExact 仅启动隔离的 Debug PlayerPage QA，
  # 用于测量快速关键帧反馈与最终精确收敛，绝不影响正常产品进程。
  [ValidateSet('exactOnly', 'fastPreviewThenExact')]
  [string]$ProgressDragSeekMode = 'exactOnly',
  [ValidateRange(0, 3000)]
  [int]$SettleMilliseconds = 350,
  [ValidateRange(0, 15000)]
  [int]$P95BudgetMs = 0,
  [ValidateRange(960, 7680)]
  [int]$InitialWindowWidth = 1280,
  [ValidateRange(540, 4320)]
  [int]$InitialWindowHeight = 720,
  # 真实 PlayerPage 默认以窄窗口挂载，避免右侧常驻队列压缩视频表面后，按整个客户区
  # 百分比计算的物理拖动终点落到队列而不是 Slider。4K/DPI 实验可显式覆盖这两个值。
  [ValidateRange(960, 7680)]
  [int]$PlayerPageInitialWindowWidth = 960,
  [ValidateRange(540, 4320)]
  [int]$PlayerPageInitialWindowHeight = 720,
  [string]$DebugExecutable = '',
  [string]$Output = '',
  # 仅 Debug QA：隔离自适应 Texture 尺寸回落/重建是否触发桌面引擎崩溃；默认保持正式策略。
  [switch]$DisableAdaptiveTextureSizing,
  # 仅 Debug QA：强制当前会话走软件解码，以验证降级提示与安全重新打开闭环。
  [switch]$ForceSoftwareDecode,
  # 仅 Debug QA：软件降级确认后自动执行一次与 banner 相同的安全重新打开动作。
  [switch]$AutoRetrySoftwareDecode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw '桌面像素门禁只支持 Windows。' }
if (-not (Test-Path -LiteralPath $Sample -PathType Leaf)) {
  throw "本地样本不存在：$Sample"
}
if ($HoldMilliseconds -gt 0 -and $Action -notin @('forward', 'backward')) {
  throw 'HoldMilliseconds 仅允许用于自动化 forward/backward 对照，不得用于实体或全屏动作。'
}
if (-not $Output) {
  $Output = Join-Path $PSScriptRoot ("..\.local\qa\player-desktop-pixel-gate\" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw "输出目录已存在，拒绝覆盖既有证据：$Output"
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

$readyPath = Join-Path $Output 'ready.json'
$failurePath = Join-Path $Output 'desktop-pixel-probe-failure.txt'
$qaFailurePath = Join-Path $Output 'desktop-pixel-qa-failure.txt'
$shutdownRequestPath = Join-Path $Output 'shutdown.request'
$probeOutput = Join-Path $Output 'desktop-pixels'
$realPlayerPageAction = $Action -in @('playerFullscreen', 'progressDrag', 'forward', 'backward', 'manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')
$manualKeyboardAction = $Action -in @('manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')
$manualLongKeyboardAction = $Action -in @('manualLongForward', 'manualLongBackward')
if ($AutoRetrySoftwareDecode -and -not $ForceSoftwareDecode) {
  throw 'AutoRetrySoftwareDecode 必须与 ForceSoftwareDecode 一起使用。'
}
if ($AutoRetrySoftwareDecode -and -not $realPlayerPageAction) {
  throw 'AutoRetrySoftwareDecode 只允许用于正式 PlayerPage QA。'
}
$windowTitle = if ($realPlayerPageAction) {
  'LocalTagPlayer Real PlayerPage QA'
} else {
  'LocalTagPlayer Desktop Pixel QA'
}
$logPath = Join-Path $Output 'debug-qa.stdout.log'
$errorPath = Join-Path $Output 'debug-qa.stderr.log'

# 将 Dart seek 阶段与桌面像素首变更做匿名动作窗口关联。
#
# 两套时钟不能直接相减：像素采样的 QPC 是系统级锚点，PLAYER_SEEK_TRACE 的
# mono_us 是 Dart 进程内 Stopwatch。因此这里只用两边已有的 UTC 侧车做关联，并在
# 输出中明确证据等级；它用于定位“后端帧已变但 DWM 仍未变”的段落，不伪造 QPC 延迟。
function Write-DesktopPixelTraceCorrelation {
  param(
    [string]$LogPath,
    [string]$PixelReportPath,
    [string]$NativeKeyboardEvidencePath,
    [string]$PlayerInputEvidencePath,
    [string]$OutputPath
  )

    $correlation = [ordered]@{
    schemaVersion = 2
    evidence = 'utc-input-window-correlation-only'
    status = 'unavailable'
    limitation = 'PLAYER_SEEK_TRACE mono_us 与桌面 QPC 不同源；实体消息同时提供 UTC 仅用于动作窗口筛选，不替代 QPC→DWM 延迟。窗口外 trace 不得借最近邻伪造为本次输入证据。'
    traceEvents = @()
    pixelActions = @()
    playerInputEvents = @()
    correlations = @()
    actionTraceSummaries = @()
  }
  try {
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $PixelReportPath -PathType Leaf)) {
      [System.IO.File]::WriteAllText(
        $OutputPath,
        ($correlation | ConvertTo-Json -Depth 20),
        [System.Text.UTF8Encoding]::new($false)
      )
      return
    }

    $traceEvents = @()
    foreach ($line in Get-Content -LiteralPath $LogPath) {
      $marker = 'PLAYER_SEEK_TRACE '
      $markerIndex = $line.IndexOf($marker, [StringComparison]::Ordinal)
      if ($markerIndex -lt 0) { continue }
      $fields = @{}
      foreach ($match in [regex]::Matches(
          $line.Substring($markerIndex + $marker.Length),
          '(?<key>[A-Za-z0-9_]+)=(?<value>[^\s]+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
      }
      $wallUtcUs = 0L
      $hasMicrosecondAnchor = [long]::TryParse(
        [string]$fields['wall_utc_us'],
        [ref]$wallUtcUs) -and $wallUtcUs -gt 0
      $wallUtcMs = 0L
      if (-not $hasMicrosecondAnchor -and
          (-not [long]::TryParse([string]$fields['wall_utc_ms'], [ref]$wallUtcMs) -or
           $wallUtcMs -le 0)) {
        continue
      }
      if (-not $hasMicrosecondAnchor) {
        $wallUtcUs = $wallUtcMs * 1000L
      } else {
        $wallUtcMs = [long][Math]::Floor($wallUtcUs / 1000L)
      }
      $runtimeSnapshot = [ordered]@{}
      foreach ($field in $fields.GetEnumerator()) {
        if ($field.Key.StartsWith('snapshot_', [StringComparison]::Ordinal)) {
          $runtimeSnapshot[$field.Key.Substring(9)] = [string]$field.Value
        }
      }
      $traceEvents += [ordered]@{
        trace = [string]$fields['trace']
        stage = [string]$fields['stage']
        targetMs = if ($fields.ContainsKey('target_ms')) {
          [int]$fields['target_ms']
        } else { $null }
        wallUtcMs = $wallUtcMs
        wallUtcUs = $wallUtcUs
        wallUtcPrecision = if ($hasMicrosecondAnchor) { 'microsecond' } else { 'millisecond-fallback' }
        monoUs = if ($fields.ContainsKey('mono_us')) {
          [long]$fields['mono_us']
        } else { $null }
        waitMs = if ($fields.ContainsKey('wait_ms')) {
          [int]$fields['wait_ms']
        } else { $null }
        frameEvidence = if ($fields.ContainsKey('frame_evidence')) {
          [string]$fields['frame_evidence']
        } else { $null }
        runtimeSnapshot = if ($runtimeSnapshot.Count -gt 0) {
          $runtimeSnapshot
        } else { $null }
      }
    }

    $nativeEvents = @()
    if (-not [String]::IsNullOrWhiteSpace($NativeKeyboardEvidencePath) -and
        (Test-Path -LiteralPath $NativeKeyboardEvidencePath -PathType Leaf)) {
      foreach ($line in Get-Content -LiteralPath $NativeKeyboardEvidencePath) {
        if ([String]::IsNullOrWhiteSpace($line)) { continue }
        try {
          $event = $line | ConvertFrom-Json
          if ($event.event -ne 'native_keyboard_message' -or
              [string]::IsNullOrWhiteSpace([string]$event.action) -or
              [string]::IsNullOrWhiteSpace([string]$event.phase)) {
            continue
          }
          $qpcUs = 0L
          $utcUs = 0L
          if (-not [long]::TryParse([string]$event.qpcUs, [ref]$qpcUs) -or
              -not [long]::TryParse([string]$event.utcUs, [ref]$utcUs) -or
              $qpcUs -le 0 -or $utcUs -le 0) {
            continue
          }
          $nativeEvents += [ordered]@{
            action = [string]$event.action
            phase = [string]$event.phase
            qpcUs = $qpcUs
            utcUs = $utcUs
          }
        } catch {
          # ready 行或半行不含输入证据；保留其它完整事件。
        }
      }
    }

    # 页面语义回执与原生消息分开读取；它只证明固定 action/phase 已进入 PlayerPage
    # Focus 链，不包含原始按键、目标位置、媒体标识或路径。最终报告保留 UTC 事件，
    # 让审查者能复核 native -> PlayerPage -> PLAYER_SEEK_TRACE 的三方窗口，而不是只看
    # 探针内存中的 inputSemanticConfirmed 布尔值。
    $playerInputEvents = @()
    if (-not [String]::IsNullOrWhiteSpace($PlayerInputEvidencePath) -and
        (Test-Path -LiteralPath $PlayerInputEvidencePath -PathType Leaf)) {
      foreach ($line in Get-Content -LiteralPath $PlayerInputEvidencePath) {
        if ([String]::IsNullOrWhiteSpace($line)) { continue }
        try {
          $event = $line | ConvertFrom-Json
          $eventName = [string]$event.event
          if ($eventName -notin @(
              'player_keyboard_event',
              'progress_slider_start',
              'progress_slider_committed',
              'progress_preview_seek_submitted',
              'progress_exact_seek_confirmed')) {
            continue
          }
          $utcUs = 0L
          if (-not [long]::TryParse([string]$event.utcUs, [ref]$utcUs) -or
              $utcUs -le 0) {
            continue
          }
          $action = if ($null -ne $event.PSObject.Properties['action']) {
            [string]$event.action
          } else { '' }
          $phase = if ($null -ne $event.PSObject.Properties['phase']) {
            [string]$event.phase
          } else { '' }
          if ($eventName -eq 'player_keyboard_event' -and
              ($action -notin @('forward', 'backward', 'other') -or
               $phase -notin @('down', 'repeat', 'up', 'unknown'))) {
            continue
          }
          $playerInputEvents += [ordered]@{
            event = $eventName
            action = $action
            phase = $phase
            utcUs = $utcUs
          }
        } catch {
          # 只跳过 ready 行或与写入交叠的半行，不影响其它匿名回执。
        }
      }
    }

    $pixelReport = Get-Content -LiteralPath $PixelReportPath -Raw | ConvertFrom-Json
    $epochTicks = 621355968000000000L
    $expectedAction = if ([int]$pixelReport.virtualKey -eq 0x4A) {
      'backward'
    } else {
      'forward'
    }
    # 自动化 win32-keyboard-* 也可能真实进入 PlayerPage Focus 链；它没有实体 QPC
    # 锚点，但页面语义仍应进入关联报告。QPC 证据等级另由 native 侧车单独决定。
    $isKeyboardInput = [string]$pixelReport.inputMode -like '*keyboard*'
    $pixelActions = @()
    foreach ($action in @($pixelReport.actions)) {
      $firstSample = @(
          @($action.samples) |
          Where-Object {
            [bool]$action.passed -and
              [long]$action.firstChangedPixelQpcUs -gt 0 -and
              $_.qpcUs -ge [long]$action.firstChangedPixelQpcUs
          } |
          Sort-Object qpcUs |
          Select-Object -First 1
      )
      $sample = if ($firstSample.Count -gt 0) { $firstSample[0] } else { $null }
      $firstChangedUtcUs = if ($null -ne $sample) {
        [long](([long]$sample.utcTicks - $epochTicks) / 10L)
      } else { $null }
      $nativeDown = @(
        $nativeEvents |
          Where-Object {
            $_.action -eq $expectedAction -and $_.phase -eq 'down' -and
              [long]$_.qpcUs -eq [long]$action.keyDownQpcUs
          } |
          Select-Object -First 1
      )
      $nativeDownEvent = if ($nativeDown.Count -gt 0) {
        $nativeDown[0]
      } else { $null }
      $nativeUp = @(
        $nativeEvents |
          Where-Object {
            $_.action -eq $expectedAction -and $_.phase -eq 'up' -and
              [long]$action.physicalKeyUpQpcUs -gt 0 -and
              [long]$_.qpcUs -eq [long]$action.physicalKeyUpQpcUs
          } |
          Select-Object -First 1
      )
      $nativeUpEvent = if ($nativeUp.Count -gt 0) { $nativeUp[0] } else { $null }
      # 旧侧车可能只有 qpcUs、当前侧车同时有 qpcUs/utcUs；先检查属性存在性，
      # 这样拖动/普通点击没有 native 文件时也能生成 correlation。
      $nativeDownQpcUs = if ($null -ne $nativeDownEvent -and
                             $null -ne $nativeDownEvent.PSObject.Properties['qpcUs']) {
        [long]$nativeDownEvent.qpcUs
      } else { $null }
      $nativeDownUtcUs = if ($null -ne $nativeDownEvent -and
                             $null -ne $nativeDownEvent.PSObject.Properties['utcUs']) {
        [long]$nativeDownEvent.utcUs
      } else { $null }
      $nativeUpQpcUs = if ($null -ne $nativeUpEvent -and
                           $null -ne $nativeUpEvent.PSObject.Properties['qpcUs']) {
        [long]$nativeUpEvent.qpcUs
      } else { $null }
      $nativeUpUtcUs = if ($null -ne $nativeUpEvent -and
                           $null -ne $nativeUpEvent.PSObject.Properties['utcUs']) {
        [long]$nativeUpEvent.utcUs
      } else { $null }
      $inputDownUtcUs = if ($null -ne $nativeDownUtcUs) {
        $nativeDownUtcUs
      } elseif ($null -ne $firstChangedUtcUs -and
                [int]$action.inputDownToFirstChangedPixelMs -gt 0) {
        [long]$firstChangedUtcUs -
          ([int]$action.inputDownToFirstChangedPixelMs * 1000L)
      } else { $null }
      $physicalKeyUpUtcUs = $nativeUpUtcUs
      $traceWindowStartUtcUs = if ($null -ne $inputDownUtcUs) {
        [long]$inputDownUtcUs - 500000L
      } else { $null }
      $traceWindowEndUtcUs = if ($null -ne $firstChangedUtcUs) {
        $endAnchor = [long]$firstChangedUtcUs
        if ($null -ne $physicalKeyUpUtcUs) {
          $endAnchor = [Math]::Max($endAnchor, [long]$physicalKeyUpUtcUs)
        }
        $endAnchor + 1000000L
      } else { $null }
      $semanticEvents = @(
        if ($null -ne $traceWindowStartUtcUs -and
            $null -ne $traceWindowEndUtcUs) {
          @(
            $playerInputEvents |
              Where-Object {
                (
                  ($isKeyboardInput -and
                   $_.event -eq 'player_keyboard_event' -and
                   $_.action -eq $expectedAction) -or
                  (-not $isKeyboardInput -and
                   $_.event -in @(
                     'progress_slider_start',
                     'progress_slider_committed',
                     'progress_preview_seek_submitted',
                     'progress_exact_seek_confirmed'))
                ) -and
                  [long]$_.utcUs -ge [long]$traceWindowStartUtcUs -and
                  [long]$_.utcUs -le [long]$traceWindowEndUtcUs
              } |
              Sort-Object utcUs
          )
        }
      )
      $pixelActions += [ordered]@{
        index = [int]$action.index
        passed = [bool]$action.passed
        inputUsesNativeQpcAnchor = [bool]$action.inputUsesNativeQpcAnchor
        keyDownQpcUs = [long]$action.keyDownQpcUs
        firstChangedPixelQpcUs = [long]$action.firstChangedPixelQpcUs
        firstChangedUtcTicks = if ($null -ne $sample) { [long]$sample.utcTicks } else { $null }
        firstChangedUtcUs = $firstChangedUtcUs
        nativeDownQpcUs = $nativeDownQpcUs
        nativeDownUtcUs = $nativeDownUtcUs
        nativeUpQpcUs = $nativeUpQpcUs
        nativeUpUtcUs = $nativeUpUtcUs
        playerInputEvents = $semanticEvents
        playerInputEventCount = $semanticEvents.Count
        playerInputEvidence = if ($semanticEvents.Count -gt 0) {
          'player-page-input-events-in-action-window'
        } else { 'unavailable' }
        inputDownUtcUs = $inputDownUtcUs
        physicalKeyUpUtcUs = $physicalKeyUpUtcUs
        traceWindowStartUtcUs = $traceWindowStartUtcUs
        traceWindowEndUtcUs = $traceWindowEndUtcUs
        inputAnchorEvidence = if ($null -ne $nativeDownEvent) {
          'native-qpc-plus-utc'
        } elseif ($null -ne $inputDownUtcUs) {
          'estimated-from-first-pixel'
        } else { 'unavailable' }
        inputDownToFirstChangedPixelMs = [int]$action.inputDownToFirstChangedPixelMs
        maxUnchangedRunMs = [int]$action.maxUnchangedRunMs
        presentedChanges = @(
          @($action.presentedChanges) | ForEach-Object {
            [ordered]@{
              qpcUs = [long]$_.qpcUs
              utcTicks = [long]$_.utcTicks
              utcUs = [long](([long]$_.utcTicks - $epochTicks) / 10L)
              differenceFromPreviousPercent = [double]$_.differenceFromPreviousPercent
              differenceFromBaselinePercent = [double]$_.differenceFromBaselinePercent
              fingerprint = [uint64]$_.fingerprint
            }
          }
        )
      }
    }

    $correlations = @()
    foreach ($trace in $traceEvents) {
      $traceUtcUs = [long]$trace.wallUtcUs
      $candidates = @(
        $pixelActions |
          Where-Object {
            $null -ne $_.traceWindowStartUtcUs -and
              $null -ne $_.traceWindowEndUtcUs -and
              $traceUtcUs -ge [long]$_.traceWindowStartUtcUs -and
              $traceUtcUs -le [long]$_.traceWindowEndUtcUs
          } |
          Sort-Object index
      )
      # 重叠窗口无法仅靠 UTC 判断属于哪一次实体输入；禁止退回最近邻，避免把上一
      # 次或下一次 seek 的阶段伪装成本次动作证据。只有唯一候选才建立因果关联。
      $matched = if ($candidates.Count -eq 1) { $candidates[0] } else { $null }
      $downDeltaMs = if ($null -ne $matched) {
        [Math]::Round(
          ([double]$traceUtcUs - [double]$matched.inputDownUtcUs) / 1000.0,
          3
        )
      } else { $null }
      $firstPixelDeltaMs = if ($null -ne $matched -and
                               $null -ne $matched.firstChangedUtcUs) {
        [Math]::Round(
          ([double]$matched.firstChangedUtcUs - [double]$traceUtcUs) / 1000.0,
          3
        )
      } else { $null }
      $causalOrder = if ($null -eq $matched) {
        'unmatched'
      } elseif ($null -ne $matched.inputDownUtcUs -and
                $traceUtcUs -lt [long]$matched.inputDownUtcUs) {
        'before-input-down'
      } elseif ($null -ne $matched.firstChangedUtcUs -and
                $traceUtcUs -gt [long]$matched.firstChangedUtcUs) {
        'after-first-pixel'
      } else {
        'between-input-and-first-pixel'
      }
      $correlations += [ordered]@{
         trace = $trace.trace
         stage = $trace.stage
         targetMs = $trace.targetMs
         traceWallUtcMs = $trace.wallUtcMs
         traceWallUtcUs = $trace.wallUtcUs
         traceWallUtcPrecision = $trace.wallUtcPrecision
         runtimeSnapshot = $trace.runtimeSnapshot
         matchedPixelActionIndex = if ($null -ne $matched) { $matched.index } else { $null }
        traceAfterInputDownMs = $downDeltaMs
        traceToFirstChangedPixelMs = $firstPixelDeltaMs
        causalOrder = $causalOrder
        withinInputWindow = $null -ne $matched
        candidateActionCount = $candidates.Count
        nextPresentedChangeUtcUs = $null
        traceToNextPresentedChangeMs = $null
        unmatchedReason = if ($null -ne $matched) {
          $null
        } elseif ($candidates.Count -gt 1) {
          'ambiguous-overlapping-pixel-action-windows'
        } else {
          'outside-pixel-action-input-window'
        }
      }
      if ($null -ne $matched) {
        $nextChange = @(
          @($matched.presentedChanges) |
            Where-Object { [long]$_.utcUs -ge $traceUtcUs } |
            Sort-Object utcUs |
            Select-Object -First 1
        )
        if ($nextChange.Count -gt 0) {
          $correlations[-1].nextPresentedChangeUtcUs = [long]$nextChange[0].utcUs
          $correlations[-1].traceToNextPresentedChangeMs = [Math]::Round(
            ([double]$nextChange[0].utcUs - [double]$traceUtcUs) / 1000.0,
            3
          )
        }
      }
    }
    # 以“唯一动作窗口 + 唯一 trace id”为最低条件，生成可审查的分段摘要。
    # 这里不使用最近邻，也不把多个并行 trace 强行压成一条；无法唯一归因时保留
    # ambiguous 状态，让后续 ETW/WPR 或新的独立会话继续定位，而不是产生伪长尾结论。
    $actionTraceSummaries = @()
    foreach ($pixelAction in $pixelActions) {
      $actionIndex = [int]$pixelAction.index
      $windowCorrelations = @(
        $correlations | Where-Object {
          $_.matchedPixelActionIndex -eq $actionIndex -and
            $_.withinInputWindow -eq $true
        }
      )
      $traceIds = @(
        $windowCorrelations |
          ForEach-Object { [string]$_['trace'] } |
          Where-Object { -not [String]::IsNullOrWhiteSpace($_) } |
          Select-Object -Unique
      )
      $traceId = if ($traceIds.Count -eq 1) { [string]$traceIds[0] } else { $null }
      # PowerShell 会把条件分支里的空数组展开为 $null；StrictMode 下随后访问
      # `.Count` 会把“没有 trace 事件”的正常情况误报为 parse-failed。先固定为
      # 真正的空数组，再按唯一 trace 过滤，保证自动化键盘/拖动缺 trace 时仍能落盘。
      $selectedEvents = @()
      if ($null -ne $traceId) {
        $selectedEvents = @(
          $traceEvents |
            Where-Object {
              [string]$_.trace -eq $traceId -and
                $null -ne $pixelAction.traceWindowStartUtcUs -and
                $null -ne $pixelAction.traceWindowEndUtcUs -and
                [long]$_.wallUtcUs -ge [long]$pixelAction.traceWindowStartUtcUs -and
                [long]$_.wallUtcUs -le [long]$pixelAction.traceWindowEndUtcUs
            } |
            Sort-Object wallUtcUs
        )
      }
      $stageTimes = [ordered]@{}
      foreach ($event in $selectedEvents) {
        if (-not $stageTimes.Contains($event.stage)) {
          $stageTimes[$event.stage] = [ordered]@{
            wallUtcUs = $event.wallUtcUs
            wallUtcMs = $event.wallUtcMs
            precision = $event.wallUtcPrecision
            monoUs = $event.monoUs
            waitMs = $event.waitMs
            runtimeSnapshot = $event.runtimeSnapshot
          }
        }
      }
      $traceStart = if ($selectedEvents.Count -gt 0) {
        [long]$selectedEvents[0].wallUtcUs
      } else { $null }
      $commandCompleteEvent = @(
        $selectedEvents | Where-Object {
          $_.stage -in @(
            'smooth_scan_command_complete',
            'keyframe_seek_complete',
            'seek_command_complete'
          )
        } | Select-Object -First 1
      )
      $commandCompleteUtcUs = if ($commandCompleteEvent.Count -gt 0) {
        [long]$commandCompleteEvent[0].wallUtcUs
      } else { $null }
      $status = if ($traceIds.Count -eq 0) {
        'no-trace-in-input-window'
      } elseif ($traceIds.Count -gt 1) {
        'ambiguous-multiple-traces-in-input-window'
      } elseif ($selectedEvents.Count -eq 0) {
        'trace-outside-pixel-window'
      } else {
        'unique-trace'
      }
      $traceLinkEvidence = if ($status -eq 'unique-trace' -and
                               $pixelAction.inputAnchorEvidence -eq 'native-qpc-plus-utc' -and
                               [int]$pixelAction.playerInputEventCount -gt 0) {
        'native-qpc+player-semantic+unique-trace'
      } elseif ($status -eq 'unique-trace' -and
                [int]$pixelAction.playerInputEventCount -gt 0) {
        'player-semantic+unique-trace-estimated-input'
      } elseif ($status -eq 'unique-trace') {
        'unique-trace-without-player-semantic-event'
      } else {
        'unavailable'
      }
      $actionTraceSummaries += [ordered]@{
        actionIndex = $actionIndex
        passed = [bool]$pixelAction.passed
        inputAnchorEvidence = $pixelAction.inputAnchorEvidence
        status = $status
        traceLinkEvidence = $traceLinkEvidence
        traceId = $traceId
        candidateTraceCount = $traceIds.Count
        nativeDownQpcUs = $pixelAction.nativeDownQpcUs
        nativeDownUtcUs = $pixelAction.nativeDownUtcUs
        nativeUpQpcUs = $pixelAction.nativeUpQpcUs
        nativeUpUtcUs = $pixelAction.nativeUpUtcUs
        playerInputEvidence = $pixelAction.playerInputEvidence
        playerInputEventCount = $pixelAction.playerInputEventCount
        playerInputEvents = $pixelAction.playerInputEvents
        presentedChangeCount = @($pixelAction.presentedChanges).Count
        firstPresentedChangeUtcUs = if (@($pixelAction.presentedChanges).Count -gt 0) {
          [long]$pixelAction.presentedChanges[0].utcUs
        } else { $null }
        lastPresentedChangeUtcUs = if (@($pixelAction.presentedChanges).Count -gt 0) {
          [long]$pixelAction.presentedChanges[-1].utcUs
        } else { $null }
        traceStageTimes = $stageTimes
        inputDownToTraceStartMs = if ($null -ne $traceStart -and
                                      $null -ne $pixelAction.inputDownUtcUs) {
          [Math]::Round(
            ([double]$traceStart - [double]$pixelAction.inputDownUtcUs) / 1000.0,
            3
          )
        } else { $null }
        traceStartToFirstChangedPixelMs = if ($null -ne $traceStart -and
                                             $null -ne $pixelAction.firstChangedUtcUs) {
          [Math]::Round(
            ([double]$pixelAction.firstChangedUtcUs - [double]$traceStart) / 1000.0,
            3
          )
        } else { $null }
        commandCompleteToFirstChangedPixelMs = if (
            $null -ne $commandCompleteUtcUs -and
            $null -ne $pixelAction.firstChangedUtcUs) {
          [Math]::Round(
            ([double]$pixelAction.firstChangedUtcUs - [double]$commandCompleteUtcUs) / 1000.0,
            3
          )
        } else { $null }
      }
    }
    $correlation.traceEvents = @($traceEvents)
    $correlation.pixelActions = @($pixelActions)
    $correlation.playerInputEvents = @($playerInputEvents)
    $correlation.correlations = @($correlations)
    $correlation.actionTraceSummaries = @($actionTraceSummaries)
    $correlation.status = if ($traceEvents.Count -gt 0 -and $pixelActions.Count -gt 0) {
      if (@($pixelActions | Where-Object { $_.inputAnchorEvidence -eq 'native-qpc-plus-utc' }).Count -gt 0) {
        'available-native-qpc-utc-window'
      } else {
        'available-estimated-utc-window'
      }
    } else {
      'unavailable-no-shared-events'
    }
  } catch {
    # 关联失败不能改写像素门禁结果；只保留异常类型和脚本行号，避免把私有路径或
    # 媒体内容写进 QA 报告，同时让三方字段新增后的 parse-failed 可定位而非静默吞掉。
    $correlation.status = 'unavailable-parse-failed'
    $correlation.failureCategory = 'trace-correlation-parse-failed'
    $correlation.failureType = $_.Exception.GetType().Name
    $correlation.failureLine = [int]$_.InvocationInfo.ScriptLineNumber
    $correlation.failureMessage = ([string]$_.Exception.Message) -replace '[A-Za-z]:\\[^ ]+', '<path>'
  }
  [System.IO.File]::WriteAllText(
    $OutputPath,
    ($correlation | ConvertTo-Json -Depth 20),
    [System.Text.UTF8Encoding]::new($false)
  )
}

function Convert-QaShortcutToVirtualKey {
  param([string]$Shortcut)
  if ($Shortcut -match '\+') {
    throw "真实 PlayerPage QA 暂不注入带修饰键的快捷键：$Shortcut"
  }
  $base = ($Shortcut -split '\+')[-1].Trim().ToUpperInvariant()
  switch ($base) {
    'ARROWLEFT' { return 0x25 }
    'ARROWRIGHT' { return 0x27 }
    'ARROWUP' { return 0x26 }
    'ARROWDOWN' { return 0x28 }
    'J' { return 0x4A }
    'L' { return 0x4C }
    default { throw "真实 PlayerPage QA 不支持当前快捷键的无修饰 VK 注入：$base" }
  }
}

$previousEnvironment = @{}
foreach ($name in @(
  'LOCAL_TAG_PLAYER_PIXEL_SAMPLE',
  'LOCAL_TAG_PLAYER_PIXEL_OUTPUT',
  'LOCAL_TAG_PLAYER_PIXEL_WINDOW_TITLE',
  'LOCAL_TAG_PLAYER_PIXEL_SAMPLES',
  'LOCAL_TAG_PLAYER_PIXEL_P95_BUDGET_MS',
  'LOCAL_TAG_PLAYER_PIXEL_WINDOW_WIDTH',
  'LOCAL_TAG_PLAYER_PIXEL_WINDOW_HEIGHT',
  'LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA',
  'LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA',
  'LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA',
  'LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA',
  'LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA',
  'LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION',
  'LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_HOLD_MODE',
  'LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_QA',
  'LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_ACTION',
  'LOCAL_TAG_PLAYER_QA_PROGRESS_DRAG_SEEK_MODE',
  'LOCAL_TAG_PLAYER_QA_DISABLE_ADAPTIVE_TEXTURE',
  'LOCAL_TAG_PLAYER_QA_FORCE_SOFTWARE_DECODE',
  'LOCAL_TAG_PLAYER_QA_AUTO_RETRY_SOFTWARE_DECODE'
)) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$testProcess = $null
try {
  $env:LOCAL_TAG_PLAYER_PIXEL_SAMPLE = $Sample
  $env:LOCAL_TAG_PLAYER_PIXEL_OUTPUT = $Output
  $env:LOCAL_TAG_PLAYER_PIXEL_WINDOW_TITLE = $windowTitle
  $env:LOCAL_TAG_PLAYER_PIXEL_SAMPLES = "$Samples"
  $qaWindowWidth = if ($realPlayerPageAction) {
    $PlayerPageInitialWindowWidth
  } else {
    $InitialWindowWidth
  }
  $qaWindowHeight = if ($realPlayerPageAction) {
    $PlayerPageInitialWindowHeight
  } else {
    $InitialWindowHeight
  }
  $env:LOCAL_TAG_PLAYER_PIXEL_WINDOW_WIDTH = "$qaWindowWidth"
  $env:LOCAL_TAG_PLAYER_PIXEL_WINDOW_HEIGHT = "$qaWindowHeight"
  if ($P95BudgetMs -gt 0) {
    $env:LOCAL_TAG_PLAYER_PIXEL_P95_BUDGET_MS = "$P95BudgetMs"
  } else {
    Remove-Item Env:LOCAL_TAG_PLAYER_PIXEL_P95_BUDGET_MS -ErrorAction SilentlyContinue
  }

  if (-not $DebugExecutable) {
    $DebugExecutable = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Debug\local_tag_player.exe'
  }
  $DebugExecutable = [System.IO.Path]::GetFullPath($DebugExecutable)
  if (-not (Test-Path -LiteralPath $DebugExecutable -PathType Leaf)) {
    throw "缺少刚构建的 Windows Debug 可执行程序：$DebugExecutable"
  }
  if ($realPlayerPageAction) {
    $env:LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA = '1'
    $env:LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA = '1'
    $env:LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA = '1'
    if ($manualKeyboardAction) {
      # 原生 runner 仅在 Debug QA 内记录匿名动作/QPC；真实按键由操作者在窗口前台按下。
      $env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA = '1'
      $env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION = if ($Action -in @('manualBackward', 'manualLongBackward')) {
        'backward'
      } else {
        'forward'
      }
      $env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_HOLD_MODE = if ($manualLongKeyboardAction) {
        'long'
      } else {
        'short'
      }
    } else {
      Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA -ErrorAction SilentlyContinue
      Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION -ErrorAction SilentlyContinue
      Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_HOLD_MODE -ErrorAction SilentlyContinue
    }
    if ($HoldMilliseconds -gt 0 -and $Action -in @('forward', 'backward')) {
      # 仅让隔离 QA 页在首个自动化方向 Down 后恢复播放；正式页面和实体模式不读取。
      $env:LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_QA = '1'
      $env:LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_ACTION = if ($Action -eq 'backward') {
        'backward'
      } else {
        'forward'
      }
    } else {
      Remove-Item Env:LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_QA -ErrorAction SilentlyContinue
      Remove-Item Env:LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_ACTION -ErrorAction SilentlyContinue
    }
    $env:LOCAL_TAG_PLAYER_QA_PROGRESS_DRAG_SEEK_MODE = $ProgressDragSeekMode
    if ($DisableAdaptiveTextureSizing) {
      $env:LOCAL_TAG_PLAYER_QA_DISABLE_ADAPTIVE_TEXTURE = '1'
    } else {
      Remove-Item Env:LOCAL_TAG_PLAYER_QA_DISABLE_ADAPTIVE_TEXTURE -ErrorAction SilentlyContinue
    }
    if ($ForceSoftwareDecode) {
      $env:LOCAL_TAG_PLAYER_QA_FORCE_SOFTWARE_DECODE = '1'
    } else {
      Remove-Item Env:LOCAL_TAG_PLAYER_QA_FORCE_SOFTWARE_DECODE -ErrorAction SilentlyContinue
    }
    if ($AutoRetrySoftwareDecode) {
      $env:LOCAL_TAG_PLAYER_QA_AUTO_RETRY_SOFTWARE_DECODE = '1'
    } else {
      Remove-Item Env:LOCAL_TAG_PLAYER_QA_AUTO_RETRY_SOFTWARE_DECODE -ErrorAction SilentlyContinue
    }
    Remove-Item Env:LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA -ErrorAction SilentlyContinue
  } else {
    $env:LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA = '1'
    Remove-Item Env:LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_HOLD_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_QA -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_ACTION -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QA_PROGRESS_DRAG_SEEK_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QA_DISABLE_ADAPTIVE_TEXTURE -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QA_FORCE_SOFTWARE_DECODE -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QA_AUTO_RETRY_SOFTWARE_DECODE -ErrorAction SilentlyContinue
  }
  # 必须保留可见窗口；这是实际 Debug 程序的 DWM 合成与真实 Win32 输入，不是测试绑定。
  $testProcess = Start-Process -FilePath $DebugExecutable -PassThru `
    -RedirectStandardOutput $logPath -RedirectStandardError $errorPath
  $readyDeadline = [DateTime]::UtcNow.AddSeconds(90)
  while (-not (Test-Path -LiteralPath $readyPath) -and
         -not (Test-Path -LiteralPath $qaFailurePath) -and
         -not $testProcess.HasExited -and
         [DateTime]::UtcNow -lt $readyDeadline) {
    Start-Sleep -Milliseconds 100
  }
  if (Test-Path -LiteralPath $qaFailurePath) {
    throw (Get-Content -LiteralPath $qaFailurePath -Raw)
  }
  if ($testProcess.HasExited) {
    throw "实际 Debug Texture QA 在写出握手文件前退出，exit code=$($testProcess.ExitCode)。"
  }
  if (-not (Test-Path -LiteralPath $readyPath)) {
    throw '实际 Debug Texture QA 未在 90 秒内写出桌面探针握手文件。'
  }
  $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
  if ($ready.backend -ne 'media-kit-flutter-texture' -or
      $ready.state -ne 'paused-static-baseline-ready') {
    throw '桌面探针握手未确认正式 MediaKit Texture 的静止基线。'
  }
  if ($realPlayerPageAction -and $ready.surface -ne 'product-player-page') {
    throw '真实 PlayerPage 动作缺少产品页面表面握手，拒绝退化到专用 Texture 页。'
  }
  if ($Action -eq 'progressDrag' -and
      $ready.progressDragSeekMode -ne $ProgressDragSeekMode) {
    throw '真实 PlayerPage 拖动 QA 的定位策略握手不匹配，拒绝将默认精确结果与两阶段实验混算。'
  }
  if ($Action -in @('playerFullscreen', 'forward', 'backward', 'manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward') -and -not $ready.focusReady) {
    throw '真实 PlayerPage 键盘动作缺少 FocusNode 就绪握手，拒绝把未送达的 scan-code 当作 seek 性能。'
  }
  $configuredKeyboardVirtualKey = 0
  if ($realPlayerPageAction -and $Action -in @('forward', 'backward')) {
    $configuredShortcut = if ($Action -eq 'backward') {
      [string]$ready.seekBackwardShortcut
    } else {
      [string]$ready.seekForwardShortcut
    }
    if ([string]::IsNullOrWhiteSpace($configuredShortcut)) {
      throw '真实 PlayerPage QA 握手缺少当前快捷键，拒绝用默认 J/L 冒充用户输入。'
    }
    $configuredKeyboardVirtualKey = Convert-QaShortcutToVirtualKey $configuredShortcut
  }
  if ($manualKeyboardAction -and
      $ready.manualKeyboardHoldMode -ne $(if ($manualLongKeyboardAction) { 'long' } else { 'short' })) {
    throw '实体键盘 QA 的短按/长按握手不匹配，拒绝混淆两类体验合同。'
  }
  # FocusNode 在首次布局、按钮 autofocus 与窗口激活之间会短暂迁移；实际输入前由
  # Win32 探针以 GetForegroundWindow 再次核验，不能用这个 Flutter 内部瞬时状态拒绝
  # 已经就绪的正式 Texture 会话。
  try {
    if ($Action -eq 'progressDrag') {
      # Slider 的 PointerUp 匿名回执只用于证明命中正式完整 Slider；它不进入媒体/画面
      # 证据，缺失时由探针以语义超时失败，绝不能仅凭底部像素变化放行。
      & (Join-Path $PSScriptRoot 'invoke_player_desktop_pixel_probe.ps1') `
        -WindowTitle $ready.windowTitle -ProcessId ([int]$ready.testProcessId) `
        -Action $Action -Samples $Samples -FrameRate $FrameRate `
        -MinimumEffectiveCaptureFps $MinimumEffectiveCaptureFps `
        -PixelChangeThresholdPercent $PixelChangeThresholdPercent `
        -SettleMilliseconds $SettleMilliseconds -Output $probeOutput `
        -ExpectedInputEvidencePath (Join-Path $Output 'player-input-events.jsonl')
    } elseif ($manualKeyboardAction) {
      # 此分支不执行 SendInput：探针已完成静态基线后会等待一次实体 J/L。原生 FLUTTERVIEW
      # 观察器提供与 DWM 采样一致的 QPC 锚点，页面回执仍必须证明快捷键实际进入 PlayerPage。
      & (Join-Path $PSScriptRoot 'invoke_player_desktop_pixel_probe.ps1') `
        -WindowTitle $ready.windowTitle -ProcessId ([int]$ready.testProcessId) `
        -Action $Action -Samples $Samples -FrameRate $FrameRate `
        -MinimumEffectiveCaptureFps $MinimumEffectiveCaptureFps `
        -PixelChangeThresholdPercent $PixelChangeThresholdPercent `
        -SettleMilliseconds $SettleMilliseconds -Output $probeOutput `
        -ExpectedInputEvidencePath (Join-Path $Output 'player-input-events.jsonl') `
        -NativeKeyboardEvidencePath (Join-Path $Output 'native-keyboard-qpc-events.jsonl') `
        -ManualInputTimeoutMilliseconds $ManualInputTimeoutMilliseconds `
        -ManualLongHoldMinimumMilliseconds $ManualLongHoldMinimumMilliseconds
    } else {
      $preparePlayerKeyboardFocus = if ($realPlayerPageAction) {
        $true
      } else {
        $false
      }
      # 先解析为独立变量再传给 C# 探针。内嵌 if 表达式夹在反引号续行和注释
      # 之间时，PowerShell 可能把参数丢出调用；一旦丢失，真实 PlayerPage 的
      # 像素变化会被错误地当成已命中快捷键。语义回执路径必须显式存在。
      $playerInputEvidencePath = if ($realPlayerPageAction) {
        Join-Path $Output 'player-input-events.jsonl'
      } else {
        ''
      }
      & (Join-Path $PSScriptRoot 'invoke_player_desktop_pixel_probe.ps1') `
        -WindowTitle $ready.windowTitle -ProcessId ([int]$ready.testProcessId) `
        -Action $Action -Samples $Samples -FrameRate $FrameRate `
        -MinimumEffectiveCaptureFps $MinimumEffectiveCaptureFps `
        -PixelChangeThresholdPercent $PixelChangeThresholdPercent `
        -SettleMilliseconds $SettleMilliseconds -Output $probeOutput `
        -HoldMilliseconds $HoldMilliseconds `
        -VirtualKey $configuredKeyboardVirtualKey `
        -KeyboardInjectionMode 'scanCode' `
        -PreparePlayerKeyboardFocus:$preparePlayerKeyboardFocus `
        -ExpectedInputEvidencePath $playerInputEvidencePath
    }
    # 被调用的是 PowerShell 脚本而非 native exe；严格模式下 $LASTEXITCODE 可能根本
    # 不存在。必须使用调用状态，不能把已生成的成功摘要误写成 probe failure。
    if (-not $?) { throw '桌面像素探针失败。' }
  } catch {
    [System.IO.File]::WriteAllText($failurePath, $_.Exception.Message, [System.Text.UTF8Encoding]::new($false))
  }
  if ($Action -eq 'progressDrag' -and
      $ProgressDragSeekMode -eq 'fastPreviewThenExact') {
    # DWM 探针会在首个实际画面后立即返回；快速关键帧请求与最终精确定位仍在同一
    # 异步会话中收敛。必须等待两个匿名阶段回执，不能把偶然较快的精确 seek 当实验成功。
    $inputEvidencePath = Join-Path $Output 'player-input-events.jsonl'
    $experimentDeadline = [DateTime]::UtcNow.AddSeconds(4)
    $experimentEvents = @()
    do {
      if (Test-Path -LiteralPath $inputEvidencePath) {
        $experimentEvents = @(
          Get-Content -LiteralPath $inputEvidencePath | ForEach-Object {
            try { ($_.Trim() | ConvertFrom-Json).event } catch { $null }
          } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
      }
      if (($experimentEvents -contains 'progress_preview_seek_submitted') -and
          ($experimentEvents -contains 'progress_exact_seek_confirmed')) {
        break
      }
      Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $experimentDeadline)
    if (-not ($experimentEvents -contains 'progress_preview_seek_submitted') -or
        -not ($experimentEvents -contains 'progress_exact_seek_confirmed')) {
      throw '两阶段拖动缺少快速请求或最终精确确认回执，拒绝生成首帧 p95。'
    }
  }
  $summaryPath = Join-Path $probeOutput 'desktop-pixel-summary.json'
  if (-not (Test-Path -LiteralPath $summaryPath)) {
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
      $probeFailure = (Get-Content -LiteralPath $failurePath -Raw).Trim()
      if (-not [String]::IsNullOrWhiteSpace($probeFailure)) {
        throw "桌面像素探针失败：$probeFailure"
      }
    }
    throw '桌面像素探针未生成摘要，且没有可读的失败分类。'
  }
  $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
  Write-DesktopPixelTraceCorrelation `
    -LogPath $logPath `
    -PixelReportPath (Join-Path $probeOutput 'desktop-pixel-report.json') `
    -NativeKeyboardEvidencePath (Join-Path $Output 'native-keyboard-qpc-events.jsonl') `
    -PlayerInputEvidencePath (Join-Path $Output 'player-input-events.jsonl') `
    -OutputPath (Join-Path $Output 'desktop-pixel-trace-correlation.json')
  if (-not $summary.captureRatePassed -or
      [int]$summary.successfulSamples -ne $Samples -or
      [int]$summary.timedOutSamples -ne 0) {
    throw "桌面像素门禁未满足采样合同：成功 $($summary.successfulSamples)/$Samples，超时 $($summary.timedOutSamples)，有效采样=$($summary.captureRatePassed)。"
  }
  if ($Action -notin @('fullscreen', 'playerFullscreen') -and
      -not (@($summary.actionEvidence) -contains 'desktop-composited-pixel-change')) {
    throw '输入门禁没有生成桌面合成像素证据。'
  }
  if ($Action -in @('fullscreen', 'playerFullscreen')) {
    if (-not (@($summary.actionEvidence) -contains 'window-geometry-change')) {
      throw '全屏门禁没有生成窗口几何变化证据。'
    }
    $rendererEventsPath = Join-Path $Output 'renderer-events.jsonl'
    $rendererDeadline = [DateTime]::UtcNow.AddSeconds(4)
    do {
      if ((Test-Path -LiteralPath $rendererEventsPath) -and
          (Get-Content -LiteralPath $rendererEventsPath -Raw) -match 'fullscreen_settled') {
        break
      }
      Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $rendererDeadline)
    if (-not (Test-Path -LiteralPath $rendererEventsPath) -or
        -not ((Get-Content -LiteralPath $rendererEventsPath -Raw) -match 'fullscreen_settled')) {
      throw '全屏窗口已变化，但 QA 未写出稳定后的 Texture 诊断事件。'
    }
  }
  Write-Output "PLAYER_DESKTOP_PIXEL_GATE $($summary | ConvertTo-Json -Compress)"
} finally {
  if ($null -ne $testProcess -and -not $testProcess.HasExited) {
    # 先让 Debug QA await MediaKit/ANGLE/D3D11 dispose；强杀会遗留 GPU 表面，下一独立
    # 4K 会话可能在初始化中崩溃。只在协议超时后终止本脚本刚启动的 PID。
    [System.IO.File]::WriteAllText(
      $shutdownRequestPath,
      'dispose-before-exit',
      [System.Text.UTF8Encoding]::new($false)
    )
    $shutdownDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $shutdownDeadline) {
      Start-Sleep -Milliseconds 100
    }
    if (-not $testProcess.HasExited) {
      Stop-Process -Id $testProcess.Id -ErrorAction SilentlyContinue
    }
  }
  foreach ($entry in $previousEnvironment.GetEnumerator()) {
    if ($null -eq $entry.Value) {
      Remove-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue
    } else {
      Set-Item "Env:$($entry.Key)" $entry.Value
    }
  }
}
