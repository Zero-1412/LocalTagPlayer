param(
  [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
  [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build\windows\x64'
$configurationFlag = if ($Configuration -eq 'Debug') { '--debug' } else { '--release' }
$runnerConfiguration = if ($Configuration -eq 'Debug') { 'Debug' } else { 'Release' }
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
    --target ltp_vsscript_stub ltp_vapoursynth_motion_host_test
  if ($LASTEXITCODE -ne 0) {
    throw "VapourSynth probe build failed with exit code $LASTEXITCODE"
  }

  $probeDirectory = Join-Path $buildRoot 'vapoursynth_motion_probe'
  $hostTest = Join-Path $probeDirectory 'ltp_vapoursynth_motion_host_test.exe'
  $vsscript = Join-Path $probeDirectory 'VSScript.dll'
  $script = Join-Path $repoRoot 'tool\vapoursynth_passthrough_probe.vpy'
  if (-not (Test-Path -LiteralPath $hostTest) -or
      -not (Test-Path -LiteralPath $vsscript)) {
    throw "VapourSynth probe output is missing: $probeDirectory"
  }

  $mpvDirectory = Join-Path $buildRoot "runner\$runnerConfiguration"
  $previousPath = $env:PATH
  try {
    $env:PATH = "$mpvDirectory;$previousPath"
    & $hostTest $probeDirectory $script
    if ($LASTEXITCODE -ne 0) {
      throw "Structured vf host test failed with exit code $LASTEXITCODE"
    }
  } finally {
    $env:PATH = $previousPath
  }
  Write-Output 'VapourSynth host: structured append, preservation, and removal passed.'
} finally {
  Pop-Location
}
