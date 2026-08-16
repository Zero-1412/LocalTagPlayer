param(
  [string]$Flutter = 'flutter',
  [string[]]$SamplePaths = @(),
  [ValidateRange(10, 86400)]
  [int]$LongPlaySeconds = 1800,
  [ValidateRange(6, 1000)]
  [int]$RapidSwitchCount = 18,
  [ValidateRange(0, 10000)]
  [int]$MaxDroppedFrames = 5,
  [ValidateSet('auto', 'simulated', 'passed', 'failed')]
  [string]$PhysicalCrossDpiStatus = 'auto',
  # 用 Flutter Profile 构建执行集成测试；默认 Debug 保留本地快速诊断路径。
  [switch]$Profile,
  [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($SamplePaths.Count -eq 0) {
  # 本机自然片源只作为便捷默认值；仓库不分发这些文件，CI 或其它开发机必须显式传入。
  $SamplePaths = @(
    (Join-Path $repoRoot '.local\qa\natural-compression-ab\samples\live-face-low-650k.mp4'),
    (Join-Path $repoRoot '.local\qa\natural-compression-ab\samples\animation-gradient-low-650k.mp4'),
    (Join-Path $repoRoot '.local\qa\natural-compression-ab\samples\dark-scene-low-650k.mp4')
  )
}
if ($SamplePaths.Count -lt 3) {
  throw '双后端稳定性矩阵至少需要三段真实片源。'
}
$resolvedSamples = @()
foreach ($sample in $SamplePaths) {
  if (-not (Test-Path -LiteralPath $sample -PathType Leaf)) {
    throw "稳定性矩阵片源不存在：$sample"
  }
  $resolvedSamples += [System.IO.Path]::GetFullPath($sample)
}

if (-not $Output) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $Output = Join-Path $repoRoot ".local\qa\player-backend-stability\$stamp"
}
if (-not [System.IO.Path]::IsPathRooted($Output)) {
  $Output = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
}
if (Test-Path -LiteralPath $Output) {
  throw "稳定性矩阵输出目录已存在，拒绝覆盖：$Output"
}
New-Item -ItemType Directory -Force -Path $Output | Out-Null

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens
if ($PhysicalCrossDpiStatus -eq 'simulated') {
  # 单屏模拟只验证 Flutter metrics、Surface 重算和状态机，不声称发生了物理跨屏。
  $effectivePhysicalDpiStatus = 'simulated-single-monitor'
} elseif ($PhysicalCrossDpiStatus -eq 'auto') {
  # 自动测试无法在单显示器上证明真实跨 DPI；多显示器也需要确认两块屏幕缩放不同并实际移窗。
  $effectivePhysicalDpiStatus = if ($screens.Count -lt 2) {
    'not-run-single-monitor'
  } else {
    'pending-physical-cross-display'
  }
} else {
  $effectivePhysicalDpiStatus = $PhysicalCrossDpiStatus
}

$env:LOCAL_TAG_PLAYER_STABILITY_SAMPLES = $resolvedSamples -join '|'
$env:LOCAL_TAG_PLAYER_STABILITY_LONG_SECONDS = $LongPlaySeconds.ToString()
$env:LOCAL_TAG_PLAYER_STABILITY_SWITCHES = $RapidSwitchCount.ToString()
$env:LOCAL_TAG_PLAYER_STABILITY_MAX_DROPPED_FRAMES = $MaxDroppedFrames.ToString()
$env:LOCAL_TAG_PLAYER_STABILITY_PHYSICAL_DPI_STATUS = $effectivePhysicalDpiStatus

$runResults = @()
try {
  foreach ($backend in @('mediaKit', 'mpv')) {
    $backendOutput = Join-Path $Output $backend
    New-Item -ItemType Directory -Force -Path $backendOutput | Out-Null
    $env:LOCAL_TAG_PLAYER_STABILITY_BACKEND = $backend
    $env:LOCAL_TAG_PLAYER_STABILITY_OUTPUT = $backendOutput
    $logPath = Join-Path $backendOutput 'integration.log'

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($Profile) {
      & $Flutter drive `
        --profile `
        --driver (Join-Path $repoRoot 'test_driver\integration_test.dart') `
        --target (Join-Path $repoRoot 'integration_test\player_backend_stability_matrix_test.dart') `
        -d windows *>&1 |
        Tee-Object -FilePath $logPath
    } else {
      & $Flutter test `
        integration_test/player_backend_stability_matrix_test.dart `
        -d windows *>&1 |
        Tee-Object -FilePath $logPath
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference

    $reportPath = Join-Path $backendOutput "$backend-stability.json"
    $report = if (Test-Path -LiteralPath $reportPath) {
      Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    } else {
      $null
    }
    $runResults += [PSCustomObject]@{
      backend = $backend
      exitCode = $exitCode
      reportPath = $reportPath
      report = $report
    }
  }
} finally {
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_BACKEND -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_SAMPLES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_LONG_SECONDS -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_SWITCHES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_MAX_DROPPED_FRAMES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STABILITY_PHYSICAL_DPI_STATUS -ErrorAction SilentlyContinue
}

$backendReports = @{}
foreach ($run in $runResults) {
  $backendReports[$run.backend] = $run.report
}
$automatedPass = ($runResults | Where-Object {
    $_.exitCode -ne 0 -or $null -eq $_.report -or $_.report.automatedPass -ne $true
  }).Count -eq 0
$releaseGate = if (-not $automatedPass) {
  'failed'
} elseif ($effectivePhysicalDpiStatus -eq 'simulated-single-monitor') {
  'passed-simulated-cross-dpi'
} elseif ($effectivePhysicalDpiStatus -eq 'passed') {
  'passed'
} else {
  'pending-physical-cross-dpi'
}

$matrix = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  platform = 'windows'
  automatedPass = $automatedPass
  releaseGate = $releaseGate
  physicalCrossDpiStatus = $effectivePhysicalDpiStatus
  displayCount = $screens.Count
  requestedLongPlaySecondsPerBackend = $LongPlaySeconds
  requestedRapidSwitchesPerBackend = $RapidSwitchCount
  maxDroppedFramesPerBackend = $MaxDroppedFrames
  backends = $backendReports
  platformGates = [ordered]@{
    windows = [ordered]@{
      mediaKit = 'available'
      mpv = 'available-libmpv-flutter-texture'
    }
    macos = [ordered]@{
      mediaKit = 'available'
      mpv = 'blocked-native-backend-not-implemented'
    }
    linux = [ordered]@{
      mediaKit = 'available'
      mpv = 'blocked-native-backend-not-implemented'
    }
  }
}
$matrixPath = Join-Path $Output 'player-backend-stability-matrix.json'
$matrix | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath $matrixPath -Encoding utf8

Write-Host "稳定性矩阵：$matrixPath"
Write-Host "自动门禁：$automatedPass；发布门禁：$releaseGate；真实跨 DPI：$effectivePhysicalDpiStatus"
if (-not $automatedPass) {
  exit 1
}
