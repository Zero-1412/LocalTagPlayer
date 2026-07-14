<#
  管理压力测试输出的生命周期。

  ArtifactsRoot：统一产物根目录，只在其直接子目录中执行过期清理。
  RetentionDays：自动过期天数；设为 0 时禁用自动过期。
  CompactDirectory：成功压测后需要压缩的单个输出目录；为空时只执行过期清理。
  KeepFileNames：压缩后保留在输出根目录的汇总文件名。
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$ArtifactsRoot,
  [ValidateRange(0, 3650)]
  [int]$RetentionDays = 7,
  [string]$CompactDirectory = '',
  [string[]]$KeepFileNames = @('summary.json', 'phase-summary.csv', 'latency-summary.csv')
)

$ErrorActionPreference = 'Stop'
$markerName = '.ltp-stress-artifact'
$manifestName = 'artifact-manifest.json'

<#
  返回规范化绝对路径，供后续删除前执行边界校验。
#>
function Get-NormalizedPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

<#
  判断候选路径是否严格位于父目录内部，禁止把父目录自身作为删除目标。
#>
function Test-ChildPath {
  param(
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$Parent
  )
  return $Candidate.StartsWith(
    $Parent + '\',
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

<#
  统计目录内的文件数量与字节数，用于在压缩清单中记录释放效果。
#>
function Get-DirectoryStatistics {
  param([Parameter(Mandatory = $true)][string]$Path)
  $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue)
  $bytes = if ($files.Count -eq 0) {
    0
  } else {
    [long](($files | Measure-Object Length -Sum).Sum)
  }
  return [ordered]@{
    files = $files.Count
    bytes = $bytes
  }
}

$root = Get-NormalizedPath $ArtifactsRoot
New-Item -ItemType Directory -Force -Path $root | Out-Null

# 只清理带专用标记的直接子目录，避免误删 artifacts 下的人工证据或其它文件。
if ($RetentionDays -gt 0) {
  $cutoff = (Get-Date).ToUniversalTime().AddDays(-$RetentionDays)
  foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -Force) {
    $candidate = Get-NormalizedPath $directory.FullName
    $marker = Join-Path $candidate $markerName
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { continue }
    if ($directory.LastWriteTimeUtc -ge $cutoff) { continue }
    if (-not (Test-ChildPath -Candidate $candidate -Parent $root)) {
      throw "拒绝清理产物根目录外的路径：$candidate"
    }
    Write-Output "删除超过 $RetentionDays 天的压力测试产物：$candidate"
    Remove-Item -LiteralPath $candidate -Recurse -Force
  }
}

if (-not $CompactDirectory) { return }

$compact = Get-NormalizedPath $CompactDirectory
$marker = Join-Path $compact $markerName
if (-not (Test-Path -LiteralPath $compact -PathType Container)) {
  throw "待压缩的压力测试目录不存在：$compact"
}
if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
  throw "待压缩目录缺少压力测试标记，拒绝删除：$compact"
}
if ([System.IO.Path]::GetPathRoot($compact).TrimEnd('\') -eq $compact) {
  throw "拒绝压缩磁盘根目录：$compact"
}

$before = Get-DirectoryStatistics $compact
$keep = @($KeepFileNames + $markerName + $manifestName | Sort-Object -Unique)

# 汇总文件均位于输出根目录；子目录包含隔离 profile、缩略图和临时数据库，可整体删除。
foreach ($childDirectory in Get-ChildItem -LiteralPath $compact -Directory -Force) {
  $child = Get-NormalizedPath $childDirectory.FullName
  if (-not (Test-ChildPath -Candidate $child -Parent $compact)) {
    throw "拒绝压缩目标目录外的路径：$child"
  }
  Remove-Item -LiteralPath $child -Recurse -Force
}
foreach ($file in Get-ChildItem -LiteralPath $compact -File -Force) {
  if ($keep -contains $file.Name) { continue }
  Remove-Item -LiteralPath $file.FullName -Force
}

$after = Get-DirectoryStatistics $compact
$retainedFiles = @(
  Get-ChildItem -LiteralPath $compact -File -Force |
    Where-Object Name -ne $manifestName |
    Select-Object -ExpandProperty Name |
    Sort-Object
)
$manifest = [ordered]@{
  schemaVersion = 1
  compactedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  retentionDays = $RetentionDays
  originalFiles = $before.files
  originalBytes = $before.bytes
  retainedFiles = $retainedFiles
  retainedBytesBeforeManifest = $after.bytes
  removedFiles = $before.files - $after.files
  removedBytes = $before.bytes - $after.bytes
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $compact $manifestName) -Encoding UTF8
Write-Output ("压力测试产物已压缩：{0}，释放 {1:N1} MiB" -f $compact, ($manifest.removedBytes / 1MB))
