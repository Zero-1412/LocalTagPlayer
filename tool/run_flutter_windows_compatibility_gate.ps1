<##
.SYNOPSIS
  在只含 Git 跟踪文件的隔离工作区验证指定 Flutter Windows SDK。

.DESCRIPTION
  当前工作树不会运行 pub get、build 或测试。脚本把 Git 跟踪文件的当前内容复制到
  新 QA 目录，核验 Flutter 版本/revision 后运行全量测试、analyze、Debug/Release
  构建与启动 smoke，最后使用本机 12-case manifest 运行正式 MediaKit Texture 矩阵。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Flutter,

  [Parameter(Mandatory = $true)]
  [string]$Manifest,

  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,

  [string]$ExpectedVersion = '3.47.0',

  [string]$ExpectedFrameworkRevision = '4cf24164269a5ebf0c16a028a00727d0e77bbb05',

  [string]$FFprobe = '',

  [string]$VerifiedDependencyCache = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutterPath = [System.IO.Path]::GetFullPath($Flutter)
$manifestPath = [System.IO.Path]::GetFullPath($Manifest)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$workspace = Join-Path $outputRoot 'workspace'
if ($workspace.Length -gt 55) {
  throw "隔离工作区路径过长（$($workspace.Length) 字符）；Windows C++ 门禁要求不超过 55 字符。"
}
if (-not (Test-Path -LiteralPath $flutterPath -PathType Leaf)) {
  throw "Flutter 入口不存在：$flutterPath"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "seek manifest 不存在：$manifestPath"
}
if (Test-Path -LiteralPath $outputRoot) {
  throw "拒绝覆盖既有兼容门禁目录：$outputRoot"
}
if (-not $FFprobe) {
  $FFprobe = Join-Path $repositoryRoot 'windows\tools\ffmpeg\bin\ffprobe.exe'
}
$ffprobePath = [System.IO.Path]::GetFullPath($FFprobe)
if (-not (Test-Path -LiteralPath $ffprobePath -PathType Leaf)) {
  throw "ffprobe 不存在：$ffprobePath"
}

New-Item -ItemType Directory -Path $workspace -Force | Out-Null
$trackedFiles = @(& git -C $repositoryRoot ls-files)
if ($LASTEXITCODE -ne 0 -or $trackedFiles.Count -eq 0) {
  throw '无法枚举 Git 跟踪文件。'
}
$gateFiles = @(
  'tool/prepare_player_seek_latency_baseline.ps1',
  'tool/run_flutter_windows_compatibility_gate.ps1'
)
$isolatedFiles = @($trackedFiles + $gateFiles | Sort-Object -Unique)
foreach ($relativePath in $isolatedFiles) {
  $source = Join-Path $repositoryRoot $relativePath
  $destination = Join-Path $workspace $relativePath
  $destinationParent = Split-Path $destination -Parent
  if (-not (Test-Path -LiteralPath $destinationParent)) {
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
  }
  Copy-Item -LiteralPath $source -Destination $destination
}

$dependencySeedSummary = [ordered]@{
  enabled = $false
  verifiedArchives = 0
}
if (-not [string]::IsNullOrWhiteSpace($VerifiedDependencyCache)) {
  $dependencyCachePath = [System.IO.Path]::GetFullPath($VerifiedDependencyCache)
  if (-not (Test-Path -LiteralPath $dependencyCachePath -PathType Container)) {
    throw "固定依赖种子目录不存在：$dependencyCachePath"
  }
  $expectedDependencies = [ordered]@{
    'mpv.7z' = '72b1b348458f632063ed92a967617a078dc05129635a1b929c61d121b0e3a802'
    'angle.7z' = 'cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a'
    'media_kit_video.tar.gz' = 'afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d'
    'ffmpeg-lgpl-shared.zip' = '27bcaf58b5140171dfe838a0b365d12c60607d71fc168424456410bad6a834da'
    'LICENSE.mpv.GPL-2.0.txt' = 'edaef632cbb643e4e7a221717a6c441a4c1a7c918e6e4d56debc3d8739b233f6'
    'LICENSE.mpv.LGPL-2.1.txt' = '72b672113d642cbb8ef5dcc76938db801983c56e50b1400ab930f1a64d6dc8d9'
    'LICENSE.ANGLE.txt' = 'bf4da21bd20bcfb5b60b7ecc67fa864a79be049e21d6178076887f178dd6c71a'
  }
  $seedDestination = Join-Path $workspace 'build\windows\x64\ltp_native_deps'
  New-Item -ItemType Directory -Path $seedDestination -Force | Out-Null
  foreach ($entry in $expectedDependencies.GetEnumerator()) {
    $source = Join-Path $dependencyCachePath $entry.Key
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "固定依赖种子缺少文件：$($entry.Key)"
    }
    $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $entry.Value) {
      throw "固定依赖种子摘要不匹配：$($entry.Key)"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $seedDestination $entry.Key)
  }
  $dependencySeedSummary = [ordered]@{
    enabled = $true
    verifiedArchives = $expectedDependencies.Count
    pathsOmitted = $true
  }
}

