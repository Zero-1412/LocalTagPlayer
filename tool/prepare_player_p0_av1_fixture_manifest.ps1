<##
.SYNOPSIS
  生成两个隔离的 AV1 P0 QA 素材并写出经 ffprobe 验证的本机 manifest 副本。

.DESCRIPTION
  本工具只用于补齐本机资料库缺失的 1080p AV1 short-GOP 与 4K AV1 long-GOP
  case。输出目录必须是新的隔离 QA 目录；源视频只作为输入，不会被修改。生成后
  必须重新读取实际视频流、码率、时长和关键帧时间，任一合同不满足就拒绝写出
  manifest，不能把“编码命令成功”当成 case 覆盖。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ShortSource,

  [Parameter(Mandatory = $true)]
  [string]$LongSource,

  [Parameter(Mandatory = $true)]
  [string]$SourceManifest,

  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,

  [ValidateRange(25, 120)]
  [int]$DurationSeconds = 30,

  [string]$DebugExecutable = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RequiredCommand {
  param([Parameter(Mandatory = $true)][string]$Name)
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) { throw "缺少必需命令：$Name" }
  return $command.Source
}

function Invoke-Ffmpeg {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$LogPath
  )
  & $script:ffmpegPath @Arguments *> $LogPath
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "ffmpeg 生成 QA 素材失败，exit=$exitCode，日志=$LogPath"
  }
}

function Get-FfprobeJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $raw = (& $script:ffprobePath @Arguments -- $Path | Out-String)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { throw "ffprobe 读取失败，exit=$exitCode，path=$Path" }
  if ([string]::IsNullOrWhiteSpace($raw)) { throw "ffprobe 没有输出，path=$Path" }
  return $raw | ConvertFrom-Json
}

function Get-KeyframeEvidence {
  param([Parameter(Mandatory = $true)][string]$Path)
  # 只读 packet flags；不让 ffprobe 为了 show_frames 走 libaom 解码，避免把
  # 本机软件解码器的 AV1 level 支持差异误报成素材 GOP 失败。
  $packetArguments = @(
    '-v', 'error',
    '-select_streams', 'v:0',
    '-read_intervals', ("%+$DurationSeconds"),
    '-show_entries', 'packet=pts_time,flags',
    '-of', 'csv=p=0'
  )
  $raw = (& $script:ffprobePath @packetArguments -- $Path | Out-String)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { throw "ffprobe packet 读取失败，exit=$exitCode，path=$Path" }
  $keyframes = @($raw -split "`r?`n" | ForEach-Object {
      $parts = $_ -split ',', 2
      if ($parts.Count -eq 2 -and $parts[1] -match 'K') {
        [double]::Parse($parts[0], [System.Globalization.CultureInfo]::InvariantCulture)
      }
    } | Sort-Object)
  if ($keyframes.Count -lt 2) {
    throw "QA 素材关键帧不足，无法验证 GOP：$Path"
  }
  $intervals = @()
  for ($index = 1; $index -lt $keyframes.Count; $index++) {
    $intervals += [double]$keyframes[$index] - [double]$keyframes[$index - 1]
  }
  [ordered]@{
    keyframeCount = $keyframes.Count
    minKeyframeIntervalSeconds = [Math]::Round([double](($intervals | Measure-Object -Minimum).Minimum), 3)
    maxKeyframeIntervalSeconds = [Math]::Round([double](($intervals | Measure-Object -Maximum).Maximum), 3)
  }
}

