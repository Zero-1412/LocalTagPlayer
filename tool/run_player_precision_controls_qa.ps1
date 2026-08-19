<#
.SYNOPSIS
  在真实 PlayerPage/MediaKit Texture Debug 会话中验收逐帧、A/B loop 与外挂字幕。

.DESCRIPTION
  该脚本不发送桌面输入，也不把 Flutter 测试泵当作呈现证据。它启动隔离 Debug QA
  页面，让页面通过正式 PlayerService/NativePlayer 命令完成控制，再读取匿名 JSONL
  阶段与资源释放生命周期。输出不包含媒体路径、标题、videoId 或字幕内容。
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
  [ValidateRange(30, 180)]
  [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'precision controls QA 只支持 Windows。' }
if (-not (Test-Path -LiteralPath $Sample -PathType Leaf)) {
  throw 'precision controls QA 样本不存在。'
}
if (-not $Output) {
  $Output = Join-Path $PSScriptRoot ("..\.local\qa\precision-controls-" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw "拒绝覆盖既有 precision controls QA 证据目录：$Output"
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

if (-not $DebugExecutable) {
  $DebugExecutable = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Debug\local_tag_player.exe'
}
$DebugExecutable = [System.IO.Path]::GetFullPath($DebugExecutable)
if (-not (Test-Path -LiteralPath $DebugExecutable -PathType Leaf)) {
  throw '缺少刚构建的 Windows Debug 可执行程序。'
}

$readyPath = Join-Path $Output 'ready.json'
$precisionPath = Join-Path $Output 'precision-controls.jsonl'
$shutdownPath = Join-Path $Output 'shutdown.request'
$lifecyclePath = Join-Path $Output 'qa-lifecycle.jsonl'
$summaryPath = Join-Path $Output 'precision-controls-summary.json'
$stdoutPath = Join-Path $Output 'debug-qa.stdout.log'
$stderrPath = Join-Path $Output 'debug-qa.stderr.log'
$windowTitle = 'LocalTagPlayer Precision Controls QA'
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

function Get-PrecisionEvents {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $events = @()
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $events += ($line | ConvertFrom-Json) } catch { }
  }
  return @($events)
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
  $readyDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while (-not (Test-Path -LiteralPath $readyPath) -and
         -not $testProcess.HasExited -and
         [DateTime]::UtcNow -lt $readyDeadline) {
    Start-Sleep -Milliseconds 100
  }
  if ($testProcess.HasExited) { throw 'Debug QA 在 ready 握手前退出。' }
  if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Debug QA 未在时限内写出 ready 握手。' }
  $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
  if ($ready.surface -ne 'product-player-page' -or
      $ready.backend -ne 'media-kit-flutter-texture' -or
      -not [bool]$ready.precisionControlsQa) {
    throw 'ready 握手未确认正式 PlayerPage precision QA。'
  }

  $precisionDeadline = [DateTime]::UtcNow.AddSeconds(30)
  while (-not (Test-Path -LiteralPath $precisionPath) -and
         -not $testProcess.HasExited -and
         [DateTime]::UtcNow -lt $precisionDeadline) {
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path -LiteralPath $precisionPath)) {
    throw 'precision controls QA 未写出匿名阶段证据。'
  }
  $events = @(Get-PrecisionEvents $precisionPath)
  $requiredStages = @(
    'frame_step_complete',
    'ab_loop_a',
    'ab_loop_b',
    'ab_loop_cycle_complete',
    'ab_loop_clear',
    'external_subtitle_complete'
  )
  $precisionCompleteDeadline = [DateTime]::UtcNow.AddSeconds(30)
  $requiredStagesComplete = $false
  do {
    $precisionLines = @(Get-Content -LiteralPath $precisionPath)
    $missingRequiredStage = @($requiredStages | Where-Object {
        $stage = $_
        @($precisionLines | Where-Object {
            ($_ -like ('*"stage":"' + $stage + '"*')) -and
            ($_ -like '*"success":true*')
          }).Count -eq 0
      })
    $requiredStagesComplete = $missingRequiredStage.Count -eq 0
    if ($requiredStagesComplete) { break }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $precisionCompleteDeadline)
  if (-not $requiredStagesComplete) {
    throw 'precision controls QA 未在时限内完成所有必需阶段。'
  }
  $events = @(Get-PrecisionEvents $precisionPath)
  foreach ($stage in $requiredStages) {
    $successfulLine = @(
      Get-Content -LiteralPath $precisionPath |
        Where-Object {
          $_ -like ('*"stage":"' + $stage + '"*') -and
          $_ -like '*"success":true*'
        }
    )
    if ($successfulLine.Count -eq 0) {
      throw "precision controls QA 阶段失败：$stage"
    }
  }
  if (-not (Test-Path -LiteralPath $lifecyclePath -PathType Leaf) -or
      -not ((Get-Content -LiteralPath $lifecyclePath -Raw) -match 'precision_controls_qa_complete')) {
    throw 'precision controls QA 缺少完成生命周期。'
  }

  [System.IO.File]::WriteAllText(
    $shutdownPath,
    'dispose-before-exit',
    [System.Text.UTF8Encoding]::new($false)
  )
  $releaseDeadline = [DateTime]::UtcNow.AddSeconds(20)
  while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $releaseDeadline) {
    Start-Sleep -Milliseconds 100
  }
  $lifecycle = if (Test-Path -LiteralPath $lifecyclePath) {
    @(Get-Content -LiteralPath $lifecyclePath | ForEach-Object {
      try { (($_ | ConvertFrom-Json).event).ToString() } catch { 'lifecycle_line_unreadable' }
    })
  } else { @() }
  $summary = [ordered]@{
    evidence = 'real-player-page-native-player-precision-controls'
    surface = 'product-player-page'
    backend = 'media-kit-flutter-texture'
    requiredStages = $requiredStages
    stages = @($events | ForEach-Object {
      $successProperty = $_.PSObject.Properties['success']
      $frameEvidenceProperty = $_.PSObject.Properties['frameEvidence']
      $positionProperty = $_.PSObject.Properties['positionMs']
      $trackListProperty = $_.PSObject.Properties['trackListObserved']
      [ordered]@{
        stage = [string]$_.stage
        success = if ($null -eq $successProperty) { $null } else { [bool]$successProperty.Value }
        frameEvidence = if ($null -eq $frameEvidenceProperty) { $null } else { [string]$frameEvidenceProperty.Value }
        positionMs = if ($null -eq $positionProperty) { $null } else { [int]$positionProperty.Value }
        trackListObserved = if ($null -eq $trackListProperty) { $null } else { [bool]$trackListProperty.Value }
      }
    })
    resourceReleaseConfirmed = $lifecycle -contains 'player_resources_released'
    lifecycle = $lifecycle
    pathOrMediaContentRetained = $false
  }
  [System.IO.File]::WriteAllText(
    $summaryPath,
    ($summary | ConvertTo-Json -Depth 10),
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Output ("PLAYER_PRECISION_CONTROLS_QA " + ($summary | ConvertTo-Json -Compress))
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
