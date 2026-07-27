param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(300, 1200)]
  [int]$VideoBitrateKbps = 650,
  [string]$OutputDirectory = ".local/qa/natural-compression-ab",
  [switch]$SkipPlayback
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$output = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace $OutputDirectory)
)
$sourceDirectory = Join-Path $workspace ".local/qa/natural-sources"
$sampleDirectory = Join-Path $output "samples"
$ffmpeg = Join-Path $workspace "windows/tools/ffmpeg/bin/ffmpeg.exe"
$ffprobe = Join-Path $workspace "windows/tools/ffmpeg/bin/ffprobe.exe"
if (-not (Test-Path -LiteralPath $ffmpeg) -or
    -not (Test-Path -LiteralPath $ffprobe)) {
  throw "Bundled FFmpeg or FFprobe is unavailable."
}
New-Item -ItemType Directory -Force -Path `
  $output, $sourceDirectory, $sampleDirectory | Out-Null

<#
 * 自然片源只下载到 `.local/qa`，不进入仓库，也不读取用户媒体库。
 *
 * 两部 Blender Open Movie 均为 CC BY 3.0；报告保留原始下载地址、许可页和署名，
 * 方便复查样片来源。下载先写入 `.partial`，完成后才替换正式文件。
#>
function Receive-QaSource {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if ((Test-Path -LiteralPath $Destination) -and
      (Get-Item -LiteralPath $Destination).Length -gt 1MB) {
    return
  }
  $partial = "$Destination.partial"
  Invoke-WebRequest -Uri $Uri -UseBasicParsing -OutFile $partial `
    -TimeoutSec 900
  Move-Item -LiteralPath $partial -Destination $Destination -Force
}

$sintelUri =
  "https://download.blender.org/durian/trailer/sintel_trailer-1080p.mp4"
$tearsArchiveUri =
  "https://download.blender.org/demo/movies/tears-of-steel_teaser.mp4.zip"
$sintelPath = Join-Path $sourceDirectory "sintel-trailer-1080p.mp4"
$tearsArchivePath = Join-Path $sourceDirectory "tears-of-steel-teaser.zip"
$tearsPath = Join-Path $sourceDirectory "tears-of-steel_teaser.mp4"
Receive-QaSource -Uri $sintelUri -Destination $sintelPath
Receive-QaSource -Uri $tearsArchiveUri -Destination $tearsArchivePath
if (-not (Test-Path -LiteralPath $tearsPath)) {
  Expand-Archive -LiteralPath $tearsArchivePath `
    -DestinationPath $sourceDirectory -Force
}
if (-not (Test-Path -LiteralPath $tearsPath)) {
  throw "Tears of Steel teaser was not found after extraction."
}

<#
 * 每类内容先截取短的高质量参考段，再无缝循环到统一时长并压为低码率 1080P。
 *
 * 参考段选择让第 12 秒固定帧分别落在面部、暖色天空渐变和暗部人物上；统一压制
 * 参数避免编码器差异污染关闭/清晰增强的播放器 A/B。
#>
$cases = @(
  [ordered]@{
    name = "live-face"
    category = "live-action face"
    source = $tearsPath
    sourceName = "Tears of Steel teaser"
    startSeconds = 0
    segmentSeconds = 5
    sourceUri = $tearsArchiveUri
    licenseUri = "https://mango.blender.org/about/"
    attribution = "Tears of Steel (c) Blender Foundation | mango.blender.org"
  },
  [ordered]@{
    name = "animation-gradient"
    category = "animated gradient"
    source = $sintelPath
    sourceName = "Sintel trailer"
    startSeconds = 31
    segmentSeconds = 10
    sourceUri = $sintelUri
    licenseUri = "https://durian.blender.org/sharing"
    attribution = "Sintel (c) Blender Foundation | durian.blender.org"
  },
  [ordered]@{
    name = "dark-scene"
    category = "dark scene"
    source = $tearsPath
    sourceName = "Tears of Steel teaser"
    startSeconds = 30.7
    segmentSeconds = 2.1
    sourceUri = $tearsArchiveUri
    licenseUri = "https://mango.blender.org/about/"
    attribution = "Tears of Steel (c) Blender Foundation | mango.blender.org"
  }
)

foreach ($case in $cases) {
  $referencePath = Join-Path $sampleDirectory `
    "$($case.name)-reference.mp4"
  $samplePath = Join-Path $sampleDirectory `
    "$($case.name)-low-${VideoBitrateKbps}k.mp4"
  & $ffmpeg -hide_banner -loglevel error -y `
    -ss $case.startSeconds -i $case.source -t $case.segmentSeconds -an `
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,format=yuv420p" `
    -c:v libx264 -preset slow -crf 10 -g 48 `
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
    -color_range tv $referencePath
  if ($LASTEXITCODE -ne 0) {
    throw "Natural reference generation failed: $($case.name)"
  }
  & $ffmpeg -hide_banner -loglevel error -y `
    -stream_loop -1 -i $referencePath -t ($DurationSeconds + 15) -an `
    -c:v libx264 -preset slow `
    -b:v "$($VideoBitrateKbps)k" `
    -maxrate "$($VideoBitrateKbps + 100)k" `
    -bufsize "$($VideoBitrateKbps * 2)k" `
    -g 48 -keyint_min 48 -sc_threshold 0 `
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
    -color_range tv -movflags +faststart $samplePath
  if ($LASTEXITCODE -ne 0) {
    throw "Natural low bitrate generation failed: $($case.name)"
  }
  $case["samplePath"] = $samplePath
  $case["actualBitrate"] = [int](& $ffprobe -v error `
      -show_entries format=bit_rate `
      -of default=noprint_wrappers=1:nokey=1 $samplePath)
}