function Get-VerifiedVideo {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][int]$ExpectedWidth,
    [Parameter(Mandatory = $true)][int]$ExpectedHeight,
    [Parameter(Mandatory = $true)][ValidateSet('short-gop', 'long-gop')][string]$ExpectedGop
  )
  $probe = Get-FfprobeJson -Path $Path -Arguments @(
    '-v', 'error',
    '-select_streams', 'v:0',
    '-show_entries', 'stream=codec_name,width,height,bit_rate,duration',
    '-of', 'json'
  )
  $stream = @($probe.streams) | Select-Object -First 1
  if ($null -eq $stream) { throw "QA 素材缺少视频流：$Path" }
  if ([string]$stream.codec_name -ne 'av1' -or
      [int]$stream.width -ne $ExpectedWidth -or
      [int]$stream.height -ne $ExpectedHeight) {
    throw "QA 素材 codec/分辨率不符合合同：$Path"
  }
  $duration = [double]$stream.duration
  if ($duration -lt ($DurationSeconds - 1)) {
    throw "QA 素材时长不足：$Path，实际=${duration}s"
  }
  $bitrate = [double]$stream.bit_rate
  $minimumBitrate = if ($ExpectedWidth -eq 1920) { 2000000 } else { 10000000 }
  if ($bitrate -lt $minimumBitrate) {
    throw "QA 素材码率不足：$Path，实际=${bitrate}bps，最低=${minimumBitrate}bps"
  }
  $keyframe = Get-KeyframeEvidence -Path $Path
  if ($ExpectedGop -eq 'short-gop' -and
      $keyframe.maxKeyframeIntervalSeconds -gt 1.1) {
    throw "QA 素材不是 short GOP：$Path，最大间隔=$($keyframe.maxKeyframeIntervalSeconds)s"
  }
  if ($ExpectedGop -eq 'long-gop' -and
      $keyframe.maxKeyframeIntervalSeconds -lt 4.0) {
    throw "QA 素材不是 long GOP：$Path，最大间隔=$($keyframe.maxKeyframeIntervalSeconds)s"
  }
  [ordered]@{
    path = $Path
    codec = [string]$stream.codec_name
    width = [int]$stream.width
    height = [int]$stream.height
    bitrateKbps = [Math]::Round($bitrate / 1000.0, 1)
    durationSeconds = [Math]::Round($duration, 3)
    minKeyframeIntervalSeconds = $keyframe.minKeyframeIntervalSeconds
    maxKeyframeIntervalSeconds = $keyframe.maxKeyframeIntervalSeconds
    keyframeCountInProbeWindow = $keyframe.keyframeCount
  }
}

function Set-ManifestCaseProperty {
  param(
    [Parameter(Mandatory = $true)][object]$Case,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowNull()][object]$Value
  )
  $property = $Case.PSObject.Properties[$Name]
  if ($null -eq $property) {
    $Case | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  } else {
    $property.Value = $Value
  }
}

$ffmpegPath = Resolve-RequiredCommand -Name 'ffmpeg'
$ffprobePath = Resolve-RequiredCommand -Name 'ffprobe'
$shortSourcePath = [System.IO.Path]::GetFullPath($ShortSource)
$longSourcePath = [System.IO.Path]::GetFullPath($LongSource)
$sourceManifestPath = [System.IO.Path]::GetFullPath($SourceManifest)
$fixtureRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $shortSourcePath -PathType Leaf)) {
  throw "1080p AV1 源素材不存在：$shortSourcePath"
}
if (-not (Test-Path -LiteralPath $longSourcePath -PathType Leaf)) {
  throw "4K AV1 源素材不存在：$longSourcePath"
}
if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) {
  throw "源 manifest 不存在：$sourceManifestPath"
}
if (Test-Path -LiteralPath $fixtureRoot) {
  throw "拒绝覆盖既有 QA fixture 目录：$fixtureRoot"
}
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

$shortOutput = Join-Path $fixtureRoot '1080p-av1-short-gop.mp4'
$longOutput = Join-Path $fixtureRoot '4k-av1-long-gop.mp4'
$shortLog = Join-Path $fixtureRoot '1080p-av1-short-gop.ffmpeg.log'
$longLog = Join-Path $fixtureRoot '4k-av1-long-gop.ffmpeg.log'

# 只生成短时隔离样本；关键帧强制间隔与码率参数写入脚本，确保同机复跑可解释。
Invoke-Ffmpeg -LogPath $shortLog -Arguments @(
  '-hide_banner', '-loglevel', 'warning', '-y',
  '-i', $shortSourcePath,
  '-t', "$DurationSeconds",
  '-map', '0:v:0', '-map', '0:a:0?',
  '-c:v', 'av1_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', '20',
  # 1080p fixture 沿用本机已知可播放的 AV1 level，避免把 QA 素材自身变成
  # 不受当前解码器支持的 level 实验。
  '-level', '8',
  '-b:v', '8M', '-maxrate', '12M', '-bufsize', '24M',
  '-g', '60', '-forced-idr', '1',
  '-force_key_frames', 'expr:gte(t,n_forced*1)',
  '-c:a', 'aac', '-b:a', '192k',
  '-movflags', '+faststart',
  $shortOutput
)
Invoke-Ffmpeg -LogPath $longLog -Arguments @(
  '-hide_banner', '-loglevel', 'warning', '-y',
  '-i', $longSourcePath,
  '-t', "$DurationSeconds",
  '-map', '0:v:0', '-map', '0:a:0?',
  '-c:v', 'av1_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', '19',
  # 4K/60 fixture 沿用本机已知可播放的 AV1 level，同时把 GOP 明确延长到 5 秒。
  '-level', '13',
  '-b:v', '20M', '-maxrate', '35M', '-bufsize', '70M',
  '-g', '300', '-forced-idr', '1',
  '-force_key_frames', 'expr:gte(t,n_forced*5)',
  '-c:a', 'aac', '-b:a', '192k',
  '-movflags', '+faststart',
  $longOutput
)

