param(
  [ValidateRange(20, 120)]
  [int]$DurationSeconds = 20,
  [ValidateRange(800, 12000)]
  [int]$VideoBitrateKbps = 6000,
  [string]$OutputDirectory = ".local/qa/nvofa-motion-stress/samples",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$output = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace $OutputDirectory)
)
$ffmpeg = Join-Path $workspace "windows/tools/ffmpeg/bin/ffmpeg.exe"
$ffprobe = Join-Path $workspace "windows/tools/ffmpeg/bin/ffprobe.exe"
if (-not (Test-Path -LiteralPath $ffmpeg) -or
    -not (Test-Path -LiteralPath $ffprobe)) {
  throw "Bundled FFmpeg or FFprobe is unavailable."
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

<#
 * 生成五类匿名、可复现的连续运动压力片段。
 *
 * 所有样本固定为 1080P/24fps SDR，不读取用户媒体，也不进入正式应用包。
 * 码率保持在足以观察插帧伪影的范围，避免压缩噪声主导结果。
#>
$fontPath = "C\:/Windows/Fonts/arial.ttf"
$cases = @(
  [ordered]@{
    name = "fast-pan"
    category = "快速横移"
    qualityFocus = "大位移、画面边界与显露区域"
    filter = "testsrc2=size=1920x1080:rate=24," +
      "scroll=horizontal=0.08:vertical=0,format=yuv420p"
  },
  [ordered]@{
    name = "fine-fence"
    category = "细栅栏"
    qualityFocus = "高频竖线、细节抖动与光流误配"
    filter = "color=c=0x202838:size=1920x1080:rate=24," +
      "geq=lum='if(lt(mod(X+N*3\,12)\,2)\,220\,32)':" +
      "cb=128:cr=128,format=yuv420p"
  },
  [ordered]@{
    name = "subtitles"
    category = "固定字幕"
    qualityFocus = "静态文字边缘与运动背景的分层"
    filter = "testsrc2=size=1920x1080:rate=24," +
      "scroll=horizontal=0.04:vertical=0," +
      "drawbox=x=160:y=820:w=1600:h=150:" +
      "color=black@0.72:t=fill," +
      "drawtext=fontfile='$fontPath':" +
      "text='LOCAL TAG PLAYER  /  MOTION TEST':" +
      "fontcolor=white:fontsize=54:x=(w-text_w)/2:y=860," +
      "format=yuv420p"
  },
  [ordered]@{
    name = "motion-blur"
    category = "运动模糊"
    qualityFocus = "模糊轮廓、重影与过度锐利边缘"
    filter = "testsrc2=size=1920x1080:rate=24," +
      "scroll=horizontal=0.09:vertical=0," +
      "tmix=frames=5:weights='1 1 1 1 1',format=yuv420p"
  },
  [ordered]@{
    name = "scene-cut"
    category = "重复场景切换"
    qualityFocus = "切镜保护与跨场景错误合成"
    # 让 12.020833 秒恰好落在切镜两侧源帧之间，匹配播放器固定奇数帧采证。
    filter = "nullsrc=size=1920x1080:rate=24," +
      "geq=lum='if(lt(mod(T+3.9583333\,4)\,2)\," +
      "32+mod(X+Y\,96)\,128+mod(3*X+2*Y\,96))':" +
      "cb='96+mod(X\,64)':cr='160-mod(Y\,64)',format=yuv420p"
  }
)

<# 只复用规格和时长均满足门禁的既有 QA 样本。 #>
function Test-StressSample {
  param([string]$Path, [int]$MinimumSeconds)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  try {
    $probe = & $ffprobe -v error -select_streams v:0 `
      -show_entries stream=width,height,r_frame_rate `
      -show_entries format=duration -of json $Path |
      ConvertFrom-Json
    $stream = @($probe.streams)[0]
    return $stream.width -eq 1920 -and
      $stream.height -eq 1080 -and
      $stream.r_frame_rate -eq "24/1" -and
      [double]$probe.format.duration -ge ($MinimumSeconds - 0.5)
  } catch {
    return $false
  }
}

$sampleSeconds = $DurationSeconds + 15
foreach ($case in $cases) {
  $samplePath = Join-Path $output "$($case.name)-1080p24.mp4"
  if ($Force -or -not (Test-StressSample $samplePath $sampleSeconds)) {
    $partialPath = "$samplePath.partial.mp4"
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    & $ffmpeg -hide_banner -loglevel error -y `
      -f lavfi -i $case.filter -t $sampleSeconds -an `
      -c:v libx264 -preset medium `
      -b:v "$($VideoBitrateKbps)k" `
      -maxrate "$($VideoBitrateKbps)k" `
      -bufsize "$($VideoBitrateKbps * 2)k" `
      -g 48 -keyint_min 48 -sc_threshold 0 `
      -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
      -color_range tv -movflags +faststart $partialPath
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-StressSample $partialPath $sampleSeconds)) {
      throw "NVOFA 连续压力样本生成失败：$($case.name)"
    }
    Move-Item -LiteralPath $partialPath -Destination $samplePath -Force
  }
  $case["samplePath"] = $samplePath
}

$manifest = [ordered]@{
  schemaVersion = 1
  samplePolicy =
    "deterministic anonymous 1080p24 continuous-motion clips; local QA only"
  durationSeconds = $sampleSeconds
  videoBitrateKbps = $VideoBitrateKbps
  cases = @($cases | ForEach-Object {
      [ordered]@{
        name = $_.name
        category = $_.category
        qualityFocus = $_.qualityFocus
        samplePath = $_.samplePath
      }
    })
}
$manifestPath = Join-Path $output "manifest.json"
$manifest | ConvertTo-Json -Depth 8 |
  Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "NVOFA continuous stress samples: $manifestPath"
