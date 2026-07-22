param(
  [string]$OutputDirectory = ".local/qa/fixed-samples",
  [ValidateRange(30, 1800)]
  [int]$HdrDurationSeconds = 360,
  [ValidateRange(30, 1800)]
  [int]$SdrDurationSeconds = 240,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$requestedOutput = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
  $OutputDirectory
} else {
  Join-Path $workspace $OutputDirectory
}
$output = [System.IO.Path]::GetFullPath($requestedOutput)
$ffmpeg = Join-Path $workspace "windows/tools/ffmpeg/bin/ffmpeg.exe"
$ffprobe = Join-Path $workspace "windows/tools/ffmpeg/bin/ffprobe.exe"
if (-not (Test-Path -LiteralPath $ffmpeg) -or
    -not (Test-Path -LiteralPath $ffprobe)) {
  throw "Bundled FFmpeg or FFprobe is unavailable."
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

$hdrPath = Join-Path $output "fixed-hdr10-pq-1080p.mp4"
$sdrPath = Join-Path $output "fixed-sdr-dark-1080p.mp4"

<# 复用已有样本前验证时长，防止短冒烟文件被误用于更长基线。 #>
function Test-SampleDuration {
  param([string]$Path, [int]$MinimumSeconds)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $duration = & $ffprobe -v error -show_entries format=duration `
      -of default=noprint_wrappers=1:nokey=1 $Path
    return ([double]$duration -ge ($MinimumSeconds - 0.5))
  } catch {
    return $false
  }
}

<#
  固定 HDR 样本把确定性移动测试图从 BT.709 转换到 BT.2020/PQ，并写入
  Mastering Display 与 MaxCLL；样本只进入 .local QA，不包含用户媒体。
#>
if ($Force -or -not (Test-SampleDuration $hdrPath $HdrDurationSeconds)) {
  $hdrTemporary = Join-Path $output "fixed-hdr10-pq-1080p.partial.mp4"
  Remove-Item -LiteralPath $hdrTemporary -Force -ErrorAction SilentlyContinue
  $hdrFilter = "testsrc2=size=1920x1080:rate=30," +
    "format=gbrpf32le," +
    "zscale=primariesin=bt709:transferin=bt709:matrixin=gbr:" +
    "primaries=bt2020:transfer=smpte2084:matrix=bt2020nc:" +
    "range=limited:npl=1000,format=yuv420p10le"
  $x265 = "log-level=error:hdr10=1:repeat-headers=1:" +
    "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:" +
    "master-display=G(13250,34500)B(7500,3000)R(34000,16000)" +
    "WP(15635,16450)L(10000000,50):max-cll=1000,400"
  & $ffmpeg -hide_banner -loglevel error -y `
    -f lavfi -i $hdrFilter `
    -t $HdrDurationSeconds -an `
    -c:v libx265 -preset ultrafast -x265-params $x265 `
    -tag:v hvc1 -movflags +faststart `
    -metadata title="Local Tag Player fixed HDR10 QA sample" `
    $hdrTemporary
  if ($LASTEXITCODE -ne 0) {
    throw "Fixed HDR sample generation failed: $LASTEXITCODE"
  }
  if (-not (Test-SampleDuration $hdrTemporary $HdrDurationSeconds)) {
    throw "Generated HDR sample failed validation."
  }
  Move-Item -LiteralPath $hdrTemporary -Destination $hdrPath -Force
}

<#
  SDR 暗场样本包含低亮度水平渐变、相邻灰阶块和缓慢移动亮块，用于单独观察
  黑位、暗部纹理、色带与性能；它不启用任何播放器暗部增强。
#>
if ($Force -or -not (Test-SampleDuration $sdrPath $SdrDurationSeconds)) {
  $sdrTemporary = Join-Path $output "fixed-sdr-dark-1080p.partial.mp4"
  Remove-Item -LiteralPath $sdrTemporary -Force -ErrorAction SilentlyContinue
  $sdrFilter = "gradients=size=1920x1080:rate=30:" +
    "c0=0x000000:c1=0x282828:x0=0:y0=0:x1=1920:y1=0:speed=0," +
    "drawbox=x=120:y=160:w=280:h=180:color=0x080808:t=fill," +
    "drawbox=x=430:y=160:w=280:h=180:color=0x101010:t=fill," +
    "drawbox=x=740:y=160:w=280:h=180:color=0x181818:t=fill," +
    "drawbox=x='mod(t*90,1700)':y=720:w=220:h=120:color=0x303030:t=fill," +
    "format=yuv420p"
  & $ffmpeg -hide_banner -loglevel error -y `
    -f lavfi -i $sdrFilter `
    -t $SdrDurationSeconds -an `
    -c:v libx264 -preset ultrafast -crf 18 `
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
    -color_range tv -movflags +faststart `
    -metadata title="Local Tag Player fixed SDR dark QA sample" `
    $sdrTemporary
  if ($LASTEXITCODE -ne 0) {
    throw "Fixed SDR sample generation failed: $LASTEXITCODE"
  }
  if (-not (Test-SampleDuration $sdrTemporary $SdrDurationSeconds)) {
    throw "Generated SDR sample failed validation."
  }
  Move-Item -LiteralPath $sdrTemporary -Destination $sdrPath -Force
}

if (-not (Test-SampleDuration $hdrPath $HdrDurationSeconds) -or
    -not (Test-SampleDuration $sdrPath $SdrDurationSeconds)) {
  throw "Fixed quality sample validation failed."
}

<# 保存不含本机路径的媒体属性，确保后续长播始终复用相同规格。 #>
$manifest = [ordered]@{
  schemaVersion = 1
  hdr = & $ffprobe -v error -select_streams v:0 `
    -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,color_range,color_space,color_transfer,color_primaries,duration `
    -of json $hdrPath | ConvertFrom-Json
  sdrDark = & $ffprobe -v error -select_streams v:0 `
    -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,color_range,color_space,color_transfer,color_primaries,duration `
    -of json $sdrPath | ConvertFrom-Json
}
$manifest | ConvertTo-Json -Depth 8 |
  Set-Content -LiteralPath (Join-Path $output "sample-manifest.json") -Encoding utf8

Write-Host "Fixed quality samples are ready: $output"
