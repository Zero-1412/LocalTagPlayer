param(
  [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
  [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build\windows\x64'
$configurationFlag = if ($Configuration -eq 'Debug') { '--debug' } else { '--release' }
$flutterCommand = (Get-Command flutter.bat -ErrorAction Stop).Source
$cmakeCommand = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if ([string]::IsNullOrWhiteSpace($cmakeCommand)) {
  # Flutter may use Visual Studio's bundled CMake without adding it to PATH.
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
  # Generate the Flutter Windows build tree, then build only the local probe.
  & $flutterCommand build windows $configurationFlag
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows configuration failed with exit code $LASTEXITCODE"
  }

  & $cmakeCommand -S windows -B $buildRoot -DLTP_BUILD_LOCAL_VIDEO_PLUGIN_PROBE=ON
  if ($LASTEXITCODE -ne 0) {
    throw "Probe CMake configuration failed with exit code $LASTEXITCODE"
  }
  & $cmakeCommand --build $buildRoot --config $Configuration --target ltp_local_video_plugin_probe
  if ($LASTEXITCODE -ne 0) {
    throw "Probe build failed with exit code $LASTEXITCODE"
  }

  $probePath = Join-Path $buildRoot 'local_video_plugin_probe\ltp_local_video_plugin_probe.dll'
  if (-not (Test-Path -LiteralPath $probePath)) {
    throw "Probe target built but the expected DLL is missing: $probePath"
  }
  & $cmakeCommand --build $buildRoot --config $Configuration --target ltp_local_video_plugin_host_test
  if ($LASTEXITCODE -ne 0) {
    throw "Host test build failed with exit code $LASTEXITCODE"
  }
  $hostTestPath = Join-Path $buildRoot 'local_video_plugin_probe\ltp_local_video_plugin_host_test.exe'
  if (-not (Test-Path -LiteralPath $hostTestPath)) {
    throw "Host test built but the expected executable is missing: $hostTestPath"
  }
  $env:LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH = $probePath
  & $hostTestPath
  if ($LASTEXITCODE -ne 0) {
    throw "Host round-trip and fallback test failed with exit code $LASTEXITCODE"
  }
  Write-Output "Probe DLL: $probePath"
  Write-Output 'Local QA requires LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv and LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH.'
  Write-Output 'Set LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PROBE_FAIL_AFTER=30 to test fallback.'
} finally {
  Pop-Location
}
