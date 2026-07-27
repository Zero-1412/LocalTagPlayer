param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build\windows\x64'
$configurationFlag = if ($Configuration -eq 'Debug') { '--debug' } else { '--release' }
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
  & $cmakeCommand -S windows -B $buildRoot -DLTP_BUILD_NVOFA_DRIVER_PROBE=ON
  if ($LASTEXITCODE -ne 0) {
    throw "NVOFA probe configuration failed with exit code $LASTEXITCODE"
  }
  & $cmakeCommand --build $buildRoot --config $Configuration `
    --target ltp_nvofa_driver_probe
  if ($LASTEXITCODE -ne 0) {
    throw "NVOFA driver probe build failed with exit code $LASTEXITCODE"
  }

  $probe = Join-Path $buildRoot 'nvidia_optical_flow_probe\ltp_nvofa_driver_probe.exe'
  if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
    throw "NVOFA driver probe output is missing: $probe"
  }
  & $probe
  if ($LASTEXITCODE -ne 0) {
    throw "NVOFA driver probe failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}
