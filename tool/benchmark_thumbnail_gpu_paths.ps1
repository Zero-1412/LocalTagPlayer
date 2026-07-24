param(
  [Parameter(Mandatory = $true)]
  [string[]]$InputPath,
  [string]$Ffmpeg = '.\windows\tools\ffmpeg\bin\ffmpeg.exe',
  [string]$Ffprobe = '.\windows\tools\ffmpeg\bin\ffprobe.exe',
  [ValidateRange(1, 20)]
  [int]$Rounds = 5,
  [string]$Output = '.\artifacts\ffmpeg_thumbnail_gpu_ab.json'
)

$ErrorActionPreference = 'Stop'
$Output = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
$outputDirectory = Split-Path -Parent $Output
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$scratch = Join-Path $outputDirectory 'ffmpeg_thumbnail_gpu_ab_scratch'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

<# 运行与产品缩略图一致的单帧输出；GPU 路径失败也记录退出码，不静默回退。 #>
function Invoke-ThumbnailCase {
  param(
    [string]$Mode,
    [string]$Source,
    [string]$Destination
  )
  $arguments = @('-hide_banner', '-loglevel', 'error', '-threads', '1',
    '-ss', '2', '-noaccurate_seek')
  if ($Mode -eq 'd3d11_decode') {
    $arguments += @('-hwaccel', 'd3d11va', '-hwaccel_output_format', 'd3d11')
  } elseif ($Mode -eq 'd3d12_scale') {
    $arguments += @('-hwaccel', 'd3d12va', '-hwaccel_output_format', 'd3d12')
  }
  $arguments += @('-i', $Source, '-map', '0:v:0', '-frames:v', '1')
  if ($Mode -eq 'software') {
    $arguments += @('-vf', 'scale=384:-2')
  } elseif ($Mode -eq 'd3d11_decode') {
    <# 当前 FFmpeg 8.1 构建的 scale_d3d11 无法创建缩略图纹理，因此只测硬解加 CPU 缩放。 #>
    $arguments += @('-vf', 'hwdownload,format=nv12,scale=384:-2')
  } else {
    $arguments += @('-vf', 'scale_d3d12=w=384:h=-2,hwdownload,format=nv12,format=yuvj420p')
  }
  $arguments += @('-q:v', '4', '-y', $Destination)
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  & $Ffmpeg @arguments 2>$null
  $exitCode = $LASTEXITCODE
  $stopwatch.Stop()
  [pscustomobject]@{
    elapsedMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
    exitCode = $exitCode
  }
}

$results = @()
for ($sampleIndex = 0; $sampleIndex -lt $InputPath.Count; $sampleIndex++) {
  $source = (Resolve-Path -LiteralPath $InputPath[$sampleIndex]).Path
  $probe = & $Ffprobe -v error -select_streams v:0 `
    -show_entries stream=codec_name,width,height,pix_fmt -of json $source |
    ConvertFrom-Json
  $stream = $probe.streams | Select-Object -First 1
  foreach ($mode in @('software', 'd3d11_decode', 'd3d12_scale')) {
    $samples = @()
    for ($round = 0; $round -le $Rounds; $round++) {
      $destination = Join-Path $scratch "sample-$sampleIndex-$mode.jpg"
      $measurement = Invoke-ThumbnailCase -Mode $mode -Source $source -Destination $destination
      <# 第一轮只负责预热进程外的文件系统缓存，不计入稳定样本。 #>
      if ($round -gt 0) { $samples += $measurement }
    }
    $successful = @($samples | Where-Object exitCode -eq 0)
    $times = @($successful | ForEach-Object elapsedMs | Sort-Object)
    $results += [pscustomobject]@{
      sample = "sample-$($sampleIndex + 1)"
      codec = $stream.codec_name
      width = $stream.width
      height = $stream.height
      pixelFormat = $stream.pix_fmt
      mode = $mode
      rounds = $Rounds
      successfulRounds = $successful.Count
      medianMs = if ($times.Count) { $times[[math]::Floor($times.Count / 2)] } else { $null }
      minMs = if ($times.Count) { $times[0] } else { $null }
      maxMs = if ($times.Count) { $times[-1] } else { $null }
      exitCodes = @($samples | ForEach-Object exitCode)
    }
  }
}

[pscustomobject]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  ffmpegVersion = (& $Ffmpeg -version | Select-Object -First 1)
  thumbnailWidth = 384
  results = $results
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Output -Encoding utf8

Get-Content -LiteralPath $Output
