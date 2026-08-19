[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceManifest,

  [Parameter(Mandatory = $true)]
  [string]$OutputManifest,

  [string]$EvidenceRoot = '.local\qa'
)

$ErrorActionPreference = 'Stop'

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "JSON 文件不存在：$Path"
  }
  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    throw "JSON 文件无效：$Path；$($_.Exception.Message)"
  }
}

function Get-ValidatedMatrixCandidate {
  param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [Parameter(Mandatory = $true)][string]$Root
  )

  # 只接受目录名已明确声明素材/动作的矩阵，不从媒体路径或文件内容反推 case。
  $directories = @(
    Get-ChildItem -LiteralPath $Root -Directory -Filter "$Prefix*" -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notmatch '(?i)postdwell' }
  )
  $validated = @()
  foreach ($directory in $directories) {
    $summaryPath = Join-Path $directory.FullName 'desktop-pixel-matrix-summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { continue }

    try {
      $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    } catch {
      continue
    }

    $records = @($summary.records)
    $validRecords = @($records | Where-Object { [string]$_.status -eq 'valid' })
    $complete = $true
    foreach ($record in $validRecords) {
      $runNumber = 0
      if (-not [int]::TryParse([string]$record.run, [ref]$runNumber)) {
        $complete = $false
        break
      }
      $runRoot = Join-Path $directory.FullName ('run-{0:D2}' -f $runNumber)
      $reportPath = Join-Path $runRoot 'desktop-pixels\desktop-pixel-report.json'
      if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        $reportPath = Join-Path $runRoot 'desktop-pixel-report.json'
      }
      if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        $complete = $false
        break
      }
    }

    $isEligible = [bool]$summary.p95Eligible
    $hasDwmEvidence = [string]$summary.evidence -eq 'desktop-composited-pixel-change'
    $isProductPage = [string]$summary.surface -eq 'product-player-page'
    if ($isEligible -and $hasDwmEvidence -and $isProductPage -and
      $validRecords.Count -ge 3 -and $complete) {
      $validated += [pscustomobject]@{
        directory = $directory
        validSessions = $validRecords.Count
      }
    }
  }

  # 目录名包含时间后缀时按名称倒序选最新项；规则不依赖文件系统枚举顺序。
  return $validated | Sort-Object { $_.directory.Name } -Descending | Select-Object -First 1
}

function Get-BindingPrefix {
  param([Parameter(Mandatory = $true)][object]$Binding)

  if ([int]$Binding.width -eq 1920) {
    $directoryGop = ([string]$Binding.gop) -replace '-gop$', ''
    return 'current-semantic-matrix-1080p-{0}-{1}-{2}-' -f
      [string]$Binding.codec, $directoryGop, [string]$Binding.direction
  }
  return 'current-4k-{0}-realpage-{1}-longhold-7run-' -f
    [string]$Binding.codec, [string]$Binding.direction
}

$sourceFullPath = [System.IO.Path]::GetFullPath($SourceManifest)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputManifest)
if ($sourceFullPath -eq $outputFullPath) {
  throw 'SourceManifest 与 OutputManifest 必须不同，避免覆盖原始 manifest。'
}
$evidenceRootFullPath = [System.IO.Path]::GetFullPath($EvidenceRoot)
if (-not (Test-Path -LiteralPath $evidenceRootFullPath -PathType Container)) {
  throw "证据根目录不存在：$evidenceRootFullPath"
}

$manifest = Read-JsonFile $sourceFullPath
if ([int]$manifest.schemaVersion -ne 1) {
  throw '只支持 schemaVersion=1 的 P0 manifest。'
}
$cases = @($manifest.cases)
if ($cases.Count -ne 12) {
  throw "P0 manifest 必须包含 12 个 case，实际为 $($cases.Count)。"
}