<#
 * 在真实 Windows MediaKit 窗口运行一个内容类别和一个增强档位。
#>
function Invoke-NaturalCompressionMode {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $modeOutput = Join-Path (Join-Path $output $Case.name) $Mode
  New-Item -ItemType Directory -Force -Path $modeOutput | Out-Null
  $env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH = $Case.samplePath
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT = $modeOutput
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE = $Mode
  $env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS = $DurationSeconds.ToString()
  try {
    Push-Location $workspace
    & flutter test integration_test/player_fixed_quality_baseline_test.dart `
      -d windows *>&1 |
      Tee-Object -FilePath (Join-Path $modeOutput "baseline.log")
    $testExitCode = $LASTEXITCODE
  } finally {
    Pop-Location
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE `
      -ErrorAction SilentlyContinue
    Remove-Item Env:LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS `
      -ErrorAction SilentlyContinue
  }
  if ($testExitCode -ne 0) {
    throw "Natural compression A/B failed: $($Case.name) / $Mode"
  }
}

if (-not $SkipPlayback) {
  foreach ($case in $cases) {
    Invoke-NaturalCompressionMode -Case $case -Mode "compression-off"
    Invoke-NaturalCompressionMode -Case $case -Mode "compression-clarity"
  }
}

<# 从匿名诊断时间序列提取可直接横向比较的压力上限。 #>
function Get-NaturalModeSummary {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Case,
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $reportPath = Join-Path `
    (Join-Path (Join-Path $output $Case.name) $Mode) `
    "$Mode-player-baseline.json"
  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
  $samples = @($report.samples)
  return [ordered]@{
    mode = $Mode
    sampleCount = $samples.Count
    maxDecoderDroppedFrames = ($samples |
        Measure-Object -Property decoderDroppedFrames -Maximum).Maximum
    maxOutputDroppedFrames = ($samples |
        Measure-Object -Property outputDroppedFrames -Maximum).Maximum
    maxTotalDroppedFrames = ($samples |
        Measure-Object -Property totalDroppedFrames -Maximum).Maximum
    videoStallSamples = @($samples |
        Where-Object { $_.videoStalled -eq $true }).Count
    audioStallSamples = @($samples |
        Where-Object { $_.audioStalled -eq $true }).Count
    finalDiagnostics = $report.finalDiagnostics
  }
}

$caseSummaries = foreach ($case in $cases) {
  [ordered]@{
    name = $case.name
    category = $case.category
    sourceName = $case.sourceName
    sourceUri = $case.sourceUri
    licenseUri = $case.licenseUri
    attribution = $case.attribution
    startSeconds = $case.startSeconds
    segmentSeconds = $case.segmentSeconds
    requestedVideoBitrateKbps = $VideoBitrateKbps
    actualBitrateKbps = [math]::Round($case.actualBitrate / 1000, 1)
    captureSecond = 12
    off = Get-NaturalModeSummary -Case $case -Mode "compression-off"
    clarity = Get-NaturalModeSummary `
      -Case $case -Mode "compression-clarity"
  }
}

$summary = [ordered]@{
  schemaVersion = 1
  samplePolicy = "isolated CC BY 3.0 open-movie excerpts"
  cases = @($caseSummaries)
  glslSharpenGate = [ordered]@{
    requirement =
      "all three natural categories must show stable visual benefit without performance regression"
    decision = "pending fixed-frame visual review; GLSL is not implemented"
  }
}
$summary | ConvertTo-Json -Depth 10 |
  Set-Content -LiteralPath `
    (Join-Path $output "natural-compression-ab-summary.json") `
    -Encoding utf8

Write-Host "Natural compression quality A/B completed: $output"
