param(
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Debug",
  [string]$RuntimeDirectory = "",
  [string]$SamplePath = "",
  [switch]$PerformanceGate
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repositoryRoot "build\windows\x64"
$headerCommit = "edb50da3cf849840d680249aa6dbef248ebce2ca"
$headerDirectory = Join-Path $repositoryRoot "build\nvofa-public-headers\$headerCommit"
$runtimePath = if ([string]::IsNullOrWhiteSpace($RuntimeDirectory)) {
  Join-Path $repositoryRoot `
    "build\vapoursynth-r78\installed\Lib\site-packages\vapoursynth"
} else {
  [System.IO.Path]::GetFullPath($RuntimeDirectory)
}
$vapoursynthInclude = Join-Path $runtimePath "include"
$scriptPath = Join-Path $repositoryRoot "tool\vapoursynth_nvofa_interpolation.vpy"

<#
  本脚本构建并实测“不分发厂商文件”的本机 NVOFA/VapourSynth 原型。

  官方公开头文件只下载到被忽略的 build 目录；插件、VapourSynth 和探针均无
  install 规则。成功必须同时满足真实 NVOFA execute、2× estimated-vf-fps、
  seek、同进程 reload 和确定性关闭。
#>
if (-not (Test-Path -LiteralPath (Join-Path $runtimePath "VSScript.dll"))) {
  throw "VapourSynth R78 runtime is missing: $runtimePath"
}
if (-not (Test-Path -LiteralPath (Join-Path $vapoursynthInclude "VapourSynth4.h"))) {
  throw "VapourSynth4.h is missing: $vapoursynthInclude"
}
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  throw "NVOFA interpolation script is missing: $scriptPath"
}

# 复用固定提交和 SHA-256 下载逻辑，并先证明当前驱动仍能实际 execute。
& (Join-Path $PSScriptRoot "run_nvofa_execute_probe.ps1") -Configuration $Configuration

$visualStudio = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
  -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
if ([string]::IsNullOrWhiteSpace($visualStudio)) {
  throw "Visual Studio C++ toolchain was not found."
}
$cmake = Join-Path $visualStudio `
  "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path -LiteralPath $cmake)) {
  $cmake = "cmake"
}

$configureArguments = @(
  "-S", (Join-Path $repositoryRoot "windows"),
  "-B", $buildRoot,
  "-DLTP_BUILD_VAPOURSYNTH_MOTION_PROBE=ON",
  "-DLTP_BUILD_NVOFA_EXECUTE_PROBE=ON",
  "-DLTP_BUILD_NVOFA_VAPOURSYNTH_PLUGIN=ON",
  "-DLTP_NVOFA_PUBLIC_HEADER_DIR=$headerDirectory",
  "-DLTP_VAPOURSYNTH_INCLUDE_DIR=$vapoursynthInclude"
)
& $cmake @configureArguments
if ($LASTEXITCODE -ne 0) {
  throw "NVOFA VapourSynth CMake configure failed with exit code $LASTEXITCODE."
}
& $cmake --build $buildRoot --config $Configuration `
  --target ltp_nvofa_vapoursynth_plugin `
    ltp_d3d11_midpoint_warper_probe `
    ltp_vapoursynth_real_frame_probe
if ($LASTEXITCODE -ne 0) {
  throw "NVOFA VapourSynth build failed with exit code $LASTEXITCODE."
}

$probeDirectory = Join-Path $buildRoot "vapoursynth_motion_probe"
$nvofaDirectory = Join-Path $buildRoot "nvidia_optical_flow_probe"
$probe = Join-Path $probeDirectory "ltp_vapoursynth_real_frame_probe.exe"
$plugin = Join-Path $nvofaDirectory "ltp_nvofa_vapoursynth.dll"
$warperProbe = Join-Path $nvofaDirectory `
  "ltp_d3d11_midpoint_warper_probe.exe"
$runnerDirectory = Join-Path $buildRoot "runner\$Configuration"
$mpvRuntime = Join-Path $runnerDirectory "libmpv-2.dll"
$probeMpvRuntime = Join-Path $probeDirectory "libmpv-2.dll"
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
  throw "VapourSynth real-frame probe was not produced: $probe"
}
if (-not (Test-Path -LiteralPath $plugin -PathType Leaf)) {
  throw "NVOFA VapourSynth plugin was not produced: $plugin"
}
if (-not (Test-Path -LiteralPath $warperProbe -PathType Leaf)) {
  throw "D3D11 midpoint warper probe was not produced: $warperProbe"
}
if (-not (Test-Path -LiteralPath $mpvRuntime -PathType Leaf)) {
  throw "Pinned libmpv runtime is missing: $mpvRuntime"
}
Copy-Item -LiteralPath $mpvRuntime -Destination $probeMpvRuntime -Force

$warperResult = & $warperProbe
if ($LASTEXITCODE -ne 0 -or
    (@($warperResult) -join "`n") -notmatch
      "d3d11-warp-occlusion=passed.*vector-infill=90.*image-hole-fill=201") {
  throw "D3D11 occlusion and hole-fill probe failed.`n$warperResult"
}
$warperResult

if ([string]::IsNullOrWhiteSpace($SamplePath)) {
  $sampleDirectory = Join-Path $repositoryRoot `
    "build\nvofa-vapoursynth-interpolation"
  New-Item -ItemType Directory -Force -Path $sampleDirectory | Out-Null
  $sample = Join-Path $sampleDirectory "synthetic-24fps.mp4"
  $ffmpeg = Join-Path $repositoryRoot "windows\tools\ffmpeg\bin\ffmpeg.exe"
  if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) {
    throw "Pinned FFmpeg is missing: $ffmpeg"
  }
  & $ffmpeg -hide_banner -loglevel error -f lavfi `
    -i "testsrc2=size=320x192:rate=24:duration=6" `
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p `
    -movflags +faststart -y $sample
  if ($LASTEXITCODE -ne 0) {
    throw "Synthetic interpolation sample generation failed."
  }
} else {
  $sample = [System.IO.Path]::GetFullPath($SamplePath)
}
if (-not (Test-Path -LiteralPath $sample -PathType Leaf)) {
  throw "Interpolation sample is missing: $sample"
}

$env:LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH = $plugin
try {
  $probeMode = if ($PerformanceGate) {
    "expect-active-performance"
  } else {
    "expect-active"
  }
  $probeResult = & $probe $runtimePath $scriptPath $sample $probeMode
  if ($LASTEXITCODE -ne 0) {
    throw "NVOFA VapourSynth real-frame probe failed with exit code $LASTEXITCODE.`n$probeResult"
  }
  $joinedProbeResult = @($probeResult) -join "`n"
  if ($joinedProbeResult -notmatch "consistency-protected=passed" -or
      $joinedProbeResult -notmatch "d3d11-warp=passed" -or
      $joinedProbeResult -notmatch "cuda-luid-match=passed" -or
      $joinedProbeResult -notmatch "d3d11-luid=([0-9a-f]{8}):([0-9a-f]{8})") {
    throw "NVOFA VapourSynth probe did not prove consistency-protected D3D11 warp and exact D3D11/CUDA LUID matching.`n$probeResult"
  }
  $probeResult
} finally {
  Remove-Item Env:LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH `
    -ErrorAction SilentlyContinue
}

Write-Output `
  "NVOFA VapourSynth 2x frames, seek, reload, and rollback boundary passed."
