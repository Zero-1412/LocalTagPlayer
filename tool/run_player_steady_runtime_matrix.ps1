<#
.SYNOPSIS
  在正式 PlayerPage/MediaKit Texture 上采集独立稳态运行态窗口。

.DESCRIPTION
  该脚本不启动桌面像素探针，也不把后端属性当作 DWM 呈现证据。每轮独立 Debug
  进程播放同一匿名本机样本至少 10 秒，读取 decoder/VO/total drop、硬解、Texture
  代次和资源释放。缺失的计数保持 unknown；不会从动作窗口或空属性推断稳态通过。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Sample,
  [ValidateRange(3, 7)]
  [int]$Runs = 3,
  [ValidateRange(10, 60)]
  [int]$DurationSeconds = 10,
  [string]$DebugExecutable = '',
  [string]$Output = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw '稳态运行态矩阵只支持 Windows。' }
if (-not (Test-Path -LiteralPath $Sample -PathType Leaf)) {
  throw "本地样本不存在：$Sample"
}
if (-not $Output) {
  $Output = Join-Path $PSScriptRoot ("..\.local\qa\player-steady-runtime-matrix\" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw "输出目录已存在，拒绝覆盖既有稳态证据：$Output"
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

function Get-NullableInt {
  param([object]$Value)
  if ($null -eq $Value) { return $null }
  $parsed = 0
  if ([int]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
  return $null
}

function Get-SteadyCounterEvidence {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Samples,
    [Parameter(Mandatory = $true)][string]$Name,
    [object]$ActualDurationMilliseconds = $null
  )

  $values = @($Samples | ForEach-Object {
      $property = $_.PSObject.Properties[$Name]
      if ($null -ne $property) {
        Get-NullableInt $property.Value
      } else {
        $null
      }
    } | Where-Object { $null -ne $_ })
  $missing = $Samples.Count - $values.Count
  $reset = $false
  for ($index = 1; $index -lt $values.Count; $index++) {
    if ([int]$values[$index] -lt [int]$values[$index - 1]) {
      $reset = $true
      break
    }
  }
  $complete = $values.Count -ge 2 -and $missing -eq 0 -and -not $reset
  $delta = if ($complete) { [int]$values[-1] - [int]$values[0] } else { $null }
  $ratePerTenSeconds = if ($complete -and $ActualDurationMilliseconds -gt 0) {
    [double]$delta * 10000.0 / [double]$ActualDurationMilliseconds
  } else { $null }
  [ordered]@{
    status = if (-not $complete) { 'unknown' } elseif ($delta -gt 0) { 'fail' } else { 'pass' }
    start = if ($complete) { [int]$values[0] } else { $null }
    end = if ($complete) { [int]$values[-1] } else { $null }
    delta = $delta
    ratePerTenSeconds = $ratePerTenSeconds
    numericSampleCount = $values.Count
    missingSampleCount = $missing
    counterResetObserved = $reset
  }
}

function Get-SteadyRuntimeEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][int]$RequestedDurationMilliseconds
  )

  $summaryPath = Join-Path $RunRoot 'steady-runtime-summary.json'
  $samplesPath = Join-Path $RunRoot 'steady-runtime-samples.jsonl'
  $lifecyclePath = Join-Path $RunRoot 'qa-lifecycle.jsonl'
  $summary = if (Test-Path -LiteralPath $summaryPath) {
    Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
  } else { $null }
  $samples = @()
  if (Test-Path -LiteralPath $samplesPath) {
    foreach ($line in Get-Content -LiteralPath $samplesPath) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try { $samples += ($line | ConvertFrom-Json) } catch { }
    }
  }
  $actualDuration = if ($null -ne $summary) {
    Get-NullableInt $summary.actualDurationMs
  } else { $null }
  $lifecycle = if (Test-Path -LiteralPath $lifecyclePath) {
    Get-Content -LiteralPath $lifecyclePath -Raw
  } else { '' }
  $hwdec = @($samples | ForEach-Object {
      $property = $_.PSObject.Properties['hwdec_current']
      if ($null -ne $property) {
        [string]$property.Value
      }
    } | Where-Object { $_ -and $_ -notin @('empty', 'unavailable') } | Sort-Object -Unique)
  $generations = @($samples | ForEach-Object {
      $property = $_.PSObject.Properties['texture_generation']
      if ($null -ne $property) {
        Get-NullableInt $property.Value
      } else {
        $null
      }
    } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
  $windowComplete = $null -ne $summary -and
    [string]$summary.evidence -eq 'backend-runtime-steady-window' -and
    [string]$summary.status -eq 'complete' -and
    $null -ne $actualDuration -and
    $actualDuration -ge $RequestedDurationMilliseconds -and
    $samples.Count -ge 8
  [ordered]@{
    evidenceKind = 'backend-runtime-steady-window'
    windowComplete = $windowComplete
    requestedDurationMs = $RequestedDurationMilliseconds
    actualDurationMs = $actualDuration
    sampleCount = $samples.Count
    playingSampleCount = if ($null -ne $summary) { Get-NullableInt $summary.playingSampleCount } else { $null }
    bufferingSampleCount = if ($null -ne $summary) { Get-NullableInt $summary.bufferingSampleCount } else { $null }
    decoderDrop = Get-SteadyCounterEvidence $samples 'decoder_drop_frames' $actualDuration
    voDrop = Get-SteadyCounterEvidence $samples 'vo_drop_frames' $actualDuration
    totalDrop = Get-SteadyCounterEvidence $samples 'total_drop_frames' $actualDuration
    hwdecCurrent = $hwdec
    hwdecCurrentFinal = if ($hwdec.Count -gt 0) { [string]$hwdec[-1] } else { $null }
    textureGenerationValues = $generations
    textureGenerationDelta = if ($generations.Count -gt 1) {
      [int]$generations[-1] - [int]$generations[0]
    } else { 0 }
    resourceReleased = if ($lifecycle -match 'player_resources_released') { $true }
      elseif ($lifecycle -match 'player_release_failed') { $false }
      else { $null }
  }
}

