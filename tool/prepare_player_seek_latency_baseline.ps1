<##
.SYNOPSIS
  将已选本机素材正规化为可重放的 12-case seek manifest。

.DESCRIPTION
  路径只写入调用方指定的本机 `.local/qa` 文件；标准输出不包含路径或文件名。
  每个 case 都重新经过 ffprobe，并记录文件大小与修改时间。后续 runner 会同时
  复核媒体属性和文件身份，避免素材被替换后沿用旧基线。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceManifest,

  [Parameter(Mandatory = $true)]
  [string]$OutputManifest,

  [string]$FFprobe = '',

  [hashtable]$BudgetOverrides = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourcePath = [System.IO.Path]::GetFullPath($SourceManifest)
$outputPath = [System.IO.Path]::GetFullPath($OutputManifest)
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
  throw "源 manifest 不存在：$sourcePath"
}
if (Test-Path -LiteralPath $outputPath) {
  throw "拒绝覆盖既有 baseline：$outputPath"
}
if (-not $FFprobe) {
  $FFprobe = Join-Path $PSScriptRoot '..\windows\tools\ffmpeg\bin\ffprobe.exe'
}
$ffprobePath = [System.IO.Path]::GetFullPath($FFprobe)
if (-not (Test-Path -LiteralPath $ffprobePath -PathType Leaf)) {
  throw "ffprobe 不存在：$ffprobePath"
}

function Get-VideoProbe {
  param([Parameter(Mandatory = $true)][string]$Path)
  $raw = (& $ffprobePath -v error -select_streams v:0 `
      -show_entries stream=codec_name,width,height,bit_rate,duration `
      -of json -- $Path | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'ffprobe 无法读取 baseline 样本。' }
  $probe = $raw | ConvertFrom-Json
  $stream = @($probe.streams) | Select-Object -First 1
  if ($null -eq $stream) { throw 'baseline 样本没有视频流。' }
  return $stream
}

