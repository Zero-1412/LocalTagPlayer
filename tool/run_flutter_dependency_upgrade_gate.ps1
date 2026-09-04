<##
.SYNOPSIS
  在独立短路径工作区验证单个 Flutter 直接依赖升级。

.DESCRIPTION
  每次只允许 desktop_drop 或 package_info_plus 一个候选。脚本复制 Git 跟踪内容，
  只改隔离副本中的目标约束，然后依次执行解析、focused/full test、analyze、
  Windows Debug build 和隔离 profile 启动 smoke；主工作树不会运行 pub 或 build。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('desktop_drop', 'package_info_plus')]
  [string]$Package,

  [Parameter(Mandatory = $true)]
  [string]$Flutter,

  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,

  [string]$ExpectedVersion = '3.47.0',

  [string]$ExpectedFrameworkRevision = '4cf24164269a5ebf0c16a028a00727d0e77bbb05',

  [string]$VerifiedDependencyCache = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutterPath = [System.IO.Path]::GetFullPath($Flutter)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$workspace = Join-Path $outputRoot 'workspace'
if ($workspace.Length -gt 55) {
  throw "隔离工作区路径过长（$($workspace.Length) 字符）；Windows C++ 门禁要求不超过 55 字符。"
}
if (-not (Test-Path -LiteralPath $flutterPath -PathType Leaf)) {
  throw "Flutter 入口不存在：$flutterPath"
}
if (Test-Path -LiteralPath $outputRoot) {
  throw "拒绝覆盖既有依赖门禁目录：$outputRoot"
}

$candidateByPackage = @{
  desktop_drop = [ordered]@{
    expectedConstraint = '^0.7.1'
    targetConstraint = '^0.8.4'
    focusedTests = @(
      'test/widget_test.dart',
      'test/architecture_contract_test.dart'
    )
  }
  package_info_plus = [ordered]@{
    expectedConstraint = '^9.0.1'
    targetConstraint = '^10.2.1'
    focusedTests = @(
      'test/app_update_test.dart',
      'test/architecture_contract_test.dart'
    )
  }
}
$candidate = $candidateByPackage[$Package]

New-Item -ItemType Directory -Path $workspace -Force | Out-Null
$trackedFiles = @(& git -C $repositoryRoot ls-files)
if ($LASTEXITCODE -ne 0 -or $trackedFiles.Count -eq 0) {
  throw '无法枚举 Git 跟踪文件。'
}
# 当前脚本可能仍处于交付前未跟踪状态；只额外复制这一个固定门禁文件。
$gateFiles = @('tool/run_flutter_dependency_upgrade_gate.ps1')
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
  # 与 Flutter 3.47 总门禁共享同一固定摘要，拒绝用未知本机二进制绕过供应链校验。
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

$pubspecPath = Join-Path $workspace 'pubspec.yaml'
$pubspec = Get-Content -Raw -LiteralPath $pubspecPath
$escapedPackage = [regex]::Escape($Package)
$constraintPattern = '(?m)^  {0}: (?<constraint>[^\r\n]+)' -f $escapedPackage
$matches = [regex]::Matches($pubspec, $constraintPattern)
if ($matches.Count -ne 1) {
  throw "pubspec 未找到唯一直接依赖：$Package"
}
$match = $matches[0]
$actualConstraint = $match.Groups['constraint'].Value.Trim()
if ($actualConstraint -ne $candidate.expectedConstraint) {
  throw "候选基线约束不符：package=$Package actual=$actualConstraint expected=$($candidate.expectedConstraint)"
}
$replacement = "  ${Package}: $($candidate.targetConstraint)"
$updatedPubspec = [regex]::Replace($pubspec, $constraintPattern, $replacement, 1)
Set-Content -LiteralPath $pubspecPath -Value $updatedPubspec -Encoding utf8