$shortEvidence = Get-VerifiedVideo -Path $shortOutput -ExpectedWidth 1920 -ExpectedHeight 1080 -ExpectedGop 'short-gop'
$longEvidence = Get-VerifiedVideo -Path $longOutput -ExpectedWidth 3840 -ExpectedHeight 2160 -ExpectedGop 'long-gop'
$manifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json
$shortCase = @($manifest.cases | Where-Object id -eq '1080p-av1-short-gop') | Select-Object -First 1
$longCase = @($manifest.cases | Where-Object id -eq '4k-av1-long-gop') | Select-Object -First 1
if ($null -eq $shortCase -or $null -eq $longCase) {
  throw '源 manifest 缺少预期的两个 AV1 case。'
}
foreach ($entry in @(
    [ordered]@{ case = $shortCase; evidence = $shortEvidence; gop = 'short-gop'; budget = 500 },
    [ordered]@{ case = $longCase; evidence = $longEvidence; gop = 'long-gop'; budget = 1200 }
  )) {
  $case = $entry.case
  $evidence = $entry.evidence
  Set-ManifestCaseProperty $case 'path' ([string]$evidence.path)
  Set-ManifestCaseProperty $case 'codec' 'av1'
  Set-ManifestCaseProperty $case 'width' ([int]$evidence.width)
  Set-ManifestCaseProperty $case 'height' ([int]$evidence.height)
  Set-ManifestCaseProperty $case 'gop' ([string]$entry.gop)
  Set-ManifestCaseProperty $case 'p95BudgetMs' ([int]$entry.budget)
  Set-ManifestCaseProperty $case 'bitrateKbps' $evidence.bitrateKbps
  Set-ManifestCaseProperty $case 'durationSeconds' $evidence.durationSeconds
  Set-ManifestCaseProperty $case 'maxKeyframeIntervalSeconds' $evidence.maxKeyframeIntervalSeconds
  Set-ManifestCaseProperty $case 'selectionStatus' 'qa-generated-fixture-and-ffprobe-verified'
  Set-ManifestCaseProperty $case 'selectionEvidence' ([ordered]@{
    sourceKind = 'controlled-local-qa-fixture'
    generatedBy = 'prepare_player_p0_av1_fixture_manifest.ps1'
    sourcePathOmittedFromReport = $true
    keyframeCountInProbeWindow = $evidence.keyframeCountInProbeWindow
    minKeyframeIntervalSeconds = $evidence.minKeyframeIntervalSeconds
    maxKeyframeIntervalSeconds = $evidence.maxKeyframeIntervalSeconds
  })
}
$manifest.status = 'partial'
$manifest.source = 'readonly-library-db-plus-controlled-av1-qa-fixture-and-ffprobe'
$manifest.generatedAt = (Get-Date).ToUniversalTime().ToString('o')
if (-not [string]::IsNullOrWhiteSpace($DebugExecutable)) {
  $debugExecutablePath = [System.IO.Path]::GetFullPath($DebugExecutable)
  if (-not (Test-Path -LiteralPath $debugExecutablePath -PathType Leaf)) {
    throw "Debug 可执行文件不存在：$debugExecutablePath"
  }
  if ($null -eq $manifest.build) { $manifest.build = [ordered]@{} }
  $manifest.build.executableSha256 = (Get-FileHash -LiteralPath $debugExecutablePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifest.build.configuration = 'Debug'
  $manifest.build.surface = 'mediaKit-texture'
  $manifest.build.evidenceKind = 'desktop-composited-pixel-change'
}
$manifestPath = Join-Path $fixtureRoot 'player_p0_manifest-with-av1-fixtures.json'
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
$summary = [ordered]@{
  evidence = 'controlled-local-av1-p0-fixtures'
  outputDirectory = $fixtureRoot
  manifest = $manifestPath
  durationSeconds = $DurationSeconds
  cases = [ordered]@{
    '1080p-av1-short-gop' = $shortEvidence
    '4k-av1-long-gop' = $longEvidence
  }
  sourcePathsOmittedFromSummary = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $fixtureRoot 'fixture-summary.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 20