# 只声明已经有明确目录合同的组合；未列出的动作继续留在 unknown。
$bindings = @(
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'h264'; direction = 'forward'; action = 'shortForward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'h264'; direction = 'backward'; action = 'shortBackward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'h264'; direction = 'drag'; action = 'drag' },
  [ordered]@{ width = 1920; gop = 'long-gop'; codec = 'h264'; direction = 'forward'; action = 'longForward' },
  [ordered]@{ width = 1920; gop = 'long-gop'; codec = 'h264'; direction = 'backward'; action = 'longBackward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'hevc'; direction = 'forward'; action = 'shortForward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'hevc'; direction = 'backward'; action = 'shortBackward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'hevc'; direction = 'drag'; action = 'drag' },
  [ordered]@{ width = 1920; gop = 'long-gop'; codec = 'hevc'; direction = 'forward'; action = 'longForward' },
  [ordered]@{ width = 1920; gop = 'long-gop'; codec = 'hevc'; direction = 'backward'; action = 'longBackward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'av1'; direction = 'forward'; action = 'shortForward' },
  [ordered]@{ width = 1920; gop = 'short-gop'; codec = 'av1'; direction = 'backward'; action = 'shortBackward' },
  [ordered]@{ width = 1920; gop = 'long-gop'; codec = 'av1'; direction = 'forward'; action = 'longForward' },
  [ordered]@{ width = 1920; gop = 'long-gop'; codec = 'av1'; direction = 'backward'; action = 'longBackward' },
  [ordered]@{ width = 3840; gop = 'long-gop'; codec = 'h264'; direction = 'forward'; action = 'longForward' },
  [ordered]@{ width = 3840; gop = 'long-gop'; codec = 'h264'; direction = 'backward'; action = 'longBackward' },
  [ordered]@{ width = 3840; gop = 'long-gop'; codec = 'hevc'; direction = 'forward'; action = 'longForward' },
  [ordered]@{ width = 3840; gop = 'long-gop'; codec = 'hevc'; direction = 'backward'; action = 'longBackward' },
  [ordered]@{ width = 3840; gop = 'long-gop'; codec = 'av1'; direction = 'forward'; action = 'longForward' },
  [ordered]@{ width = 3840; gop = 'long-gop'; codec = 'av1'; direction = 'backward'; action = 'longBackward' }
)
$actions = @('startup', 'shortForward', 'shortBackward', 'drag', 'longForward', 'longBackward', 'fullscreen')
$mapped = @()
$omitted = @()

foreach ($case in $cases) {
  $caseEvidence = [ordered]@{}
  foreach ($action in $actions) {
    $matchingBindings = @($bindings | Where-Object {
        [int]$_.width -eq [int]$case.width -and
          [string]$_.gop -eq [string]$case.gop -and
          [string]$_.codec -eq [string]$case.codec -and
          [string]$_.action -eq $action
      })
    if ($matchingBindings.Count -eq 0) {
      $omitted += [ordered]@{
        caseId = [string]$case.id
        action = $action
        reason = 'no-exact-directory-binding'
      }
      continue
    }

    $binding = $matchingBindings[0]
    $prefix = Get-BindingPrefix $binding
    $candidate = Get-ValidatedMatrixCandidate -Prefix $prefix -Root $evidenceRootFullPath
    if ($null -eq $candidate) {
      $omitted += [ordered]@{
        caseId = [string]$case.id
        action = $action
        reason = 'no-validated-explicit-matrix'
        expectedPrefix = $prefix
      }
      continue
    }

    $caseEvidence[$action] = @($candidate.directory.FullName)
    $mapped += [ordered]@{
      caseId = [string]$case.id
      action = $action
      directoryName = $candidate.directory.Name
      validSessions = $candidate.validSessions
      selectionRule = 'validated summary; product-player-page; p95Eligible; directory name descending'
    }
  }

  if ($caseEvidence.Count -gt 0) {
    $case | Add-Member -MemberType NoteProperty -Name evidence -Value $caseEvidence -Force
  } elseif ($null -ne $case.PSObject.Properties['evidence']) {
    # 每次从源 manifest 重建，避免旧目录被删除后残留陈旧 evidence。
    $case.PSObject.Properties.Remove('evidence')
  }
}

$assembly = [ordered]@{
  schemaVersion = 1
  source = 'explicit-directory-name-and-summary'
  selectionRule = '目录名精确声明 resolution/codec/GOP/action；summary 必须为 product-player-page、desktop-composited-pixel-change、p95Eligible 且至少 3 个 valid run'
  mappedCount = $mapped.Count
  omittedCount = $omitted.Count
  mapped = @($mapped)
  omitted = @($omitted)
}
$manifest | Add-Member -MemberType NoteProperty -Name evidenceAssembly -Value $assembly -Force

$outputDirectory = Split-Path -Parent $outputFullPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$json = $manifest | ConvertTo-Json -Depth 20
Set-Content -LiteralPath $outputFullPath -Value $json -Encoding utf8
Write-Output "evidenceAssembly mapped=$($mapped.Count) omitted=$($omitted.Count)"
