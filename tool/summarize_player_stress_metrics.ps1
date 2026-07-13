param(
  [Parameter(Mandatory = $true)]
  [string]$InputDirectory,
  [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$metricsPath = Join-Path $InputDirectory 'process-metrics.csv'
if (-not (Test-Path -LiteralPath $metricsPath)) {
  throw "找不到进程采样文件：$metricsPath"
}

<# 返回升序样本的最近秩百分位，避免阶段峰值被单个启动样本代表。 #>
function Get-Percentile {
  param([double[]]$Values, [double]$Percentile)
  if ($Values.Count -eq 0) { return 0.0 }
  $sorted = @($Values | Sort-Object)
  $index = [Math]::Min(
    $sorted.Count - 1,
    [Math]::Max(0, [Math]::Round(($sorted.Count - 1) * $Percentile))
  )
  return [double]$sorted[$index]
}

<# 为当前指标生成中位数、P95和最大值。 #>
function Get-MetricSummary {
  param([object[]]$Rows, [string]$Property)
  $values = @($Rows | ForEach-Object { [double]$_.$Property })
  $sorted = @($values | Sort-Object)
  $middle = [Math]::Floor($sorted.Count / 2)
  $median = if ($sorted.Count % 2 -eq 0) {
    ($sorted[$middle - 1] + $sorted[$middle]) / 2
  } else {
    $sorted[$middle]
  }
  return @($median, (Get-Percentile $values 0.95), ($values | Measure-Object -Maximum).Maximum)
}

$rows = @(Import-Csv -LiteralPath $metricsPath)
for ($index = 0; $index -lt $rows.Count; $index++) {
  $cpuPercent = 0.0
  if ($index -gt 0) {
    $elapsed = ([datetimeoffset]$rows[$index].timestamp - [datetimeoffset]$rows[$index - 1].timestamp).TotalSeconds
    $cpuDelta = [double]$rows[$index].cpu_seconds - [double]$rows[$index - 1].cpu_seconds
    if ($elapsed -gt 0 -and $cpuDelta -ge 0) {
      $cpuPercent = $cpuDelta / $elapsed * 100
    }
  }
  $rows[$index] | Add-Member -NotePropertyName cpu_percent -NotePropertyValue $cpuPercent
}

$properties = @(
  'cpu_percent', 'threads', 'working_set_mb', 'private_mb',
  'handles', 'gpu_dedicated_mb', 'gpu_shared_mb', 'gpu_committed_mb'
)
$summary = foreach ($group in $rows | Group-Object phase) {
  $record = [ordered]@{
    phase = $group.Name
    samples = $group.Count
    unresponsive = @($group.Group | Where-Object responding -ne 'True').Count
  }
  foreach ($property in $properties) {
    $metric = Get-MetricSummary $group.Group $property
    $record["${property}_median"] = [Math]::Round($metric[0], 1)
    $record["${property}_p95"] = [Math]::Round($metric[1], 1)
    $record["${property}_max"] = [Math]::Round($metric[2], 1)
  }
  [pscustomobject]$record
}

$summaryPath = Join-Path $InputDirectory 'phase-summary.csv'
$summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding utf8
$summary | Format-Table phase, samples, unresponsive, cpu_percent_median, threads_median, working_set_mb_median, private_mb_median, gpu_committed_mb_median

if ($LogPath -and (Test-Path -LiteralPath $LogPath)) {
  $text = Get-Content -LiteralPath $LogPath -Raw
  # 使用ASCII锚点解析，兼容Windows PowerShell 5.1读取无BOM UTF-8脚本。
  $seekValues = @()
  foreach ($diagnosticLine in Select-String -LiteralPath $LogPath -Pattern 'PLAYER_DIAGNOSTICS') {
    if ($diagnosticLine.Line -match 'seek[^|]*?([0-9]+) ms') {
      $seekValues = @($seekValues) + ,([double]($Matches[1]))
    }
  }
  $seekValues = @($seekValues | Where-Object { $_ -gt 0 })
  $latencySummary = @()
  if ($seekValues.Count -gt 0) {
    $latencySummary += [pscustomobject]@{
      metric = 'seek_ms'
      samples = $seekValues.Count
      median = [Math]::Round((Get-MetricSummary @($seekValues | ForEach-Object { [pscustomobject]@{ value = $_ } }) 'value')[0], 1)
      p95 = [Math]::Round((Get-Percentile $seekValues 0.95), 1)
      max = [Math]::Round(($seekValues | Measure-Object -Maximum).Maximum, 1)
    }
  }
  $disposeValues = @(
    [regex]::Matches($text, 'dispose_start=([^ ]+) dispose_end=([^\r\n]+)') |
      ForEach-Object {
        ([datetimeoffset]$_.Groups[2].Value.Trim() - [datetimeoffset]$_.Groups[1].Value).TotalMilliseconds
      }
  )
  if ($disposeValues.Count -gt 0) {
    $latencySummary += [pscustomobject]@{
      metric = 'dispose_ms'
      samples = $disposeValues.Count
      median = [Math]::Round((Get-MetricSummary @($disposeValues | ForEach-Object { [pscustomobject]@{ value = $_ } }) 'value')[0], 1)
      p95 = [Math]::Round((Get-Percentile $disposeValues 0.95), 1)
      max = [Math]::Round(($disposeValues | Measure-Object -Maximum).Maximum, 1)
    }
  }
  $latencySummary | Export-Csv -LiteralPath (Join-Path $InputDirectory 'latency-summary.csv') -NoTypeInformation -Encoding utf8
}
