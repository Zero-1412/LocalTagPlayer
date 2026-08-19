<##
.SYNOPSIS
  顺序运行正式 PlayerPage/MediaKit Texture precision controls 的独立 DWM 会话矩阵。

.DESCRIPTION
  每轮都启动独立 Debug 进程，由单会话脚本负责匿名 DWM 采样和资源释放；ready 前退出、
  缺少 summary 或脚本失败的会话只保留为 invalid，不进入聚合 visible 结论。有效会话
  交给 P1 校验器按 control 分别聚合 command/resource、visible 和 overall；unknown
  保持 unknown，脚本不会为了满足 Runs 数量而复制或重用旧证据。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Sample,
  [ValidateRange(3, 7)]
  [int]$Runs = 3,
  [string]$DebugExecutable = '',
  [string]$Output = '',
  [ValidateRange(960, 7680)]
  [int]$WindowWidth = 960,
  [ValidateRange(540, 4320)]
  [int]$WindowHeight = 720,
  [ValidateRange(15, 120)]
  [int]$SampleIntervalMilliseconds = 15,
  [ValidateRange(30, 180)]
  [int]$MinimumCaptureFps = 30,
  [ValidateRange(30, 180)]
  [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'P1 precision DWM 矩阵只支持 Windows。' }
if (-not (Test-Path -LiteralPath $Sample -PathType Leaf)) {
  throw 'P1 precision DWM 矩阵样本不存在。'
}
if (-not $Output) {
  $Output = Join-Path $PSScriptRoot ("..\.local\qa\precision-dwm-matrix-" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw '拒绝覆盖既有 P1 precision DWM 矩阵证据目录。'
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

$singleRunScript = Join-Path $PSScriptRoot 'run_player_precision_controls_dwm_qa.ps1'
$validatorScript = Join-Path $PSScriptRoot 'validate_player_p1_precision_evidence.ps1'
$validationOutputName = 'p1-precision-validation.json'
$validationOutput = Join-Path $Output $validationOutputName
$validationLog = Join-Path $Output 'p1-precision-validation.stdout.log'
$records = @()
$validRoots = @()

for ($index = 1; $index -le $Runs; $index++) {
  $runName = 'run-{0:D2}' -f $index
  $runRoot = Join-Path $Output $runName
  $runLog = Join-Path $Output ($runName + '-dwm-qa.stdout.log')
  $failure = $null
  $exitCode = $null
  $runSucceeded = $false
  try {
    $runArgs = @{
      Sample = $Sample
      Output = $runRoot
      WindowWidth = $WindowWidth
      WindowHeight = $WindowHeight
      SampleIntervalMilliseconds = $SampleIntervalMilliseconds
      MinimumCaptureFps = $MinimumCaptureFps
      TimeoutSeconds = $TimeoutSeconds
    }
    if (-not [string]::IsNullOrWhiteSpace($DebugExecutable)) {
      $runArgs.DebugExecutable = $DebugExecutable
    }
    # 每轮 stdout 独立落盘，避免矩阵输出混淆启动失败与播放器证据。
    & $singleRunScript @runArgs *> $runLog
    # 直接调用 PowerShell 脚本不保证设置 LASTEXITCODE；用调用状态配合 summary 文件，
    # 避免 StrictMode 把一个正常的 unknown 结果误报为编排异常。
    $runSucceeded = [bool]$?
    $exitCode = if ($runSucceeded) { 0 } else { 1 }
    $summaryExists = Test-Path -LiteralPath (Join-Path $runRoot 'precision-controls-dwm-summary.json') -PathType Leaf
    if (-not $runSucceeded) {
      $failure = 'single_run_failed'
    } elseif (-not $summaryExists) {
      $failure = 'missing_dwm_summary'
    }
  } catch {
    $failure = 'single_run_exception: ' + $_.Exception.Message
    $_ | Out-File -LiteralPath (Join-Path $Output ($runName + '-dwm-qa.error.log')) -Encoding utf8
  }

  $valid = $null -eq $failure
  if ($valid) { $validRoots += $runRoot }
  $records += [ordered]@{
    run = $index
    name = $runName
    status = if ($valid) { 'valid' } else { 'invalid' }
    exitCode = $exitCode
    failure = $failure
    evidenceDirectory = if ($valid) { $runName } else { $null }
  }
  Write-Output ('PLAYER_PRECISION_CONTROLS_DWM_MATRIX_RUN run={0}/{1} status={2}' -f $index,$Runs,($records[-1].status))
}

$validation = $null
$validatorExitCode = $null
if ($validRoots.Count -gt 0) {
  try {
    # 直接传递有效目录数组；validator 会按所有 session 的最严格状态聚合。
    & $validatorScript -EvidenceRoot $validRoots -Output $validationOutput *> $validationLog
    $validatorExitCode = [int]$LASTEXITCODE
    if (Test-Path -LiteralPath $validationOutput -PathType Leaf) {
      $validation = Get-Content -LiteralPath $validationOutput -Raw | ConvertFrom-Json
    }
  } catch {
    $validatorExitCode = 1
    $_ | Out-File -LiteralPath $validationLog -Encoding utf8
  }
}

$validCount = @($records | Where-Object status -eq 'valid').Count
$invalidCount = $records.Count - $validCount
$validationOverall = if ($null -eq $validation) { 'unknown' } else { [string]$validation.overall }
$overall = if ($validationOverall -eq 'fail') { 'fail' }
  elseif ($validationOverall -eq 'pass' -and $invalidCount -eq 0 -and $validCount -eq $Runs) { 'pass' }
  else { 'unknown' }
$report = [ordered]@{
  schemaVersion = 1
  evidence = 'real-player-page-dwm-precision-controls-matrix'
  overall = $overall
  runs = $Runs
  successfulRuns = $validCount
  failedRuns = $invalidCount
  validationExitCode = $validatorExitCode
  validation = $validationOutputName
  records = $records
  pathOrMediaContentRetained = $false
}
$summaryPath = Join-Path $Output 'precision-controls-dwm-matrix-summary.json'
[System.IO.File]::WriteAllText(
  $summaryPath,
  ($report | ConvertTo-Json -Depth 20),
  [System.Text.UTF8Encoding]::new($false)
)
Write-Output ('PLAYER_PRECISION_CONTROLS_DWM_MATRIX ' + ($report | ConvertTo-Json -Compress -Depth 20))

if ($overall -eq 'pass') { exit 0 }
if ($overall -eq 'fail') { exit 2 }
exit 3
