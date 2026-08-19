<##
.SYNOPSIS
  校验正式 PlayerPage precision controls 的命令/资源与 DWM 可见性证据。

.DESCRIPTION
  该工具只读取 Debug QA 目录，不启动播放器、不读取媒体路径、不把命令完成或帧号
  回执升级为真实桌面呈现。每个控制分别输出 commandResource、visible 和 overall，
  严格使用 pass、fail、unknown；缺少 DWM 摘要、采样率或阶段字段保持 unknown。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string[]]$EvidenceRoot,

  [string]$Output = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$controls = [ordered]@{
  frameStep = [ordered]@{
    commandStages = @('frame_step_complete', 'frame_step_backward_complete')
    dwmName = 'frameStep'
  }
  playbackRate = [ordered]@{
    # 临时倍速必须同时有设置读回和恢复原值的成功阶段。
    commandStages = @('playback_rate_complete', 'playback_rate_restored')
    dwmName = 'playbackRate'
  }
  abLoop = [ordered]@{
    commandStages = @(
      'ab_loop_a',
      'ab_loop_b',
      'ab_loop_cycle_complete',
      'ab_loop_clear'
    )
    dwmName = 'abLoop'
  }
  externalSubtitle = [ordered]@{
    commandStages = @('external_subtitle_complete')
    dwmName = 'externalSubtitle'
  }
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-JsonLines {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $values = @()
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $values += ($line | ConvertFrom-Json) } catch { }
  }
  return @($values)
}

function Get-ObjectProperty {
  param(
    [object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -ne $property) { return $property.Value }
  if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
    return $Object[$Name]
  }
  return $null
}

function New-Status {
  param(
    [ValidateSet('pass', 'fail', 'unknown')]
    [string]$Status,
    [object]$Value,
    [string]$Reason
  )
  return [ordered]@{
    status = $Status
    value = $Value
    reason = $Reason
  }
}

function Merge-Status {
  param([object[]]$Values)
  $statuses = @($Values | ForEach-Object { [string](Get-ObjectProperty $_ 'status') })
  if ($statuses -contains 'fail') { return 'fail' }
  if ($statuses.Count -eq 0 -or $statuses -contains 'unknown') { return 'unknown' }
  return 'pass'
}

function Get-CommandStageStatus {
  param(
    [object[]]$Events,
    [string[]]$Stages
  )
  $stageResults = @()
  foreach ($stage in $Stages) {
    $matches = @($Events | Where-Object { [string]$_.stage -eq $stage })
    if ($matches.Count -eq 0) {
      $stageResults += New-Status 'unknown' $null "缺少命令阶段：$stage。"
      continue
    }
    $successValues = @($matches | ForEach-Object {
      $success = Get-ObjectProperty $_ 'success'
      if ($null -eq $success) { 'unknown' } elseif ([bool]$success) { 'pass' } else { 'fail' }
    })
    $stageStatus = if ($successValues -contains 'fail') { 'fail' }
      elseif ($successValues -contains 'unknown') { 'unknown' }
      else { 'pass' }
    $stageResults += New-Status $stageStatus $successValues "命令阶段 $stage。"
  }
  return [ordered]@{
    status = Merge-Status $stageResults
    stages = $stageResults
    reason = '命令完成与属性/状态读回只属于 command/resource QA。'
  }
}

function Get-ResourceReleaseStatus {
  param([object[]]$LifecycleEvents)
  $events = @($LifecycleEvents | ForEach-Object { [string]$_ })
  if ($events -contains 'player_release_failed') {
    return New-Status 'fail' $false '资源释放明确失败。'
  }
  if ($events -contains 'player_resources_released') {
    return New-Status 'pass' $true '正式 PlayerService 资源释放事件已记录。'
  }
  return New-Status 'unknown' $null '缺少资源释放生命周期事件。'
}

function Get-VisibleStatus {
  param(
    [object]$DwmSummary,
    [string]$DwmName
  )
  if ($null -eq $DwmSummary) {
    return [ordered]@{
      status = 'unknown'
      stageStatus = 'unknown'
      captureStatus = 'unknown'
      evidenceKind = $null
      value = $null
      reason = '缺少 precision-controls-dwm-summary.json；命令证据不能替代 DWM 可见性。'
    }
  }

  $stageMetrics = Get-ObjectProperty $DwmSummary 'stageMetrics'
  $stage = Get-ObjectProperty $stageMetrics $DwmName
  $stageStatus = [string](Get-ObjectProperty $stage 'status')
  if ($stageStatus -notin @('pass', 'fail', 'unknown')) { $stageStatus = 'unknown' }
  $capture = Get-ObjectProperty $DwmSummary 'capture'
  $captureStatus = [string](Get-ObjectProperty $capture 'captureRateStatus')
  if ($captureStatus -notin @('pass', 'fail', 'unknown')) { $captureStatus = 'unknown' }
  $evidenceKind = [string](Get-ObjectProperty $capture 'firstDwmEvidenceKind')
  if ($evidenceKind -ne 'desktop-composited-pixel-change') { $evidenceKind = '' }

  $visibleStatus = if ($evidenceKind -ne 'desktop-composited-pixel-change') {
    'unknown'
  } elseif ($stageStatus -eq 'fail' -or $captureStatus -eq 'fail') {
    'fail'
  } elseif ($stageStatus -eq 'unknown' -or $captureStatus -eq 'unknown') {
    'unknown'
  } else {
    'pass'
  }
  return [ordered]@{
    status = $visibleStatus
    stageStatus = $stageStatus
    captureStatus = $captureStatus
    evidenceKind = if ($evidenceKind) { $evidenceKind } else { $null }
    value = [ordered]@{
      presentedChangeCount = Get-ObjectProperty $stage 'presentedChangeCount'
      effectiveFps = Get-ObjectProperty $capture 'effectiveFps'
      minimumFps = Get-ObjectProperty $capture 'minimumFps'
      maxDifferencePercent = Get-ObjectProperty $stage 'maxDifferencePercent'
    }
    reason = '只有真实 desktop-composited-pixel-change 且采样门禁可判定时才能写 visible pass。'
  }
}