$versionRaw = (& $flutterPath --version --machine | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Flutter 版本读取失败。' }
$version = $versionRaw | ConvertFrom-Json
if ([string]$version.frameworkVersion -ne $ExpectedVersion) {
  throw "Flutter 版本不符：actual=$($version.frameworkVersion) expected=$ExpectedVersion"
}
if ([string]$version.frameworkRevision -ne $ExpectedFrameworkRevision) {
  throw "Flutter revision 不符：actual=$($version.frameworkRevision) expected=$ExpectedFrameworkRevision"
}

$sourceRevision = (& git -C $repositoryRoot rev-parse HEAD | Out-String).Trim()
$gateState = [ordered]@{
  pubGet = 'not-run'
  focusedTests = 'not-run'
  fullTests = 'not-run'
  flutterAnalyze = 'not-run'
  windowsDebugBuild = 'not-run'
  windowsDebugStartup = 'not-run'
}

function Write-GateSummary {
  param(
    [Parameter(Mandatory = $true)][string]$Status,
    [string]$BlockingStage = ''
  )
  $summary = [ordered]@{
    status = $Status
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    candidate = [ordered]@{
      package = $Package
      fromConstraint = $candidate.expectedConstraint
      targetConstraint = $candidate.targetConstraint
      isolatedSinglePackageChange = $true
      dependencyOverrides = $false
    }
    flutter = [ordered]@{
      version = [string]$version.frameworkVersion
      frameworkRevision = [string]$version.frameworkRevision
      engineRevision = [string]$version.engineRevision
      dartSdkVersion = [string]$version.dartSdkVersion
    }
    source = [ordered]@{
      repositoryRevision = $sourceRevision
      workingTreeContentCopied = $true
      untrackedUserFilesExcluded = $true
      includedUntrackedGateFiles = $gateFiles
    }
    gates = $gateState
    dependencySeed = $dependencySeedSummary
    blockingStage = $BlockingStage
    logsContainLocalPaths = $true
    summaryOmitsLocalPaths = $true
  }
  $summaryPath = Join-Path $outputRoot 'dependency-gate-summary.json'
  $summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding utf8
  Write-Output "FLUTTER_DEPENDENCY_UPGRADE_GATE $($summary | ConvertTo-Json -Compress -Depth 10)"
}

function Invoke-FlutterGateStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $logPath = Join-Path $outputRoot "$Name.log"
  Push-Location $workspace
  try {
    & $flutterPath @Arguments *>&1 | Set-Content -LiteralPath $logPath -Encoding utf8
    return $LASTEXITCODE
  } finally {
    Pop-Location
  }
}

function Test-IsolatedStartup {
  $executable = Join-Path $workspace 'build\windows\x64\runner\Debug\local_tag_player.exe'
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    return 1
  }
  $profile = Join-Path $outputRoot 'startup-profile'
  New-Item -ItemType Directory -Path $profile -Force | Out-Null
  $stdout = Join-Path $outputRoot '06-startup.stdout.log'
  $stderr = Join-Path $outputRoot '06-startup.stderr.log'
  $previousDataDirectory = $env:LOCAL_TAG_PLAYER_DATA_DIR
  $env:LOCAL_TAG_PLAYER_DATA_DIR = $profile
  try {
    $process = Start-Process -FilePath $executable -WindowStyle Hidden `
      -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    try {
      Start-Sleep -Seconds 5
      $process.Refresh()
      if ($process.HasExited -or -not $process.Responding) {
        return 1
      }
      return 0
    } finally {
      if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
      }
    }
  } finally {
    if ($null -eq $previousDataDirectory) {
      Remove-Item Env:LOCAL_TAG_PLAYER_DATA_DIR -ErrorAction SilentlyContinue
    } else {
      $env:LOCAL_TAG_PLAYER_DATA_DIR = $previousDataDirectory
    }
  }
}

$steps = @(
  [ordered]@{ key = 'pubGet'; name = '01-pub-get'; arguments = @('pub', 'get') },
  [ordered]@{ key = 'focusedTests'; name = '02-focused-tests'; arguments = @('test') + $candidate.focusedTests },
  [ordered]@{ key = 'fullTests'; name = '03-full-tests'; arguments = @('test') },
  [ordered]@{ key = 'flutterAnalyze'; name = '04-analyze'; arguments = @('analyze') },
  [ordered]@{ key = 'windowsDebugBuild'; name = '05-build-debug'; arguments = @('build', 'windows', '--debug') }
)
foreach ($step in $steps) {
  Write-Output "DEPENDENCY_GATE_STEP package=$Package step=$($step.name)"
  $exitCode = Invoke-FlutterGateStep -Name $step.name -Arguments $step.arguments
  if ($exitCode -ne 0) {
    $gateState[$step.key] = 'fail'
    Write-GateSummary -Status 'blocked' -BlockingStage $step.name
    exit $exitCode
  }
  $gateState[$step.key] = 'pass'
}

Write-Output "DEPENDENCY_GATE_STEP package=$Package step=06-startup"
$startupExitCode = Test-IsolatedStartup
if ($startupExitCode -ne 0) {
  $gateState.windowsDebugStartup = 'fail'
  Write-GateSummary -Status 'blocked' -BlockingStage '06-startup'
  exit $startupExitCode
}
$gateState.windowsDebugStartup = 'pass'
Write-GateSummary -Status 'pass'