function Get-MaxGopSeconds {
  param([Parameter(Mandatory = $true)][string]$Path)
  $raw = & $ffprobePath -v error -select_streams v:0 `
    -show_entries packet=pts_time,flags -of csv=p=0 -- $Path
  if ($LASTEXITCODE -ne 0) { throw 'ffprobe 无法读取 baseline 样本 GOP。' }
  $keyframes = @($raw | ForEach-Object {
      $parts = $_ -split ',', 2
      if ($parts.Count -eq 2 -and $parts[1] -match 'K') {
        [double]::Parse(
          $parts[0],
          [System.Globalization.CultureInfo]::InvariantCulture
        )
      }
    } | Sort-Object)
  if ($keyframes.Count -lt 2) { throw 'baseline 样本关键帧不足。' }
  $largest = 0.0
  for ($index = 1; $index -lt $keyframes.Count; $index++) {
    $largest = [Math]::Max(
      $largest,
      [double]$keyframes[$index] - [double]$keyframes[$index - 1]
    )
  }
  return [Math]::Round($largest, 3)
}

$expectedIds = @(
  foreach ($resolution in @('1080p', '4k')) {
    foreach ($codec in @('h264', 'hevc', 'av1')) {
      foreach ($gop in @('short-gop', 'long-gop')) {
        "$resolution-$codec-$gop"
      }
    }
  }
)
$source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
$cases = @($source.cases)
if ($cases.Count -ne 12 -or
    @($cases.id | Sort-Object -Unique).Count -ne 12 -or
    @($expectedIds | Where-Object { $_ -notin $cases.id }).Count -ne 0) {
  throw '源 manifest 必须正好包含固定的 12 个 seek case。'
}

$normalizedCases = @()
foreach ($case in $cases | Sort-Object id) {
  foreach ($property in @('id', 'path', 'codec', 'width', 'height', 'gop', 'p95BudgetMs')) {
    if ($null -eq $case.$property -or "$($case.$property)".Trim().Length -eq 0) {
      throw "case $($case.id) 缺少 $property。"
    }
  }
  $mediaPath = [System.IO.Path]::GetFullPath([string]$case.path)
  if (-not (Test-Path -LiteralPath $mediaPath -PathType Leaf)) {
    throw "case $($case.id) 的本机素材不存在。"
  }
  $probe = Get-VideoProbe -Path $mediaPath
  if ([string]$probe.codec_name -ne [string]$case.codec -or
      [int]$probe.width -ne [int]$case.width -or
      [int]$probe.height -ne [int]$case.height) {
    throw "case $($case.id) 的实际 codec/分辨率与 manifest 不符。"
  }
  $maxGopSeconds = Get-MaxGopSeconds -Path $mediaPath
  if ($case.gop -eq 'short-gop' -and $maxGopSeconds -gt 1.1) {
    throw "case $($case.id) 不是 short GOP。"
  }
  if ($case.gop -eq 'long-gop' -and $maxGopSeconds -lt 4.0) {
    throw "case $($case.id) 不是 long GOP。"
  }
  $file = Get-Item -LiteralPath $mediaPath
  $budget = if ($BudgetOverrides.ContainsKey([string]$case.id)) {
    [int]$BudgetOverrides[[string]$case.id]
  } else {
    [int]$case.p95BudgetMs
  }
  if ($budget -lt 100 -or $budget -gt 10000) {
    throw "case $($case.id) 的 p95 预算必须在 100–10000ms。"
  }
  $normalizedCases += [ordered]@{
    id = [string]$case.id
    path = $mediaPath
    codec = [string]$probe.codec_name
    width = [int]$probe.width
    height = [int]$probe.height
    gop = [string]$case.gop
    p95BudgetMs = $budget
    budgetSource = if ($BudgetOverrides.ContainsKey([string]$case.id)) {
      'explicit-local-calibration'
    } else {
      'source-manifest'
    }
    selectionStatus = [string]$case.selectionStatus
    maxKeyframeIntervalSeconds = $maxGopSeconds
    durationSeconds = [Math]::Round([double]$probe.duration, 3)
    bitrateKbps = [Math]::Round([double]$probe.bit_rate / 1000.0, 1)
    sampleIdentity = [ordered]@{
      fileSizeBytes = [long]$file.Length
      lastWriteUnixMilliseconds = ([DateTimeOffset]$file.LastWriteTimeUtc).ToUnixTimeMilliseconds()
    }
  }
}

$destinationDirectory = Split-Path $outputPath -Parent
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
$calibratedBudgetOverrides = [ordered]@{}
foreach ($key in $BudgetOverrides.Keys | Sort-Object) {
  $calibratedBudgetOverrides[[string]$key] = [int]$BudgetOverrides[$key]
}
$manifest = [ordered]@{
  schemaVersion = 2
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  source = 'normalized-local-seek-baseline-plus-ffprobe'
  status = 'complete'
  scope = 'local-machine-regression-baseline-not-cross-device-performance-claim'
  build = $source.build
  actions = $source.actions
  cases = $normalizedCases
  validation = [ordered]@{
    caseCount = 12
    pathOutputPolicy = 'local-manifest-only'
    stdoutOmitsMediaPaths = $true
    shortGopMaxSeconds = 1.1
    longGopMinSeconds = 4.0
    sampleIdentity = 'file-size-plus-last-write-unix-milliseconds-and-runtime-ffprobe'
    calibratedBudgetOverrides = $calibratedBudgetOverrides
  }
}
$manifest | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath $outputPath -Encoding utf8

$summary = [ordered]@{
  status = 'complete'
  cases = 12
  codecs = @('h264', 'hevc', 'av1')
  resolutions = @('1080p', '4k')
  gops = @('short-gop', 'long-gop')
  pathsOmitted = $true
}
Write-Output "PLAYER_SEEK_BASELINE_READY $($summary | ConvertTo-Json -Compress)"