function Get-SessionResult {
  param([Parameter(Mandatory = $true)][string]$Root)
  $commandEvents = Get-JsonLines (Join-Path $Root 'precision-controls.jsonl')
  $lifecycle = @(Get-JsonLines (Join-Path $Root 'qa-lifecycle.jsonl') | ForEach-Object {
    [string](Get-ObjectProperty $_ 'event')
  })
  $dwmSummary = Read-JsonFile (Join-Path $Root 'precision-controls-dwm-summary.json')
  $controlResults = [ordered]@{}
  foreach ($entry in $controls.GetEnumerator()) {
    $command = Get-CommandStageStatus -Events $commandEvents -Stages $entry.Value.commandStages
    $release = Get-ResourceReleaseStatus -LifecycleEvents $lifecycle
    $commandResourceStatus = if ($command.status -eq 'fail' -or $release.status -eq 'fail') {
      'fail'
    } elseif ($command.status -eq 'unknown' -or $release.status -eq 'unknown') {
      'unknown'
    } else {
      'pass'
    }
    $visible = Get-VisibleStatus -DwmSummary $dwmSummary -DwmName $entry.Value.dwmName
    $overall = if ($commandResourceStatus -eq 'fail' -or $visible.status -eq 'fail') {
      'fail'
    } elseif ($commandResourceStatus -eq 'unknown' -or $visible.status -eq 'unknown') {
      'unknown'
    } else {
      'pass'
    }
    $controlResults[$entry.Key] = [ordered]@{
      overall = $overall
      commandResource = [ordered]@{
        status = $commandResourceStatus
        command = $command
        resourceRelease = $release
      }
      visible = $visible
    }
  }
  return [ordered]@{
    rootExists = Test-Path -LiteralPath $Root -PathType Container
    commandEvents = $commandEvents.Count
    hasDwmSummary = $null -ne $dwmSummary
    controls = $controlResults
  }
}

$sessions = @()
foreach ($root in $EvidenceRoot) {
  $fullRoot = [System.IO.Path]::GetFullPath($root)
  $sessions += Get-SessionResult $fullRoot
}

$controlsResult = [ordered]@{}
foreach ($entry in $controls.GetEnumerator()) {
  $sessionControls = @($sessions | ForEach-Object {
    Get-ObjectProperty (Get-ObjectProperty $_ 'controls') $entry.Key
  })
  $commandResourceStatuses = @($sessionControls | ForEach-Object {
    Get-ObjectProperty (Get-ObjectProperty $_ 'commandResource') 'status'
  })
  $visibleStatuses = @($sessionControls | ForEach-Object {
    Get-ObjectProperty (Get-ObjectProperty $_ 'visible') 'status'
  })
  $overallStatuses = @($sessionControls | ForEach-Object {
    Get-ObjectProperty $_ 'overall'
  })
  $controlsResult[$entry.Key] = [ordered]@{
    overall = if ($overallStatuses -contains 'fail') { 'fail' }
      elseif ($overallStatuses.Count -eq 0 -or $overallStatuses -contains 'unknown') { 'unknown' }
      else { 'pass' }
    commandResource = [ordered]@{
      status = if ($commandResourceStatuses -contains 'fail') { 'fail' }
        elseif ($commandResourceStatuses.Count -eq 0 -or $commandResourceStatuses -contains 'unknown') { 'unknown' }
        else { 'pass' }
      sessionStatuses = $commandResourceStatuses
    }
    visible = [ordered]@{
      status = if ($visibleStatuses -contains 'fail') { 'fail' }
        elseif ($visibleStatuses.Count -eq 0 -or $visibleStatuses -contains 'unknown') { 'unknown' }
        else { 'pass' }
      sessionStatuses = $visibleStatuses
    }
  }
}

$controlStatuses = @($controlsResult.Values | ForEach-Object { [string]$_.overall })
$overall = if ($controlStatuses -contains 'fail') { 'fail' }
  elseif ($controlStatuses.Count -eq 0 -or $controlStatuses -contains 'unknown') { 'unknown' }
  else { 'pass' }
$result = [ordered]@{
  schemaVersion = 1
  evidence = 'p1-player-page-precision-command-resource-and-dwm'
  overall = $overall
  evidenceDirectories = $sessions.Count
  controls = $controlsResult
  sessions = @($sessions)
}

if (-not $Output) {
  $Output = Join-Path ([System.IO.Path]::GetFullPath('.local\qa')) 'p1-precision-evidence.json'
}
$outputDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Output))
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Output -Encoding utf8
$result | ConvertTo-Json -Depth 16
if ($overall -eq 'fail') { exit 2 }
if ($overall -eq 'unknown') { exit 3 }
exit 0