$versionRaw = (& $flutterPath --version --machine | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Flutter 版本读取失败。' }
$version = $versionRaw | ConvertFrom-Json
if ([string]$version.frameworkVersion -ne $ExpectedVersion) {
  throw "Flutter 版本不符：actual=$($version.frameworkVersion) expected=$ExpectedVersion"
}
if ([string]$version.frameworkRevision -ne $ExpectedFrameworkRevision) {
  throw "Flutter revision 不符：actual=$($version.frameworkRevision) expected=$ExpectedFrameworkRevision"
}

function Invoke-FlutterStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $logPath = Join-Path $outputRoot "$Name.log"
  Push-Location $workspace
  try {
    & $flutterPath @Arguments *>&1 | Tee-Object -FilePath $logPath
    $stepExitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  if ($stepExitCode -ne 0) {
    throw "Flutter 兼容门禁失败：step=$Name exit=$stepExitCode log=$logPath"
  }
}

function Test-AppStartup {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Executable
  )
  if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "启动 smoke 缺少可执行文件：$Name"
  }
  $stdout = Join-Path $outputRoot "$Name.stdout.log"
  $stderr = Join-Path $outputRoot "$Name.stderr.log"
  $process = Start-Process -FilePath $Executable -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  try {
    Start-Sleep -Seconds 10
    $process.Refresh()
    if ($process.HasExited) {
      throw "$Name 提前退出：exit=$($process.ExitCode)"
    }
    if (-not $process.Responding) {
      throw "$Name 进程存活但无响应。"
    }
  } finally {
    if (-not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
      $process.WaitForExit()
    }
  }
}

Invoke-FlutterStep -Name '01-pub-get' -Arguments @('pub', 'get')
Invoke-FlutterStep -Name '02-test' -Arguments @('test')
Invoke-FlutterStep -Name '03-analyze' -Arguments @('analyze')
Invoke-FlutterStep -Name '04-build-debug' -Arguments @('build', 'windows', '--debug')
Test-AppStartup -Name '05-debug-startup' -Executable (
  Join-Path $workspace 'build\windows\x64\runner\Debug\local_tag_player.exe'
)
Invoke-FlutterStep -Name '06-build-release' -Arguments @('build', 'windows', '--release')
Test-AppStartup -Name '07-release-startup' -Executable (
  Join-Path $workspace 'build\windows\x64\runner\Release\local_tag_player.exe'
)

$matrixOutput = Join-Path $outputRoot '08-seek-matrix-debug'
$matrixScript = Join-Path $workspace 'tool\run_player_seek_latency_matrix.ps1'
Push-Location $workspace
try {
  & $matrixScript -Manifest $manifestPath -Flutter $flutterPath `
    -FFprobe $ffprobePath -Backend mediaKit -Output $matrixOutput
  $matrixExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($matrixExitCode -ne 0) {
  throw "Flutter 兼容门禁失败：step=08-seek-matrix-debug exit=$matrixExitCode"
}

$sourceRevision = (& git -C $repositoryRoot rev-parse HEAD | Out-String).Trim()
$summary = [ordered]@{
  status = 'pass'
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  flutter = [ordered]@{
    version = [string]$version.frameworkVersion
    frameworkRevision = [string]$version.frameworkRevision
    engineRevision = [string]$version.engineRevision
    dartSdkVersion = [string]$version.dartSdkVersion
  }
  source = [ordered]@{
    repositoryRevision = $sourceRevision
    trackedFilesOnly = $false
    workingTreeContentCopied = $true
    untrackedUserFilesExcluded = $true
    includedUntrackedGateFiles = $gateFiles
  }
  gates = [ordered]@{
    flutterTest = 'pass'
    flutterAnalyze = 'pass'
    windowsDebugBuildAndStartup = 'pass'
    windowsReleaseBuildAndStartup = 'pass'
    mediaKitTextureSeekMatrixDebug = 'pass'
    releaseTexturePerformance = 'not-measured'
  }
  dependencySeed = $dependencySeedSummary
  evidence = [ordered]@{
    samplePathsOmitted = $true
    seekSummary = '08-seek-matrix-debug/summary.json'
    preflightSummary = '08-seek-matrix-debug/preflight-summary.json'
  }
}
$summary | ConvertTo-Json -Depth 10 |
  Set-Content -LiteralPath (Join-Path $outputRoot 'compatibility-summary.json') -Encoding utf8
Write-Output "FLUTTER_WINDOWS_COMPATIBILITY_GATE $($summary | ConvertTo-Json -Compress -Depth 10)"
