param(
  [Parameter(Mandatory = $true)]
  [string]$RuntimeDirectory,
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Debug',
  [string]$SamplePath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build\windows\x64'
$configurationFlag = if ($Configuration -eq 'Debug') { '--debug' } else { '--release' }
$runtimePath = [System.IO.Path]::GetFullPath($RuntimeDirectory)
$scriptPath = Join-Path $repoRoot 'tool\vapoursynth_passthrough_probe.vpy'
$flutterCommand = (Get-Command flutter.bat -ErrorAction Stop).Source
$cmakeCommand = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if ([string]::IsNullOrWhiteSpace($cmakeCommand)) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path -LiteralPath $vswhere) {
    $cmakeCommand = & $vswhere -latest -products * `
      -requires Microsoft.VisualStudio.Component.VC.CMake.Project `
      -find 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' |
      Select-Object -First 1
  }
}
if ([string]::IsNullOrWhiteSpace($cmakeCommand)) {
  throw 'CMake was not found. Install the Visual Studio C++ CMake tools.'
}
if (-not (Test-Path -LiteralPath (Join-Path $runtimePath 'VSScript.dll'))) {
  throw "VSScript.dll is missing from the runtime directory: $runtimePath"
}
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  throw "Pass-through script is missing: $scriptPath"
}

Push-Location $repoRoot
try {
  & $flutterCommand build windows $configurationFlag
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows configuration failed with exit code $LASTEXITCODE"
  }

  & $cmakeCommand -S windows -B $buildRoot -DLTP_BUILD_VAPOURSYNTH_MOTION_PROBE=ON
  if ($LASTEXITCODE -ne 0) {
    throw "VapourSynth probe configuration failed with exit code $LASTEXITCODE"
  }
  & $cmakeCommand --build $buildRoot --config $Configuration `
    --target ltp_vapoursynth_real_frame_probe
  if ($LASTEXITCODE -ne 0) {
    throw "VapourSynth real-frame probe build failed with exit code $LASTEXITCODE"
  }

  if ([string]::IsNullOrWhiteSpace($SamplePath)) {
    $sampleDirectory = Join-Path $repoRoot 'build\vapoursynth-real-frame-probe'
    New-Item -ItemType Directory -Force -Path $sampleDirectory | Out-Null
    $sample = Join-Path $sampleDirectory 'synthetic-24fps.mp4'
    $ffmpeg = Join-Path $repoRoot 'windows\tools\ffmpeg\bin\ffmpeg.exe'
    if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) {
      throw "Pinned FFmpeg is missing: $ffmpeg"
    }
    & $ffmpeg -hide_banner -loglevel error -f lavfi `
      -i 'testsrc2=size=320x180:rate=24:duration=6' `
      -c:v libx264 -preset ultrafast -pix_fmt yuv420p `
      -movflags +faststart -y $sample
    if ($LASTEXITCODE -ne 0) {
      throw "Synthetic sample generation failed with exit code $LASTEXITCODE"
    }
  } else {
    $sample = [System.IO.Path]::GetFullPath($SamplePath)
  }
  if (-not (Test-Path -LiteralPath $sample -PathType Leaf)) {
    throw "Probe sample is missing: $sample"
  }

  $probeDirectory = Join-Path $buildRoot 'vapoursynth_motion_probe'
  $probe = Join-Path $probeDirectory 'ltp_vapoursynth_real_frame_probe.exe'
  $runnerDirectory = Join-Path $buildRoot "runner\$Configuration"
  $mpvRuntime = Join-Path $runnerDirectory 'libmpv-2.dll'
  $probeMpvRuntime = Join-Path $probeDirectory 'libmpv-2.dll'
  if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
    throw "Real-frame probe output is missing: $probe"
  }
  if (-not (Test-Path -LiteralPath $mpvRuntime -PathType Leaf)) {
    throw "Pinned libmpv runtime is missing: $mpvRuntime"
  }
  # Windows 子 PowerShell 不稳定继承临时 DLL 搜索 PATH；把固定 DLL 放入纯 QA
  # 输出目录可得到确定性装载，同时不会进入 runner bundle 或应用安装目录。
  Copy-Item -LiteralPath $mpvRuntime -Destination $probeMpvRuntime -Force
  if (-not (Test-Path -LiteralPath $probeMpvRuntime -PathType Leaf)) {
    throw "Pinned libmpv copy is missing: $probeMpvRuntime"
  }
  & $probe $runtimePath $scriptPath $sample
  if ($LASTEXITCODE -ne 0) {
    throw "VapourSynth real-frame probe failed with exit code $LASTEXITCODE"
  }
  Write-Output 'VapourSynth real frames, seek, and reload passed.'
} finally {
  Pop-Location
}
