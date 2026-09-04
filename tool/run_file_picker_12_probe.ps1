<##
.SYNOPSIS
  在不引入 package_info_plus 的最小 Flutter 工程中验证 file_picker 12.2.0。

.DESCRIPTION
  探针固定 Flutter 3.47 revision，编译目录、多文件、单文件与保存四条静态 API，
  并在指定桌面平台构建 Debug 应用。Windows 产物可继续用于真实原生选择器点击。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Flutter,

  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,

  [Parameter(Mandatory = $true)]
  [ValidateSet('windows', 'linux', 'macos')]
  [string]$BuildTarget,

  [string]$ExpectedVersion = '3.47.0',

  [string]$ExpectedFrameworkRevision = '4cf24164269a5ebf0c16a028a00727d0e77bbb05'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$flutterPath = [System.IO.Path]::GetFullPath($Flutter)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$workspace = Join-Path $outputRoot 'workspace'
if (-not (Test-Path -LiteralPath $flutterPath -PathType Leaf)) {
  throw "Flutter 入口不存在：$flutterPath"
}
if (Test-Path -LiteralPath $outputRoot) {
  throw "拒绝覆盖既有 file_picker 门禁目录：$outputRoot"
}
if ($BuildTarget -eq 'windows' -and $workspace.Length -gt 70) {
  throw "Windows 探针路径过长（$($workspace.Length) 字符）；要求不超过 70 字符。"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$versionRaw = (& $flutterPath --version --machine | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Flutter 版本读取失败。' }
$version = $versionRaw | ConvertFrom-Json
if ([string]$version.frameworkVersion -ne $ExpectedVersion) {
  throw "Flutter 版本不符：actual=$($version.frameworkVersion) expected=$ExpectedVersion"
}
if ([string]$version.frameworkRevision -ne $ExpectedFrameworkRevision) {
  throw "Flutter revision 不符：actual=$($version.frameworkRevision) expected=$ExpectedFrameworkRevision"
}

$gateState = [ordered]@{
  createProbe = 'not-run'
  pubGet = 'not-run'
  staticApiAnalyze = 'not-run'
  debugBuild = 'not-run'
}

function Write-ProbeSummary {
  param(
    [Parameter(Mandatory = $true)][string]$Status,
    [string]$BlockingStage = ''
  )
  $summary = [ordered]@{
    status = $Status
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    package = [ordered]@{
      name = 'file_picker'
      version = '12.2.0'
      packageInfoPlusExcluded = $true
      dependencyOverrides = $false
    }
    flutter = [ordered]@{
      version = [string]$version.frameworkVersion
      frameworkRevision = [string]$version.frameworkRevision
      engineRevision = [string]$version.engineRevision
      dartSdkVersion = [string]$version.dartSdkVersion
    }
    platform = $BuildTarget
    gates = $gateState
    blockingStage = $BlockingStage
    logsContainLocalPaths = $true
    summaryOmitsLocalPaths = $true
  }
  $summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $outputRoot 'file-picker-12-probe-summary.json') -Encoding utf8
  Write-Output "FILE_PICKER_12_PROBE $($summary | ConvertTo-Json -Compress -Depth 10)"
}

function Invoke-ProbeStep {
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

& $flutterPath create --empty "--platforms=$BuildTarget" `
  --project-name=file_picker_12_probe $workspace *>&1 |
  Set-Content -LiteralPath (Join-Path $outputRoot '01-create.log') -Encoding utf8
if ($LASTEXITCODE -ne 0) {
  $gateState.createProbe = 'fail'
  Write-ProbeSummary -Status 'blocked' -BlockingStage '01-create'
  exit 1
}
$gateState.createProbe = 'pass'

$pubspecPath = Join-Path $workspace 'pubspec.yaml'
$pubspec = Get-Content -Raw -LiteralPath $pubspecPath
$flutterDependency = "  flutter:`n    sdk: flutter"
if (-not $pubspec.Contains($flutterDependency)) {
  $flutterDependency = "  flutter:`r`n    sdk: flutter"
}
if (-not $pubspec.Contains($flutterDependency)) {
  throw '探针 pubspec 缺少 Flutter SDK 依赖。'
}
$pubspec = $pubspec.Replace(
  $flutterDependency,
  "$flutterDependency`n  file_picker: 12.2.0"
)
Set-Content -LiteralPath $pubspecPath -Value $pubspec -Encoding utf8

$mainPath = Join-Path (Join-Path $workspace 'lib') 'main.dart'
$probeSource = @'
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FilePickerProbeApp());

class FilePickerProbeApp extends StatefulWidget {
  const FilePickerProbeApp({super.key});

  @override
  State<FilePickerProbeApp> createState() => _FilePickerProbeAppState();
}

class _FilePickerProbeAppState extends State<FilePickerProbeApp> {
  String _status = '等待操作';

  Future<void> _pickDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'file_picker 12 目录门禁',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    setState(() => _status = path == null ? '目录选择已取消' : '目录选择成功');
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'file_picker 12 多文件门禁',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    setState(() => _status = files.isEmpty ? '多文件选择已取消' : '多文件选择成功');
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'file_picker 12 单文件门禁',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    setState(() => _status = file == null ? '单文件选择已取消' : '单文件选择成功');
  }

  Future<void> _saveFile() async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'file_picker 12 保存门禁',
      fileName: 'file-picker-12-probe.txt',
      bytes: Uint8List.fromList('file_picker 12 probe'.codeUnits),
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    setState(() => _status = uri == null ? '保存选择已取消' : '保存选择成功');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('file_picker 12.2.0 原生门禁')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton(onPressed: _pickDirectory, child: const Text('选择目录')),
              FilledButton(onPressed: _pickFiles, child: const Text('选择多个文件')),
              FilledButton(onPressed: _pickFile, child: const Text('选择单个文件')),
              FilledButton(onPressed: _saveFile, child: const Text('选择保存位置')),
              const SizedBox(height: 16),
              Text(_status, key: const ValueKey<String>('probe-status')),
            ],
          ),
        ),
      ),
    );
  }
}
'@
Set-Content -LiteralPath $mainPath -Value $probeSource -Encoding utf8

$steps = @(
  [ordered]@{ key = 'pubGet'; name = '02-pub-get'; arguments = @('pub', 'get') },
  [ordered]@{ key = 'staticApiAnalyze'; name = '03-analyze'; arguments = @('analyze') },
  [ordered]@{ key = 'debugBuild'; name = '04-build-debug'; arguments = @('build', $BuildTarget, '--debug') }
)
foreach ($step in $steps) {
  Write-Output "FILE_PICKER_12_STEP platform=$BuildTarget step=$($step.name)"
  $exitCode = Invoke-ProbeStep -Name $step.name -Arguments $step.arguments
  if ($exitCode -ne 0) {
    $gateState[$step.key] = 'fail'
    Write-ProbeSummary -Status 'blocked' -BlockingStage $step.name
    exit $exitCode
  }
  $gateState[$step.key] = 'pass'
}

Write-ProbeSummary -Status 'pass'
