param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,
  [ValidateSet('auto', 'steady', 'startup', 'short', 'drag', 'longForward', 'longBackward', 'fullscreen')]
  [string]$Interaction = 'auto',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

<#
  将匿名桌面像素报告映射到 player_smoothness_standard_20260820.md 的工程门禁。
  该脚本只读 QA 产物，不启动播放器、不修改业务设置，也不会把后端帧代理升级为 DWM 帧。
#>

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "找不到 QA JSON：$Path"
  }
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function To-DoubleOrNull {
  param([object]$Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
  try { return [double]$Value } catch { return $null }
}

function Get-Percentile {
  param([object[]]$Values, [double]$Percentile)
  $numbers = @($Values | ForEach-Object { To-DoubleOrNull $_ } | Where-Object { $null -ne $_ })
  if ($numbers.Count -eq 0) { return $null }
  $sorted = @($numbers | Sort-Object)
  $index = [Math]::Min($sorted.Count - 1, [Math]::Max(0, [Math]::Round(($sorted.Count - 1) * $Percentile)))
  return [double]$sorted[$index]
}

function New-Gate {
  param(
    [string]$Name,
    [string]$Status,
    [object]$Value,
    [object]$Threshold,
    [string]$Evidence,
    [string]$Reason
  )
  return [pscustomobject][ordered]@{
    name = $Name
    status = $Status
    value = $Value
    threshold = $Threshold
    evidence = $Evidence
    reason = $Reason
  }
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$inputItem = Get-Item -LiteralPath $resolvedInput
$summary = $null
$baseDirectory = $null
$runReports = @()

if ($inputItem.PSIsContainer) {
  $summaryFile = Join-Path $resolvedInput 'desktop-pixel-matrix-summary.json'
  $singleReport = Join-Path $resolvedInput 'desktop-pixels\desktop-pixel-report.json'
  if (Test-Path -LiteralPath $summaryFile) {
    $summary = Read-JsonFile $summaryFile
    $baseDirectory = $resolvedInput
  } elseif (Test-Path -LiteralPath $singleReport) {
    $baseDirectory = $resolvedInput
    $runReports = @([pscustomobject]@{ record = $null; report = (Read-JsonFile $singleReport) })
  } else {
    throw "目录既没有 desktop-pixel-matrix-summary.json，也没有 desktop-pixels\desktop-pixel-report.json：$resolvedInput"
  }
} else {
  if (-not $inputItem.Name.EndsWith('.json')) { throw "InputPath 必须是 JSON 或 QA 目录：$resolvedInput" }
  $candidate = Read-JsonFile $resolvedInput
  if ($candidate.records -and $candidate.inputDownToPixel) {
    $summary = $candidate
    $baseDirectory = $inputItem.DirectoryName
  } elseif ($candidate.evidence -eq 'desktop-composited-pixel-change') {
    $baseDirectory = $inputItem.DirectoryName.Parent.FullName
    $runReports = @([pscustomobject]@{ record = $null; report = $candidate })
  } else {
    throw "无法识别桌面像素报告：$resolvedInput"
  }
}

if ($summary) {
  foreach ($record in @($summary.records)) {
    $runName = ('run-{0:d2}' -f [int]$record.run)
    $reportPath = Join-Path $baseDirectory "$runName\desktop-pixels\desktop-pixel-report.json"
    if (Test-Path -LiteralPath $reportPath) {
      $runReports += [pscustomobject]@{
        record = $record
        report = (Read-JsonFile $reportPath)
      }
    }
  }
}

if ($runReports.Count -eq 0) { throw "没有找到可评估的 desktop-pixel-report.json：$resolvedInput" }

if ($Interaction -eq 'auto') {
  $mode = [string]$summary.inputMode
  if ($mode -like '*long-hold*') {
    $Interaction = if ([int]$summary.virtualKey -eq 74) { 'longBackward' } else { 'longForward' }
  } elseif ($summary.progressDragSeekMode) {
    $Interaction = 'drag'
  } else {
    $Interaction = 'short'
  }
}

$valid = @($runReports | Where-Object {
  $recordValid = ($null -eq $_.record -or [string]$_.record.status -eq 'valid')
  $reportValid = ($null -eq $_.report.passed -or [bool]$_.report.passed)
  $recordValid -and $reportValid
})
$invalidCount = $runReports.Count - $valid.Count
$firstValues = @($valid | ForEach-Object { To-DoubleOrNull $_.report.p50InputDownToPixelMs; To-DoubleOrNull $_.report.p95InputDownToPixelMs } | Where-Object { $null -ne $_ })
$firstP95Values = @($valid | ForEach-Object { To-DoubleOrNull $_.report.p95InputDownToPixelMs } | Where-Object { $null -ne $_ })
$firstP95 = Get-Percentile $firstP95Values 0.95
$releaseP95Values = @($valid | ForEach-Object { To-DoubleOrNull $_.report.p95InputUpToPixelMs } | Where-Object { $null -ne $_ })
$releaseP95 = Get-Percentile $releaseP95Values 0.95
$unchangedValues = @($valid | ForEach-Object { To-DoubleOrNull $_.report.longestUnchangedRunMs } | Where-Object { $null -ne $_ })
$unchangedMax = if ($unchangedValues.Count -gt 0) { ($unchangedValues | Measure-Object -Maximum).Maximum } else { $null }
$semanticMissing = @($valid | Where-Object {
  $actions = @($_.report.actions)
  $actions.Count -eq 0 -or @($actions | Where-Object { -not [bool]$_.inputSemanticConfirmed }).Count -gt 0
}).Count

$firstThreshold = switch ($Interaction) {
  'startup' { 1000 }
  'short' { 250 }
  'drag' { 500 }
  'longForward' { 300 }
  'longBackward' { 300 }
  'fullscreen' { 100 }
  default { 500 }
}
$firstGateStatus = if ($valid.Count -eq 0) { 'unknown' } elseif ($firstP95 -le $firstThreshold -and $invalidCount -eq 0) { 'pass' } else { 'fail' }
$validSamplesStatus = if ($valid.Count -ge 3 -or ($summary -and [int]$summary.runs -eq 1)) { 'pass' } else { 'unknown' }
$summaryRunCount = if ($summary) { [int]$summary.runs } else { 1 }
$semanticStatus = if ($semanticMissing -eq 0 -and $valid.Count -gt 0) { 'pass' } else { 'fail' }
$semanticValue = if ($semanticMissing -eq 0) { 'confirmed' } else { "missing=$semanticMissing" }
$releaseStatus = 'not-applicable'
$releaseThreshold = $null
if ($Interaction -eq 'drag') {
  $releaseThreshold = 300
  $releaseStatus = if ($null -eq $releaseP95) { 'unknown' } elseif ($releaseP95 -le $releaseThreshold) { 'pass' } else { 'fail' }
}
$longGapStatus = 'not-applicable'
$longGapThreshold = $null
if ($Interaction -in @('longForward','longBackward','drag')) {
  $longGapThreshold = 500
  $longGapStatus = if ($null -eq $unchangedMax) { 'unknown' } elseif ($unchangedMax -le $longGapThreshold) { 'pass' } else { 'fail' }
}
$gates = @(
  (New-Gate 'valid-samples' $validSamplesStatus $valid.Count $summaryRunCount '桌面像素+动作报告' "有效轮次=$($valid.Count)，无效轮次=$invalidCount；至少 3 个独立会话才可作为矩阵 p95。"),
  (New-Gate 'input-semantic' $semanticStatus $semanticValue 'all-valid-runs-confirmed' 'player_keyboard_event/Slider 回执' '页面语义回执不能由单纯像素变化替代。'),
  (New-Gate 'first-presented-frame-p95' $firstGateStatus $firstP95 $firstThreshold 'DWM desktop-composited-pixel-change' "工程门禁；首帧 p95 必须不超过 $firstThreshold ms。"),
  (New-Gate 'release-convergence-p95' $releaseStatus $releaseP95 $releaseThreshold '松手到 DWM 变化' '拖动以松手后的准确收敛作为第二个指标。'),
  (New-Gate 'longest-unchanged-gap' $longGapStatus $unchangedMax $longGapThreshold 'DWM 指纹连续采样' '工程门禁；短按不把静止基线误当连续扫描。')
)

$intervals = @()
$changesPerRun = @()
foreach ($item in $valid) {
  $changes = @($item.report.actions | ForEach-Object { $_.presentedChanges } | Where-Object { $null -ne $_ } | Sort-Object qpcUs)
  $changesPerRun += $changes.Count
  for ($i = 1; $i -lt $changes.Count; $i++) {
    $previous = To-DoubleOrNull $changes[$i - 1].qpcUs
    $current = To-DoubleOrNull $changes[$i].qpcUs
    if ($null -ne $previous -and $null -ne $current -and $current -gt $previous) {
      $intervals += (($current - $previous) / 1000.0)
    }
  }
}
$intervalP95 = Get-Percentile $intervals 0.95
$intervalMax = if ($intervals.Count -gt 0) { ($intervals | Measure-Object -Maximum).Maximum } else { $null }
if ($Interaction -in @('longForward','longBackward')) {
  $continuityStatus = if ($intervals.Count -eq 0) { 'unknown' } elseif ($intervalP95 -le 50 -and $intervalMax -le 100 -and (@($changesPerRun | Where-Object { $_ -lt 5 }).Count -eq 0)) { 'pass' } else { 'fail' }
  $gates += New-Gate 'continuous-presented-change-pacing' $continuityStatus ([ordered]@{ p95Ms = $intervalP95; maxMs = $intervalMax; changesPerRun = $changesPerRun }) ([ordered]@{ p95Ms = 50; maxMs = 100; minimumChangesPerRun = 5 }) '匿名 DWM 指纹变化（不是逐帧计数）' '长按连续扫描工程门禁；反向 latest-only 关键帧预览若未满足只能判失败/不适用，不能宣称双向连续。'
} else {
  $gates += New-Gate 'continuous-presented-change-pacing' 'not-applicable' ([ordered]@{ p95Ms = $intervalP95; maxMs = $intervalMax; changesPerRun = $changesPerRun }) $null '匿名 DWM 指纹变化' '仅长按连续扫描适用。'
}

$runtime = @()
if ($summary -and $summary.runtimeEvidence) { $runtime = @($summary.runtimeEvidence) }
$decoderDrops = @($runtime | ForEach-Object { To-DoubleOrNull $_.decoderDropFramesMax } | Where-Object { $null -ne $_ })
$voDrops = @($runtime | ForEach-Object { To-DoubleOrNull $_.voDropFramesMax } | Where-Object { $null -ne $_ })
$totalDrops = @($runtime | ForEach-Object { To-DoubleOrNull $_.totalDropFramesMax } | Where-Object { $null -ne $_ })
$decoderMax = if ($decoderDrops.Count -gt 0) { ($decoderDrops | Measure-Object -Maximum).Maximum } else { $null }
$voMax = if ($voDrops.Count -gt 0) { ($voDrops | Measure-Object -Maximum).Maximum } else { $null }
$totalMax = if ($totalDrops.Count -gt 0) { ($totalDrops | Measure-Object -Maximum).Maximum } else { $null }
$decoderStatus = if ($null -eq $decoderMax) { 'unknown' } elseif ($decoderMax -eq 0) { 'pass' } else { 'fail' }
$voStatus = if ($null -eq $voMax) { 'unknown' } elseif ($voMax -eq 0) { 'pass' } else { 'fail' }
$gates += New-Gate 'decoder-drop' $decoderStatus $decoderMax 0 'runtime snapshot（非 DWM）' '规范语义要求不丢帧；这是动作窗口快照，稳态需单独 10 秒分母。'
$gates += New-Gate 'vo-drop' $voStatus $voMax 0 'runtime snapshot（非 DWM）' 'VO drop 不可用时不能按零处理。'
$gates += New-Gate 'steady-drop-rate' 'unknown' $totalMax '0 preferred; ≤1/10s reference' '动作窗口 runtime snapshot' '缺少独立 ≥10 秒稳态分母，遵守证据分级不下结论。'

$finalHwdec = @($runtime | ForEach-Object { [string]$_.hwdecCurrentFinal } | Where-Object { $_ })
$hwdecStatus = if ($finalHwdec.Count -eq 0) { 'unknown' } elseif (@($finalHwdec | Where-Object { $_ -eq 'no' }).Count -gt 0) { 'fail' } else { 'pass' }
$gates += New-Gate 'actual-hardware-decode' $hwdecStatus $finalHwdec 'requested hardware must remain actual hardware' 'runtime snapshot（非 DWM）' '以 hwdec-current 实际值为准；软件回退必须进入用户可见降级闭环。'

$rebuilds = @($runtime | ForEach-Object { To-DoubleOrNull $_.textureRebuildEventCount } | Where-Object { $null -ne $_ })
$rebuildMax = if ($rebuilds.Count -gt 0) { ($rebuilds | Measure-Object -Maximum).Maximum } else { $null }
$rebuildStatus = if ($null -eq $rebuildMax) { 'unknown' } elseif ($rebuildMax -eq 0) { 'pass' } else { 'unknown' }
$gates += New-Gate 'texture-rebuild-during-action' $rebuildStatus $rebuildMax 0 'runtime snapshot（非 DWM）' '启动/全屏可发生重建；只有独立稳态窗口才能判定重建是否破坏播放。'

$overall = if (@($gates | Where-Object status -eq 'fail').Count -gt 0) { 'fail' } elseif (@($gates | Where-Object status -eq 'unknown').Count -gt 0) { 'unknown' } else { 'pass' }
$result = [ordered]@{
  standard = 'player-smoothness-standard-20260820'
  interaction = $Interaction
  inputPath = $resolvedInput
  evidence = 'desktop-composited-pixel-change; runtime snapshots remain separate'
  validRuns = $valid.Count
  invalidRuns = $invalidCount
  overall = $overall
  gates = @($gates)
}

if (-not $OutputPath) {
  $OutputPath = if ($inputItem.PSIsContainer) { Join-Path $resolvedInput 'smoothness-standard-evaluation.json' } else { Join-Path $inputItem.DirectoryName 'smoothness-standard-evaluation.json' }
}
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null }
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$result | ConvertTo-Json -Depth 12
if ($overall -eq 'fail') { exit 2 }
if ($overall -eq 'unknown') { exit 3 }
exit 0
