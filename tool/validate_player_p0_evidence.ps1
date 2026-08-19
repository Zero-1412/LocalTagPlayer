<#
.SYNOPSIS
  校验 Local Tag Player P0 播放真实性能 manifest 与匿名证据覆盖。

.DESCRIPTION
  该工具只读取调用方明确提供的本机 manifest 和 QA 产物，不启动播放器、不读取资料库，
  也不把后端帧代理升级为 DWM 呈现。输出只保留 case/action/数量和 pass、fail、unknown
  状态，不回写媒体路径、文件名、videoId 或像素数据。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Manifest,
  [string]$Output = '',
  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedCodecs = @('h264', 'hevc', 'av1')
$expectedResolutions = @('1080p', '4k')
$expectedGops = @('short-gop', 'long-gop')
$actions = @(
  'startup',
  'shortForward',
  'shortBackward',
  'drag',
  'longForward',
  'longBackward',
  'fullscreen'
)

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-NumberOrNull {
  param([object]$Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
  try { return [double]$Value } catch { return $null }
}

function Get-ObjectProperty {
  param(
    [object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function New-Metric {
  param(
    [string]$Name,
    [ValidateSet('pass', 'fail', 'unknown')]
    [string]$Status,
    [object]$Value,
    [string]$Reason
  )
  return [ordered]@{
    name = $Name
    status = $Status
    value = $Value
    reason = $Reason
  }
}

function Get-ExpectedCaseIds {
  $ids = @()
  foreach ($resolution in $expectedResolutions) {
    foreach ($codec in $expectedCodecs) {
      foreach ($gop in $expectedGops) {
        $ids += "$resolution-$codec-$gop"
      }
    }
  }
  return $ids
}

function Get-SessionRoots {
  param([object]$EvidenceValue)
  if ($null -eq $EvidenceValue) { return @() }
  $values = @($EvidenceValue)
  $roots = @()
  foreach ($value in $values) {
    if ($null -eq $value) { continue }
    $candidate = [string]$value
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      $roots += [System.IO.Path]::GetFullPath($candidate)
    }
  }
  return @($roots | Sort-Object -Unique)
}

function Get-RunEvidence {
  param([Parameter(Mandatory = $true)][string]$Root)

  $summaryPath = Join-Path $Root 'desktop-pixel-matrix-summary.json'
  $summary = Read-JsonFile $summaryPath
  $runRoots = @()
  if ($null -ne $summary) {
    foreach ($record in @($summary.records)) {
      $runNumber = Get-NumberOrNull $record.run
      if ($null -eq $runNumber) { continue }
      $runRoot = Join-Path $Root ('run-{0:D2}' -f [int]$runNumber)
      if (Test-Path -LiteralPath $runRoot -PathType Container) {
        $runRoots += [ordered]@{ root = $runRoot; record = $record }
      }
    }
  } else {
    # 允许把一个独立 run 目录作为证据入口，便于补录失败/人工会话。
    $runRoots += [ordered]@{ root = $Root; record = $null }
  }

  $sessions = @()
  foreach ($run in $runRoots) {
    $report = Read-JsonFile (Join-Path $run.root 'desktop-pixels\desktop-pixel-report.json')
    if ($null -eq $report) {
      $report = Read-JsonFile (Join-Path $run.root 'desktop-pixel-report.json')
    }
    $runtime = if ($null -ne $run.record) {
      Get-ObjectProperty $run.record 'runtimeEvidence'
    } else { $null }
    $lifecyclePath = Join-Path $run.root 'qa-lifecycle.jsonl'
    $lifecycle = if (Test-Path -LiteralPath $lifecyclePath -PathType Leaf) {
      Get-Content -LiteralPath $lifecyclePath -Raw
    } else { '' }
    $presentedEvidence = if ($null -ne $report) {
      [string](Get-ObjectProperty $report 'evidence')
    } else { '' }
    $reportActions = if ($null -ne $report) {
      Get-ObjectProperty $report 'actions'
    } else { $null }
    $action = if ($null -ne $reportActions -and @($reportActions).Count -gt 0) {
      @($reportActions)[0]
    } else { $null }
    $reportPassed = Get-ObjectProperty $report 'passed'
    $sessions += [ordered]@{
      hasReport = $null -ne $report
      passed = $null -ne $report -and
        $presentedEvidence -eq 'desktop-composited-pixel-change' -and
        ($null -eq $reportPassed -or [bool]$reportPassed)
      dwmEvidence = $presentedEvidence -eq 'desktop-composited-pixel-change'
      evidenceKind = $presentedEvidence
      firstDwmMs = if ($null -ne $report) {
        Get-NumberOrNull (Get-ObjectProperty $report 'p95InputDownToPixelMs')
      } else { $null }
      semanticConfirmed = if ($null -ne $action -and
        $null -ne (Get-ObjectProperty $action 'inputSemanticConfirmed')) {
        [bool](Get-ObjectProperty $action 'inputSemanticConfirmed')
      } else { $null }
      resourceReleased = if ($lifecycle -match 'player_resources_released') {
        $true
      } elseif ($lifecycle -match 'player_release_failed') {
        $false
      } else { $null }
      runtime = $runtime
      textureGenerationRecorded = $null -ne $runtime -and @(
        Get-ObjectProperty $runtime 'textureGenerationValues'
      ).Count -gt 0
    }
  }
  return @($sessions)
}

function Get-ActionThreshold {
  param([string]$Action)
  switch ($Action) {
    'startup' { return 1000 }
    'shortForward' { return 250 }
    'shortBackward' { return 250 }
    'drag' { return 500 }
    'longForward' { return 300 }
    'longBackward' { return 300 }
    'fullscreen' { return 100 }
    default { return $null }
  }
}

function Get-ActionMetrics {
  param(
    [string]$Action,
    [object]$EvidenceValue
  )

  $roots = @(Get-SessionRoots $EvidenceValue)
  $sessions = @()
  foreach ($root in $roots) { $sessions += @(Get-RunEvidence $root) }
  $valid = @($sessions | Where-Object { $_.hasReport -and $_.passed })
  $invalid = @($sessions | Where-Object { -not $_.passed })
  $threshold = Get-ActionThreshold $Action
  $firstValues = @($valid | ForEach-Object { $_.firstDwmMs } | Where-Object { $null -ne $_ })
  $firstMax = if ($firstValues.Count -gt 0) {
    ($firstValues | Measure-Object -Maximum).Maximum
  } else { $null }

  $sessionStatus = if ($valid.Count -ge 3) { 'pass' } else { 'unknown' }
  $dwmStatus = if ($invalid.Count -gt 0) { 'fail' }
    elseif ($firstValues.Count -lt 3) { 'unknown' }
    elseif ($firstMax -le $threshold) { 'pass' }
    else { 'fail' }

  $semanticRequired = $Action -in @('shortForward', 'shortBackward', 'drag', 'longForward', 'longBackward')
  $semanticValues = @($valid | ForEach-Object { $_.semanticConfirmed })
  $semanticStatus = if (-not $semanticRequired) { 'unknown' }
    elseif ($semanticValues.Count -lt 3) { 'unknown' }
    elseif (@($semanticValues | Where-Object { $null -eq $_ }).Count -gt 0) { 'unknown' }
    elseif (@($semanticValues | Where-Object { $_ -eq $false }).Count -gt 0) { 'fail' }
    else { 'pass' }

  $releaseValues = @($valid | ForEach-Object { $_.resourceReleased })
  $releaseStatus = if ($releaseValues.Count -lt 3) { 'unknown' }
    elseif (@($releaseValues | Where-Object { $_ -eq $false }).Count -gt 0) { 'fail' }
    elseif (@($releaseValues | Where-Object { $_ -ne $true }).Count -gt 0) { 'unknown' }
    else { 'pass' }

  $hwdecValues = @($valid | ForEach-Object {
    $hwdec = Get-ObjectProperty $_.runtime 'hwdecCurrentFinal'
    if ($null -ne $hwdec) { [string]$hwdec }
  } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $hwdecStatus = if ($hwdecValues.Count -lt 3) { 'unknown' }
    elseif (@($hwdecValues | Where-Object { $_ -eq 'no' }).Count -gt 0) { 'fail' }
    else { 'pass' }

  $decoderValues = @($valid | ForEach-Object {
    Get-NumberOrNull (Get-ObjectProperty $_.runtime 'decoderDropFramesMax')
  } | Where-Object { $null -ne $_ })
  $voValues = @($valid | ForEach-Object {
    Get-NumberOrNull (Get-ObjectProperty $_.runtime 'voDropFramesMax')
  } | Where-Object { $null -ne $_ })
  $totalValues = @($valid | ForEach-Object {
    Get-NumberOrNull (Get-ObjectProperty $_.runtime 'totalDropFramesMax')
  } | Where-Object { $null -ne $_ })
  $decoderStatus = if ($decoderValues.Count -lt 3) { 'unknown' }
    elseif (($decoderValues | Measure-Object -Maximum).Maximum -gt 0) { 'fail' }
    else { 'pass' }
  $voStatus = if ($voValues.Count -lt 3) { 'unknown' }
    elseif (($voValues | Measure-Object -Maximum).Maximum -gt 0) { 'fail' }
    else { 'pass' }
  # action-window drop 不能代替 10 秒稳态分母；不把数值为零误写成通过。
  $totalStatus = 'unknown'
  $textureValues = @($valid | Where-Object { $_.textureGenerationRecorded })
  $textureStatus = if ($textureValues.Count -ge 3) { 'pass' } else { 'unknown' }

  $metrics = @(
    (New-Metric 'independent-sessions' $sessionStatus $valid.Count '每个有效 action 至少需要 3 个独立会话。'),
    (New-Metric 'first-real-dwm-frame' $dwmStatus $firstMax '首个实际 DWM/桌面合成变化；后端帧代理不能替代。'),
    (New-Metric 'page-semantic-evidence' $semanticStatus $semanticValues '页面回执与 DWM 证据分开验收；缺失时保持 unknown。'),
    (New-Metric 'resource-release' $releaseStatus $releaseValues '释放事件必须可见；失败不能被成功帧覆盖。'),
    (New-Metric 'hardware-decode' $hwdecStatus $hwdecValues '只接受运行态最终硬解属性，不按请求参数推测。'),
    (New-Metric 'decoder-drop' $decoderStatus $decoderValues '动作窗口只能判掉帧非零失败；缺字段为 unknown。'),
    (New-Metric 'vo-drop' $voStatus $voValues 'VO drop 不可用时不能按零处理。'),
    (New-Metric 'steady-total-drop' $totalStatus $totalValues '必须有独立至少 10 秒稳态分母；动作窗口数值不作通过。'),
    (New-Metric 'texture-generation-recorded' $textureStatus $textureValues.Count '记录 Texture 代次/重建；稳态不重建仍需独立 10 秒窗口。')
  )
  $overall = if (@($metrics | Where-Object status -eq 'fail').Count -gt 0) { 'fail' }
    elseif (@($metrics | Where-Object status -eq 'unknown').Count -gt 0) { 'unknown' }
    else { 'pass' }
  return [ordered]@{
    action = $Action
    overall = $overall
    thresholdMs = $threshold
    evidenceDirectories = $roots.Count
    validSessions = $valid.Count
    invalidSessions = $invalid.Count
    metrics = @($metrics)
  }
}

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
  throw 'P0 manifest 不存在。'
}
$manifestData = Read-JsonFile $Manifest
if ($null -eq $manifestData) { throw 'P0 manifest 不是有效 JSON。' }

$expectedIds = @(Get-ExpectedCaseIds)
$manifestVersion = Get-ObjectProperty $manifestData 'schemaVersion'
$cases = @(Get-ObjectProperty $manifestData 'cases')
$actualIds = @($cases | ForEach-Object { [string](Get-ObjectProperty $_ 'id') })
$manifestShape = @(
  (New-Metric 'manifest-schema' $(if ($null -ne $manifestVersion -and [int]$manifestVersion -eq 1) { 'pass' } else { 'fail' }) $manifestVersion 'schemaVersion 必须为 1。'),
  (New-Metric 'manifest-case-set' $(if ($cases.Count -eq 12 -and @($actualIds | Sort-Object -Unique).Count -eq 12 -and @($expectedIds | Where-Object { $_ -notin $actualIds }).Count -eq 0) { 'pass' } else { 'fail' }) $cases.Count '必须正好覆盖 1080p/4K × H.264/HEVC/AV1 × short/long GOP 的 12 个 case。')
)

$caseRecords = @()
foreach ($case in $cases) {
  $caseId = [string](Get-ObjectProperty $case 'id')
  $casePath = [string](Get-ObjectProperty $case 'path')
  $caseCodec = [string](Get-ObjectProperty $case 'codec')
  $caseGop = [string](Get-ObjectProperty $case 'gop')
  $caseWidth = Get-NumberOrNull (Get-ObjectProperty $case 'width')
  $caseHeight = Get-NumberOrNull (Get-ObjectProperty $case 'height')
  $caseBudget = Get-NumberOrNull (Get-ObjectProperty $case 'p95BudgetMs')
  $caseChecks = @()
  $caseChecks += New-Metric 'case-identity' $(if ($caseId -in $expectedIds) { 'pass' } else { 'fail' }) $caseId 'case id 必须来自固定 12-case 集合。'
  $caseChecks += New-Metric 'media-manifest-fields' $(if (
      -not [string]::IsNullOrWhiteSpace($casePath) -and
      $caseCodec -in $expectedCodecs -and
      $caseGop -in $expectedGops -and
      $null -ne $caseWidth -and $caseWidth -gt 0 -and
      $null -ne $caseHeight -and $caseHeight -gt 0 -and
      $null -ne $caseBudget -and $caseBudget -gt 0) { 'pass' } else { 'fail' }) $caseId 'manifest 必须包含本机样本、编码、尺寸、GOP 分类和预算。'
  $actionResults = [ordered]@{}
  foreach ($action in $actions) {
    $evidenceObject = if ($null -ne $case.PSObject.Properties['evidence']) {
      $case.evidence
    } else { $null }
    $evidenceValue = if ($null -ne $evidenceObject -and
      $null -ne $evidenceObject.PSObject.Properties[$action]) {
      $evidenceObject.PSObject.Properties[$action].Value
    } else { $null }
    if ($ValidateOnly) {
      $actionResults[$action] = [ordered]@{
        action = $action
        overall = 'unknown'
        thresholdMs = Get-ActionThreshold $action
        evidenceDirectories = 0
        validSessions = 0
        invalidSessions = 0
        metrics = @((New-Metric 'evidence-coverage' 'unknown' $null 'ValidateOnly 未读取 QA 产物。'))
      }
    } else {
      $actionResults[$action] = Get-ActionMetrics $action $evidenceValue
    }
  }
  $allMetrics = @($caseChecks)
  foreach ($actionResult in $actionResults.Values) {
    $allMetrics += @($actionResult.metrics)
  }
  $caseOverall = if (@($allMetrics | Where-Object status -eq 'fail').Count -gt 0) { 'fail' }
    elseif (@($allMetrics | Where-Object status -eq 'unknown').Count -gt 0) { 'unknown' }
    else { 'pass' }
  $caseRecords += [ordered]@{
    id = $caseId
    overall = $caseOverall
    metrics = @($caseChecks)
    actions = $actionResults
  }
}

$build = Get-ObjectProperty $manifestData 'build'
$buildMetrics = @(
  (New-Metric 'debug-build' $(if ($null -ne $build -and [string]$build.configuration -eq 'Debug') { 'pass' } else { 'unknown' }) $(if ($null -ne $build) { [string]$build.configuration } else { $null }) '固定 Debug 构建；缺少身份信息不能判通过。'),
  (New-Metric 'formal-texture-path' $(if ($null -ne $build -and [string]$build.surface -eq 'mediaKit-texture') { 'pass' } else { 'unknown' }) $(if ($null -ne $build) { [string]$build.surface } else { $null }) '正式 Texture 必须明确为 MediaKit Texture。'),
  (New-Metric 'build-fingerprint' $(if ($null -ne $build -and -not [string]::IsNullOrWhiteSpace([string]$build.executableSha256)) { 'pass' } else { 'unknown' }) $null '报告必须固定 Debug 可执行文件 SHA-256；不把路径写入报告。'),
  (New-Metric 'dwm-evidence-kind' $(if ($null -ne $build -and [string]$build.evidenceKind -eq 'desktop-composited-pixel-change') { 'pass' } else { 'unknown' }) $(if ($null -ne $build) { [string]$build.evidenceKind } else { $null }) '首个实际 DWM 呈现帧是延迟终点。')
)

$allResults = @($manifestShape + $buildMetrics + ($caseRecords | ForEach-Object { $_.metrics }) + ($caseRecords | ForEach-Object { $_.actions.Values | ForEach-Object { $_.metrics } }))
$overall = if (@($allResults | Where-Object status -eq 'fail').Count -gt 0) { 'fail' }
  elseif (@($allResults | Where-Object status -eq 'unknown').Count -gt 0) { 'unknown' }
  else { 'pass' }

$result = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  evidence = 'p0-player-real-dwm-texture'
  overall = $overall
  validateOnly = [bool]$ValidateOnly
  metrics = @($manifestShape + $buildMetrics)
  cases = @($caseRecords)
}

if (-not $Output) {
  $Output = Join-Path ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Manifest))) 'p0-evidence-gate.json'
}
$outputDirectory = Split-Path -Parent $Output
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
$result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $Output -Encoding utf8
$result | ConvertTo-Json -Depth 14
if ($overall -eq 'fail') { exit 2 }
if ($overall -eq 'unknown') { exit 3 }
exit 0
