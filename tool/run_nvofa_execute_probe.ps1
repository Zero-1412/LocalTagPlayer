param(
  [ValidateSet("Debug", "Release", "RelWithDebInfo")]
  [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

<#
  该脚本按提交与摘要取得 NVIDIA 官方公开 NVOFA 头文件，只用于隔离 QA。

  文件保存在已忽略的 build 目录，不复制到 Runner、安装目录或 Flutter
  bundle；探针也必须通过显式 CMake 开关和目标名构建。
#>
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$headerCommit = "edb50da3cf849840d680249aa6dbef248ebce2ca"
$headerDirectory = Join-Path $repositoryRoot "build\nvofa-public-headers\$headerCommit"
$probeBuildDirectory = Join-Path $repositoryRoot "build\windows\x64"
$headers = @(
  @{
    Name = "nvOpticalFlowCommon.h"
    Sha256 = "A83F6045E5C470B35A6C50672F92E082B78D55752FE51CC20EB1A2738BE05B9D"
  },
  @{
    Name = "nvOpticalFlowCuda.h"
    Sha256 = "07DEFC79637FB9893F2A06204972EAA6BCF9E5BEA400C88440439EBAAA39F115"
  }
)

New-Item -ItemType Directory -Force -Path $headerDirectory | Out-Null
foreach ($header in $headers) {
  $destination = Join-Path $headerDirectory $header.Name
  $verified = Test-Path -LiteralPath $destination
  if ($verified) {
    $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    $verified = $actual -eq $header.Sha256
  }
  if (-not $verified) {
    $temporary = "$destination.download"
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    $url = "https://raw.githubusercontent.com/NVIDIA/NVIDIAOpticalFlowSDK/$headerCommit/$($header.Name)"
    Invoke-WebRequest -Uri $url -OutFile $temporary
    $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
    if ($actual -ne $header.Sha256) {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
      throw "NVOFA public header SHA256 mismatch: $($header.Name)"
    }
    Move-Item -LiteralPath $temporary -Destination $destination -Force
  }
}

$visualStudio = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
  -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
if ([string]::IsNullOrWhiteSpace($visualStudio)) {
  throw "Visual Studio C++ toolchain was not found."
}

$cmake = Join-Path $visualStudio "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path -LiteralPath $cmake)) {
  $cmake = "cmake"
}

$configureArguments = @(
  "-S", (Join-Path $repositoryRoot "windows"),
  "-B", $probeBuildDirectory,
  "-DLTP_BUILD_NVOFA_EXECUTE_PROBE=ON",
  "-DLTP_NVOFA_PUBLIC_HEADER_DIR=$headerDirectory"
)
if (-not (Test-Path -LiteralPath (Join-Path $probeBuildDirectory "CMakeCache.txt"))) {
  $configureArguments += @("-G", "Visual Studio 17 2022", "-A", "x64")
}
& $cmake @configureArguments
if ($LASTEXITCODE -ne 0) {
  throw "NVOFA execute probe CMake configure failed with exit code $LASTEXITCODE."
}

& $cmake --build $probeBuildDirectory --config $Configuration `
  --target ltp_nvofa_cuda_execute_probe
if ($LASTEXITCODE -ne 0) {
  throw "NVOFA execute probe build failed with exit code $LASTEXITCODE."
}

$probe = Join-Path $probeBuildDirectory "nvidia_optical_flow_probe\ltp_nvofa_cuda_execute_probe.exe"
if (-not (Test-Path -LiteralPath $probe)) {
  throw "NVOFA execute probe executable was not produced: $probe"
}

$result = & $probe
if ($LASTEXITCODE -ne 0) {
  throw "NVOFA execute probe failed with exit code $LASTEXITCODE.`n$result"
}
$result
