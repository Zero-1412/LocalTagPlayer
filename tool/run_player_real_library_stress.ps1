param(
  [string]$Flutter = 'E:\flutter\bin\flutter.bat',
  [int]$DurationSeconds = 1800,
  [int]$Seed = 20260713,
  [string]$MediaPath = '',
  # 复用真实播放、输入和全屏路径建立 Windows Profile 基线，不改变当前 Flutter SDK。
  [switch]$Profile,
  # 自动过期只处理带压力测试标记的目录；0 表示禁用。
  [ValidateRange(0, 3650)]
  [int]$ArtifactRetentionDays = 7,
  # 显式保留截图、逐秒指标和其它原始证据。
  [switch]$KeepRawArtifacts,
  [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
$artifactsRoot = Join-Path $PSScriptRoot '..\artifacts'
New-Item -ItemType Directory -Force -Path $artifactsRoot | Out-Null
& (Join-Path $PSScriptRoot 'manage_stress_artifacts.ps1') `
  -ArtifactsRoot $artifactsRoot `
  -RetentionDays $ArtifactRetentionDays
if (-not $Output) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $Output = Join-Path $artifactsRoot "player_real_library_stress_$stamp"
}
if (-not [System.IO.Path]::IsPathRooted($Output)) {
  $Output = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
}
if (Test-Path -LiteralPath $Output) {
  throw "输出目录已存在，拒绝覆盖：$Output"
}
New-Item -ItemType Directory -Force -Path $Output | Out-Null
Set-Content -LiteralPath (Join-Path $Output '.ltp-stress-artifact') -Value ((Get-Date).ToUniversalTime().ToString('o'))
Set-Content -LiteralPath "$Output\phase.current" -Value 'test_start|0'

# 只读取进程指标并写入压测目录，不创建 UIA 客户端。

$monitorJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  $metrics = Join-Path $Output 'process-metrics.csv'
  'timestamp,phase,cycle,cpu_seconds,threads,working_set_mb,private_mb,handles,responding,gpu_util_percent,gpu_dedicated_mb,gpu_shared_mb,gpu_committed_mb' | Set-Content $metrics
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done'))) {
    $sampleStarted = Get-Date
    $process = Get-Process local_tag_player -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $process) {
      $phase = 'unknown'
      $cycle = 0
      $phaseFile = Join-Path $Output 'phase.current'
      if (Test-Path -LiteralPath $phaseFile) {
        $parts = ((Get-Content -LiteralPath $phaseFile -Raw).Trim()) -split '\|', 2
        if ($parts.Count -ge 1 -and $parts[0]) { $phase = $parts[0] }
        if ($parts.Count -ge 2) { [void][int]::TryParse($parts[1], [ref]$cycle) }
      }
      $gpuDedicated = 0.0
      $gpuShared = 0.0
      $gpuCommitted = 0.0
      $gpuUtilPercent = 0.0
      try {
        $gpuPrefix = '\GPU Process Memory(pid_' + $process.Id + '_*)\'
        $gpuEngine = '\GPU Engine(pid_' + $process.Id + '_*)\Utilization Percentage'
        $gpu = Get-Counter -Counter @(
          ($gpuPrefix + 'Dedicated Usage'),
          ($gpuPrefix + 'Shared Usage'),
          ($gpuPrefix + 'Total Committed'),
          $gpuEngine
        ) -ErrorAction Stop
        foreach ($sample in $gpu.CounterSamples) {
          if ($sample.Path -like '*\dedicated usage') { $gpuDedicated += $sample.CookedValue }
          elseif ($sample.Path -like '*\shared usage') { $gpuShared += $sample.CookedValue }
          elseif ($sample.Path -like '*\total committed') { $gpuCommitted += $sample.CookedValue }
          elseif ($sample.Path -like '*\utilization percentage') { $gpuUtilPercent += $sample.CookedValue }
        }
      } catch {}
      $line = '{0},{1},{2},{3:F3},{4},{5:F1},{6:F1},{7},{8},{9:F1},{10:F1},{11:F1},{12:F1}' -f `
        $(Get-Date -Format o),
        $phase,
        $cycle,
        $process.TotalProcessorTime.TotalSeconds,
        $process.Threads.Count,
        ($process.WorkingSet64 / 1MB),
        ($process.PrivateMemorySize64 / 1MB),
        $process.HandleCount,
        $process.Responding,
        $gpuUtilPercent,
        ($gpuDedicated / 1MB),
        ($gpuShared / 1MB),
        ($gpuCommitted / 1MB)
      Add-Content -LiteralPath $metrics -Value $line
    }
    $remainingMs = 1000 - ((Get-Date) - $sampleStarted).TotalMilliseconds
    if ($remainingMs -gt 0) { Start-Sleep -Milliseconds $remainingMs }
  }
}

# 只按 marker 保存窗口像素，不查询、启用或关闭应用语义树。

$captureJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  Add-Type -AssemblyName System.Drawing
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpStressWindowCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
  [LtpStressWindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
  $captured = @{}
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done'))) {
    foreach ($marker in Get-ChildItem -LiteralPath $Output -Filter '*.ready' -ErrorAction SilentlyContinue) {
      if ($captured.ContainsKey($marker.FullName)) { continue }
      $process = Get-Process local_tag_player -ErrorAction SilentlyContinue |
        Where-Object MainWindowHandle -ne 0 |
        Select-Object -First 1
      if ($null -eq $process) { continue }
      $rect = New-Object LtpStressWindowCapture+RECT
      if (-not ([LtpStressWindowCapture]::GetWindowRect($process.MainWindowHandle, [ref]$rect))) { continue }
      $bitmap = [System.Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
      $graphics.Dispose()
      $bitmap.Save((Join-Path $Output "$($marker.BaseName).png"))
      $bitmap.Dispose()
      $captured[$marker.FullName] = $true
    }
    Start-Sleep -Milliseconds 200
  }
}

$env:LOCAL_TAG_PLAYER_STRESS_SECONDS = $DurationSeconds.ToString()
$env:LOCAL_TAG_PLAYER_STRESS_SEED = $Seed.ToString()
$env:LOCAL_TAG_PLAYER_STRESS_OUTPUT = $Output
if ($MediaPath) {
  $env:LOCAL_TAG_PLAYER_STRESS_MEDIA_PATH = $MediaPath
} else {
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_MEDIA_PATH -ErrorAction SilentlyContinue
}
try {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  if ($Profile) {
    & $Flutter drive `
      --profile `
      --driver test_driver/integration_test.dart `
      --target integration_test/player_real_library_stress_test.dart `
      -d windows *>&1 |
      Tee-Object -FilePath (Join-Path $Output 'stress.log')
  } else {
    & $Flutter test integration_test/player_real_library_stress_test.dart -d windows *>&1 |
      Tee-Object -FilePath (Join-Path $Output 'stress.log')
  }
  $testExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
  New-Item -ItemType File -Force -Path "$Output\stress.done" | Out-Null
  Wait-Job $monitorJob, $captureJob -Timeout 20 | Out-Null
  Receive-Job $monitorJob, $captureJob
  Remove-Job $monitorJob, $captureJob -Force
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_SECONDS -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_SEED -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_MEDIA_PATH -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath (Join-Path $Output 'process-metrics.csv')) {
  $summaryArguments = @{
    InputDirectory = $Output;
    LogPath = (Join-Path $Output 'stress.log');
  }
  & (Join-Path $PSScriptRoot 'summarize_player_stress_metrics.ps1') @summaryArguments
}
if ($testExitCode -eq 0 -and -not $KeepRawArtifacts) {
  $compactArguments = @{
    ArtifactsRoot = $artifactsRoot;
    RetentionDays = $ArtifactRetentionDays;
    CompactDirectory = $Output;
    KeepFileNames = @('phase-summary.csv', 'latency-summary.csv');
  }
  & (Join-Path $PSScriptRoot 'manage_stress_artifacts.ps1') @compactArguments
}
exit $testExitCode