$gate = Join-Path $PSScriptRoot 'run_player_desktop_pixel_latency_gate.ps1'
$records = @()
for ($index = 1; $index -le $Runs; $index++) {
  $runRoot = Join-Path $Output ('run-{0:D2}' -f $index)
  $failure = $null
  try {
    $gateArgs = @{
      Sample = $Sample
      Action = 'steady'
      Samples = 1
      SteadyRuntimeDurationMilliseconds = $DurationSeconds * 1000
      Output = $runRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($DebugExecutable)) {
      $gateArgs.DebugExecutable = $DebugExecutable
    }
    $gateStdoutPath = Join-Path $Output ('run-{0:D2}-steady-gate.stdout.log' -f $index)
    & $gate @gateArgs 2>&1 | Out-File -LiteralPath $gateStdoutPath -Encoding utf8
    if (-not $?) { throw 'steady_gate_failed' }
  } catch {
    $failure = 'gate_failed: ' + $_.Exception.Message
    $_ | Out-File -LiteralPath (Join-Path $Output ('run-{0:D2}-steady-gate.error.log' -f $index)) -Encoding utf8
  }
  $runtime = Get-SteadyRuntimeEvidence $runRoot ($DurationSeconds * 1000)
  $valid = $null -eq $failure -and [bool]$runtime.windowComplete
  $records += [ordered]@{
    run = $index
    status = if ($valid) { 'valid' } else { 'invalid' }
    failure = if ($valid) { $null } elseif ($null -ne $failure) { $failure } else { 'steady_window_invalid' }
    runtimeEvidence = $runtime
  }
}

$validRecords = @($records | Where-Object status -eq 'valid')
$invalidRecords = @($records | Where-Object status -eq 'invalid')
$runtimeValues = @($validRecords | ForEach-Object runtimeEvidence)
$metricStatus = [ordered]@{
  decoderDrop = @($runtimeValues | ForEach-Object { $_.decoderDrop.status })
  voDrop = @($runtimeValues | ForEach-Object { $_.voDrop.status })
  totalDrop = @($runtimeValues | ForEach-Object { $_.totalDrop.status })
}
foreach ($name in @('decoderDrop', 'voDrop', 'totalDrop')) {
  $statuses = @($metricStatus[$name])
  $metricStatus[$name] = if ($statuses.Count -lt $Runs -or $statuses -contains 'unknown') {
    'unknown'
  } elseif ($statuses -contains 'fail') {
    'fail'
  } else {
    'pass'
  }
}
$report = [ordered]@{
  schemaVersion = 1
  evidence = 'backend-runtime-steady-window'
  surface = 'product-player-page'
  requestedDurationMs = $DurationSeconds * 1000
  runs = $Runs
  successfulRuns = $validRecords.Count
  failedRuns = $invalidRecords.Count
  p95Eligible = $invalidRecords.Count -eq 0 -and $validRecords.Count -eq $Runs
  metrics = $metricStatus
  runtimeEvidence = $runtimeValues
  records = $records
}
$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $Output 'steady-runtime-matrix-summary.json') -Encoding utf8
Write-Output ("PLAYER_STEADY_RUNTIME_MATRIX " + ($report | ConvertTo-Json -Depth 16 -Compress))
if (-not $report.p95Eligible) { exit 1 }
