param(
  [Parameter(Mandatory = $true)]
  [string]$InputDirectory
)

$ErrorActionPreference = 'Stop'

<# 最近秩百分位；适合十轮小样本，不用插值掩盖单次尖峰。 #>
function Get-Percentile {
  param([double[]]$Values, [double]$Percentile)
  if ($Values.Count -eq 0) { return 0.0 }
  $sorted = @($Values | Sort-Object)
  $index = [Math]::Min($sorted.Count - 1, [Math]::Round(($sorted.Count - 1) * $Percentile))
  return [double]$sorted[$index]
}

<# 输出一个指标的中位数、P95和最大值。 #>
function Get-Summary {
  param([double[]]$Values)
  if ($Values.Count -eq 0) { return [ordered]@{ median = 0; p95 = 0; max = 0 } }
  $sorted = @($Values | Sort-Object)
  $middle = [Math]::Floor($sorted.Count / 2)
  $median = if ($sorted.Count % 2 -eq 0) {
    ($sorted[$middle - 1] + $sorted[$middle]) / 2
  } else { $sorted[$middle] }
  return [ordered]@{
    median = [Math]::Round($median, 2)
    p95 = [Math]::Round((Get-Percentile $Values 0.95), 2)
    max = [Math]::Round(($Values | Measure-Object -Maximum).Maximum, 2)
  }
}

$statusPath = Join-Path $InputDirectory 'library-status.jsonl'
$framePath = Join-Path $InputDirectory 'frame-timings.jsonl'
$metricsPath = Join-Path $InputDirectory 'process-metrics.csv'
$logPath = Join-Path $InputDirectory 'stress.log'
if (-not (Test-Path -LiteralPath $statusPath)) { throw "缺少状态日志：$statusPath" }

$status = @(Get-Content -LiteralPath $statusPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
$added = @($status | Where-Object phase -eq 'added')
$removed = @($status | Where-Object phase -eq 'removed')
$settled = @($status | Where-Object phase -eq 'added_scroll_settled')
$frames = if (Test-Path -LiteralPath $framePath) {
  @(Get-Content -LiteralPath $framePath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
} else { @() }
$metrics = if (Test-Path -LiteralPath $metricsPath) { @(Import-Csv -LiteralPath $metricsPath) } else { @() }

$summary = [ordered]@{
  cyclesAdded = $added.Count
  cyclesRemoved = $removed.Count
  addElapsedMs = Get-Summary @($added | ForEach-Object { [double]$_.elapsedMs })
  addUiLatencyMs = Get-Summary @($added | ForEach-Object { [double]$_.uiLatencyMs })
  removeElapsedMs = Get-Summary @($removed | ForEach-Object { [double]$_.elapsedMs })
  removeUiLatencyMs = Get-Summary @($removed | ForEach-Object { [double]$_.uiLatencyMs })
  addedCount = Get-Summary @($added | ForEach-Object { [double]$_.addedCount })
  thumbnailQueuedAfterScroll = Get-Summary @($settled | ForEach-Object { [double]$_.thumbnailQueued })
  visibleImagesAfterScroll = Get-Summary @($settled | ForEach-Object { [double]$_.visibleImages })
  probeCompletedAfterScroll = Get-Summary @($settled | ForEach-Object { [double]$_.probeCompleted })
  frameTotalP95Ms = Get-Summary @($frames | ForEach-Object { [double]$_.totalP95Ms })
  frameTotalMaxMs = Get-Summary @($frames | ForEach-Object { [double]$_.totalMaxMs })
  framesOver33Ms = ($frames | Measure-Object over33ms -Sum).Sum
  unresponsiveSamples = @($metrics | Where-Object responding -ne 'True').Count
  workingSetMb = Get-Summary @($metrics | ForEach-Object { [double]$_.working_set_mb })
  privateMb = Get-Summary @($metrics | ForEach-Object { [double]$_.private_mb })
  threads = Get-Summary @($metrics | ForEach-Object { [double]$_.threads })
  gpuCommittedMb = Get-Summary @($metrics | ForEach-Object { [double]$_.gpu_committed_mb })
  ioReadMbPerSecond = Get-Summary @($metrics | ForEach-Object { [double]$_.io_read_mb_s })
  ioWriteMbPerSecond = Get-Summary @($metrics | ForEach-Object { [double]$_.io_write_mb_s })
}

if (Test-Path -LiteralPath $logPath) {
  $diagnostics = @(Select-String -LiteralPath $logPath -Pattern 'PLAYER_DIAGNOSTICS')
  $summary.playerDiagnosticSamples = $diagnostics.Count
  $summary.softwareDecodeSamples = @($diagnostics | Where-Object Line -match 'mpv 实际硬解: no').Count
  $summary.videoStallSamples = @($diagnostics | Where-Object Line -match '视频停滞事件: [1-9]').Count
  $summary.audioStallSamples = @($diagnostics | Where-Object Line -match '音频停滞事件: [1-9]').Count
  $seek = @($diagnostics | ForEach-Object {
    if ($_.Line -match 'seek[^|]*?([0-9]+) ms') { [double]$Matches[1] }
  })
  $summary.seekMs = Get-Summary $seek
}

$summaryPath = Join-Path $InputDirectory 'summary.json'
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
[pscustomobject]$summary | Format-List
